"""Model adapters -- the portability boundary (README section 4).

The ONLY model-specific surface. Tasks, graders and scoring all sit ABOVE this
interface, so porting the benchmark to a new model is: write one adapter, re-run
the same tasks. That is the whole portability story.

Interface (module-level dispatcher):

    run(adapter, system_core, task_prompt, tools=None) -> {"output": str, "meta": dict}

``adapter`` is an *adapter spec*: either a bare string naming the adapter
("claude_cli" | "grok" | "openai"), or a dict such as
``{"name": "claude_cli", "model": "claude-opus-4-8", "dry_run": True}``. The spec
(not the call signature) carries the model id and the dry_run flag, which keeps
the signature itself model-agnostic, exactly as the contract requires.

Condition -> call mapping (owned by run.py, encoded here via ``system_core``):
    A0 (bare)    : system_core = None  -> a disposable EMPTY config-home
                   (CLAUDE_CONFIG_DIR -> fresh temp dir, no CLAUDE.md/skills):
                   the genuine core-free floor.
    A1 (+core)   : system_core = <portable core text> -> injected via
                   --append-system-prompt, otherwise a clean config-home, so the
                   ONLY difference from A0 is the core text (a clean lift).
    R  (ref bar) : system_core = None on the reference model's adapter.

Every adapter honors ``dry_run`` (default True) and returns a deterministic
placeholder without spending budget; the real path is taken only when
``dry_run`` is False (a budget-spending, user-greenlit step). claude_cli uses
the CLI's own auth (no key handled). grok/openai (Phase 4) read their API key
from an environment variable at call time -- the key is never stored in meta,
argv, or logs; their live behavior is UNVERIFIED until run with a real key.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

__all__ = ["run", "claude_cli", "grok", "openai", "ADAPTERS"]

# Overridable for tests / non-standard installs; defaults to the CLI on PATH.
DEFAULT_CLAUDE_BIN = os.environ.get("CLAUDE_BIN", "claude")
DEFAULT_MODEL = "claude-opus-4-8"


def _spec(adapter):
    """Coerce an adapter argument into a spec dict with at least a 'name'."""
    if isinstance(adapter, str):
        return {"name": adapter}
    if isinstance(adapter, dict) and "name" in adapter:
        return dict(adapter)
    raise ValueError("adapter must be a name string or a dict with a 'name' field")


def _cond_label(system_core):
    return "A1(+core)" if system_core is not None else "A0/R(bare)"


def _redact_cmd(cmd):
    """Return a copy of the argv with the (long) portable-core value redacted, so
    a stored/echoed command never dumps the whole system prompt."""
    out = []
    i = 0
    while i < len(cmd):
        tok = cmd[i]
        out.append(tok)
        if tok == "--append-system-prompt" and i + 1 < len(cmd):
            out.append(f"<portable-core:{len(cmd[i + 1])} chars>")
            i += 2
            continue
        if tok == "--append-system-prompt-file" and i + 1 < len(cmd):
            out.append("<portable-core-file>")
            i += 2
            continue
        i += 1
    return out


_SWEPT_STALE = False


def _sweep_stale_config_homes(max_age_hours=24):
    """Best-effort removal of amp-cfg-* temp homes left by crashed live runs --
    each contains a copied ``.credentials.json``, so a hard kill mid-cell leaves
    OAuth credentials at rest in %TEMP% (2026-07-16 security review). Only dirs
    older than ``max_age_hours`` are touched, so concurrent live runs are safe.
    Runs once per process, before the first temp home is created."""
    global _SWEPT_STALE
    if _SWEPT_STALE:
        return
    _SWEPT_STALE = True
    cutoff = time.time() - max_age_hours * 3600
    try:
        tmp = tempfile.gettempdir()
        for name in os.listdir(tmp):
            if name.startswith("amp-cfg-"):
                p = os.path.join(tmp, name)
                try:
                    if os.path.isdir(p) and os.path.getmtime(p) < cutoff:
                        shutil.rmtree(p, ignore_errors=True)
                except OSError:
                    pass  # best-effort: a locked dir is left for the next sweep
    except OSError:
        pass


def _build_claude_invocation(bin_path, model, system_core, task_prompt, tools, create=False):
    """Build the ``claude -p`` invocation for one (task x condition) cell.

    Returns ``(cmd, env, config_home, cleanup)``. The entire A0-vs-A1 difference
    lives here:

      * a disposable EMPTY config-home is always used (CLAUDE_CONFIG_DIR), so no
        live CLAUDE.md/skills leak into either condition -- mirroring
        run-selftest.ps1's sandbox pattern (config only ever touches a throwaway
        temp home; the live machine is untouched);
      * A1 additionally injects the portable core via --append-system-prompt.

    ``create=False`` (dry-run) does NOT touch the filesystem: it describes the
    intended temp config-home instead of making one, so the call is inspectable
    and hermetic. ``create=True`` (real run) makes the temp dir and returns a
    cleanup that removes it.
    """
    env = dict(os.environ)

    if create:
        _sweep_stale_config_homes()
        config_home = tempfile.mkdtemp(prefix="amp-cfg-")
        # Copy ONLY the OAuth credentials into the isolated home so the subprocess
        # authenticates, while NO CLAUDE.md / skills / settings.json load there --
        # a genuinely core-free baseline (structural bareness; not model-attested).
        try:
            _src = os.path.join(os.path.expanduser("~"), ".claude", ".credentials.json")
            if os.path.isfile(_src):
                shutil.copy2(_src, os.path.join(config_home, ".credentials.json"))
        except OSError:
            pass  # a copy failure surfaces later as a visible auth error, never silent

        def cleanup():
            shutil.rmtree(config_home, ignore_errors=True)
    else:
        # Described, not created -- kept out of any run-log to avoid leaking a
        # machine-specific temp path.
        config_home = os.path.join(tempfile.gettempdir(), "amp-cfg-<disposable>")

        def cleanup():
            return None

    # Isolate config so A0 is genuinely core-free (and A1 carries ONLY the core).
    env["CLAUDE_CONFIG_DIR"] = config_home

    cmd = [bin_path, "-p", str(task_prompt), "--model", str(model)]
    if system_core is not None:
        if create:
            # Write the (potentially large) portable core to a file in the isolated
            # home and pass it by path -- avoids OS argv length limits on big cores.
            core_file = os.path.join(config_home, "_core.txt")
            with open(core_file, "w", encoding="utf-8") as fh:
                fh.write(str(system_core))
            cmd += ["--append-system-prompt-file", core_file]
        else:
            cmd += ["--append-system-prompt", str(system_core)]
    # ``tools`` is reserved for Phase 1+ (e.g. --allowedTools); recorded in meta,
    # not enforced here, so the Phase 0 signature stays honest.
    return cmd, env, config_home, cleanup


def _placeholder_output(name, model, cond_label, task_prompt):
    snippet = str(task_prompt)[:60]
    return (f"[DRY-RUN placeholder | adapter={name} model={model} "
            f"condition={cond_label}] no model called, no budget spent. "
            f"task starts: {snippet!r}")


def claude_cli(spec, system_core, task_prompt, tools=None):
    """Invoke ``claude -p`` headless for one (task x condition) cell.

    * A0/bare (``system_core is None``): run in a disposable, EMPTY config-home so
      the model sees no CLAUDE.md / skills / settings -- the true core-free floor.
    * A1/+core (``system_core`` is a str): inject ONLY the portable core via
      ``--append-system-prompt``, still from a clean config-home, so the sole
      difference from A0 is the core text.

    ``dry_run`` (default True): build the command + isolated env, call NOTHING,
    return a deterministic placeholder. Uses the CLI's own auth; no API key is
    read or passed. Set ``dry_run=False`` only in a budget-greenlit Phase 1+ run.
    """
    model = spec.get("model", DEFAULT_MODEL)
    dry_run = spec.get("dry_run", True)
    bin_path = spec.get("cli_path", DEFAULT_CLAUDE_BIN)
    timeout = spec.get("timeout", 600)
    cond = _cond_label(system_core)

    cmd, env, config_home, cleanup = _build_claude_invocation(
        bin_path, model, system_core, task_prompt, tools, create=not dry_run
    )
    meta = {
        "adapter": "claude_cli",
        "model": model,
        "dry_run": bool(dry_run),
        "condition": cond,
        "core_injected": system_core is not None,
        "config_home": "<disposable-temp-config-home>",
        "cmd": _redact_cmd(cmd),
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    try:
        if dry_run:
            meta["note"] = "dry-run: no subprocess spawned; no model budget spent"
            return {
                "output": _placeholder_output("claude_cli", model, cond, task_prompt),
                "meta": meta,
            }
        # --- real path (Phase 1+, taken ONLY when dry_run is False) ---
        # cwd = the isolated home (a neutral dir with no project CLAUDE.md), so the
        # baseline is free of BOTH user- and project-level discipline.
        # encoding pinned: the CLI emits UTF-8; Windows text-mode would decode
        # cp1252 and mojibake non-ASCII output (seen in the Phase-1 run-log).
        proc = subprocess.run(cmd, env=env,
                              cwd=config_home if os.path.isdir(config_home) else None,
                              capture_output=True, text=True, timeout=timeout,
                              encoding="utf-8", errors="replace")
        meta["returncode"] = proc.returncode
        if proc.returncode != 0:
            meta["stderr_tail"] = (proc.stderr or "")[-500:]
        return {"output": proc.stdout or "", "meta": meta}
    finally:
        cleanup()


def _openai_compat(name, key_env, base_url_default, default_model,
                   spec, system_core, task_prompt):
    """Shared implementation for OpenAI-compatible chat-completions APIs.

    ``system_core`` becomes the system message (the A1 injection point); the
    task prompt is the user message. The API key is read from the environment
    at call time (``key_env``) and is NEVER stored in meta, argv, or logs.
    Endpoint shape (POST {base}/chat/completions, Bearer auth) verified against
    the providers' docs 2026-07-16; ``base_url`` is overridable via the spec or
    ``<NAME>_BASE_URL`` env var so doc drift never requires a code change.
    """
    model = spec.get("model") or default_model
    if not model:
        raise RuntimeError(f"{name}: no model id in adapter spec and no default; "
                           f"pass {{'model': ...}} explicitly")
    dry_run = spec.get("dry_run", True)
    timeout = spec.get("timeout", 300)
    base_url = (spec.get("base_url")
                or os.environ.get(f"{name.upper()}_BASE_URL", base_url_default)).rstrip("/")
    # A userinfo-bearing URL (user:pass@host) is both a credential-at-rest hazard (the
    # endpoint is persisted verbatim in run-log meta) and a loopback-guard bypass
    # (naive host parses see the userinfo, urllib connects to the real host) --
    # reject it outright, for keyed and keyless calls alike (2026-07-17 security review).
    _sp = urllib.parse.urlsplit(base_url)
    if _sp.username is not None or _sp.password is not None:
        raise RuntimeError(f"{name}: base_url must not carry userinfo credentials "
                           f"(user:pass@host); keys are env-var-only, never URLs")
    cond = _cond_label(system_core)
    meta = {
        "adapter": name,
        "model": model,
        "dry_run": bool(dry_run),
        "condition": cond,
        "core_injected": system_core is not None,
        "endpoint": f"{base_url}/chat/completions",
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    if dry_run:
        meta["note"] = "dry-run: no request sent; no budget spent"
        return {"output": _placeholder_output(name, model, cond, task_prompt), "meta": meta}

    key = os.environ.get(key_env)
    if not key:
        # Local OpenAI-compatible servers (Ollama, LM Studio, llama.cpp) accept any
        # bearer token. allow_keyless must be EXPLICIT in the spec and is honored only
        # for loopback base_urls, so a mistyped cloud call can never go out unkeyed.
        # urlsplit().hostname is the SAME parse urllib connects with (and strips IPv6
        # brackets), so guard and connection can no longer disagree (2026-07-17 review:
        # the previous string-split parse was defeated by userinfo forms).
        host = (urllib.parse.urlsplit(base_url).hostname or "").lower()
        if spec.get("allow_keyless") and host in ("localhost", "127.0.0.1", "::1"):
            key = "sk-local-keyless"
        else:
            raise RuntimeError(
                f"{name}: {key_env} is not set. Export the API key as an environment "
                f"variable; it is read at call time and never logged or passed on argv. "
                f"(Local keyless endpoints: pass {{'allow_keyless': True}} with a "
                f"loopback base_url.)")

    messages = []
    if system_core is not None:
        messages.append({"role": "system", "content": str(system_core)})
    messages.append({"role": "user", "content": str(task_prompt)})
    body = json.dumps({"model": model, "messages": messages}).encode("utf-8")
    req = urllib.request.Request(
        f"{base_url}/chat/completions", data=body, method="POST",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.load(resp)
        # A 200 response can still be a non-answer: an {"error": ...} envelope
        # (gateway/proxy pattern) or a turn with content:null (tool-call or
        # safety-filtered). Both must be INFRA-FAILURE exclusions, never a
        # legitimate empty answer scored 0.0 (2026-07-17 review finding).
        if isinstance(data, dict) and data.get("error"):
            meta["returncode"] = 1
            meta["stderr_tail"] = repr(data.get("error"))[:500]
            return {"output": "", "meta": meta}
        content = (data.get("choices") or [{}])[0].get("message", {}).get("content")
        if content is None:
            meta["returncode"] = 1
            meta["stderr_tail"] = "HTTP 200 carried no message content (content:null)"
            return {"output": "", "meta": meta}
        meta["returncode"] = 0
        return {"output": content, "meta": meta}
    except urllib.error.HTTPError as e:
        # mirror claude_cli's failure contract: empty output + diagnostic meta
        meta["returncode"] = e.code
        meta["stderr_tail"] = (e.read() or b"")[-500:].decode("utf-8", "replace")
        return {"output": "", "meta": meta}
    except urllib.error.URLError as e:
        # DNS / connection failures follow the same loud-but-contained contract
        meta["returncode"] = 1
        meta["stderr_tail"] = f"URLError: {e.reason}"[-500:]
        return {"output": "", "meta": meta}


def grok(spec, system_core, task_prompt, tools=None):
    """xAI adapter (Phase 4). OpenAI-SDK-compatible chat completions at
    https://api.x.ai/v1 + /chat/completions (verified 2026-07-16, docs.x.ai);
    key from XAI_API_KEY. Current ids grok-4.5 (recommended) / grok-4.3 -- but NO
    default is assumed (ids churn): pass {'model': ...} in the spec. xAI's newer
    preferred endpoint is /responses; /chat/completions stays the portable choice.
    See ../core/adapter-targets.md. ``dry_run`` defaults True; live use is a
    budget-spending, user-greenlit step, UNVERIFIED until run with a real key."""
    return _openai_compat("grok", "XAI_API_KEY", "https://api.x.ai/v1",
                          None, spec, system_core, task_prompt)


def openai(spec, system_core, task_prompt, tools=None):
    """OpenAI adapter (Phase 4). Chat completions at https://api.openai.com/v1 +
    /chat/completions; key from OPENAI_API_KEY. Current flagship ids gpt-5.6
    (alias of gpt-5.6-sol) / gpt-5.6-terra / gpt-5.6-luna (verified 2026-07-16,
    developers.openai.com) -- but NO default is assumed (ids churn): pass
    {'model': ...} in the spec. OpenAI's newer primary is the Responses API
    (/responses); /chat/completions stays the portable choice. See
    ../core/adapter-targets.md. ``dry_run`` defaults True; UNVERIFIED until run
    with a real key."""
    return _openai_compat("openai", "OPENAI_API_KEY", "https://api.openai.com/v1",
                          None, spec, system_core, task_prompt)


ADAPTERS = {
    "claude_cli": claude_cli,
    "grok": grok,
    "openai": openai,
}


def run(adapter, system_core, task_prompt, tools=None):
    """Dispatch to the named adapter; return ``{"output": str, "meta": dict}``.

    ``adapter``     : adapter spec (name string or dict with 'name'; see module docstring).
    ``system_core`` : None for bare (A0 / R), the portable-core text for A1.
    ``task_prompt`` : the task's prompt string.
    ``tools``       : optional tool list, reserved for Phase 1+ (recorded, not enforced).
    """
    spec = _spec(adapter)
    name = spec["name"]
    fn = ADAPTERS.get(name)
    if fn is None:
        raise ValueError(f"unknown adapter: {name!r} (known: {sorted(ADAPTERS)})")
    result = fn(spec, system_core, task_prompt, tools)
    if not isinstance(result, dict) or "output" not in result or "meta" not in result:
        raise ValueError("adapter must return a dict with 'output' and 'meta'")
    if tools is not None:
        # "recorded, not enforced" (schema.md): the run-log keeps the requested
        # tool list even though Phase 0 adapters do not act on it
        result["meta"].setdefault("tools", tools)
    return result
