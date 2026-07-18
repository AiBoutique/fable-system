"""Phase 0 CLI runner:  (task x condition) -> adapter -> grader -> run-log JSON.

Defaults to ``--dry-run`` so it NEVER spends model budget unless you pass
``--no-dry-run`` explicitly (a Phase 1+, user-greenlit step). Imports ``graders``
and ``adapters``; writes a run-log consumed by ``score.py``.

    python run.py --model claude-opus-4-8 --conditions A0,A1 --tasks tasks
    python run.py --conditions A0,A1,R --out my-runlog.json      # still dry-run
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))  # allow `python run.py` from any cwd

import adapters  # noqa: E402
import graders   # noqa: E402

CONDITIONS = ("A0", "A1", "R")

# Phase-0 placeholder for the portable core. The REAL core (model-agnostic
# CLAUDE.md + fable-mode discipline + domain skills) is injected in Phase 1 via
# --core <file>; here we only need a non-empty, model-agnostic marker string so
# the A1 wiring is exercised. It is deliberately generic (no Claude specifics).
PORTABLE_CORE_STUB = (
    "PORTABLE AMPLIFICATION CORE (Phase-0 placeholder). Operate with: decompose "
    "the task into checkable sub-claims; name at least one rival hypothesis and "
    "run the cheapest discriminating probe; verify by execution and independent "
    "review before claiming done; plan with a persisted ledger; label every claim "
    "verified / inferred / assumed and state calibrated uncertainty; ground "
    "factual claims in retrieval, not memory."
)


def adapter_for(model):
    """Map a model id to its adapter name (the model-specific surface)."""
    m = (model or "").lower()
    if m.startswith(("grok", "xai")):
        return "grok"
    if m.startswith(("gpt", "o1", "o3", "o4", "openai", "chatgpt")):
        return "openai"
    # default: the only adapter wired in Phase 0
    return "claude_cli"


def spec_and_core(condition, model, reference_model, dry_run, core_text):
    """Return (adapter_spec, system_core) for one condition (README section 3)."""
    if condition == "A0":
        return {"name": adapter_for(model), "model": model, "dry_run": dry_run}, None
    if condition == "A1":
        return {"name": adapter_for(model), "model": model, "dry_run": dry_run}, core_text
    if condition == "R":
        return {"name": adapter_for(reference_model), "model": reference_model, "dry_run": dry_run}, None
    raise ValueError(f"unknown condition: {condition!r} (known: {CONDITIONS})")


def _validate_grader(spec, fname):
    """Reject unknown grader types and empty marker/keyword lists UP FRONT --
    a typo'd type otherwise raises mid-run after budget is spent, and an empty
    list silently degrades the grade (2026-07-16 review finding)."""
    gtype = spec.get("type")
    if gtype not in graders.GRADERS:
        raise ValueError(f"{fname}: unknown grader type {gtype!r} "
                         f"(known: {sorted(graders.GRADERS)})")
    for key in ("keywords", "markers", "forbidden"):
        if key in spec and not spec[key]:
            raise ValueError(f"{fname}: grader {gtype!r} has an empty {key!r} list")
    if gtype == "all_of" and not spec.get("graders"):
        raise ValueError(f"{fname}: all_of grader has an empty 'graders' list")
    for sub in spec.get("graders", []) or []:
        _validate_grader(sub, fname)


def load_tasks(tasks_dir):
    """Load and minimally validate every *.json task in ``tasks_dir``."""
    files = sorted(glob.glob(os.path.join(tasks_dir, "*.json")))
    if not files:
        raise FileNotFoundError(f"no *.json tasks found in {tasks_dir!r}")
    tasks = []
    seen_ids = {}
    for f in files:
        with open(f, encoding="utf-8") as fh:
            t = json.load(fh)
        for field in ("id", "dimension", "prompt", "grader"):
            if field not in t:
                raise ValueError(f"{os.path.basename(f)}: task missing required field {field!r}")
        if t["id"] in seen_ids:
            raise ValueError(f"{os.path.basename(f)}: duplicate task id {t['id']!r} "
                             f"(also in {seen_ids[t['id']]})")
        seen_ids[t["id"]] = os.path.basename(f)
        _validate_grader(t["grader"], os.path.basename(f))
        tasks.append(t)
    return tasks


def _maybe_judge_fallback(task, output, code_grade, model_under_test,
                          judge_model, dry_run):
    """Lenient LLM judge, consulted ONLY when a code grader FAILS a cell.

    Recovers keyword-vocabulary false negatives (a correct answer the code grader
    missed on phrasing) without ever overriding a code PASS. Returns the (possibly
    upgraded) grade dict; on any judge error keeps the original code grade. Off
    unless ``judge_model`` is set (run.py --judge-fallback), and it spends budget.
    """
    if not judge_model or code_grade.get("passed") or code_grade.get("score") is None:
        return code_grade
    try:
        import judge as _judge  # local import; only when the fallback is enabled
        resp = _judge.run_judge(task, output, judge_model, model_under_test,
                                dry_run=dry_run)
        if resp is None:
            return code_grade
        jg = graders.llm_judge(output, judge_response=resp)
    except Exception as e:  # noqa: BLE001 -- a judge failure must never poison scoring
        code_grade = dict(code_grade)
        code_grade["judge_error"] = repr(e)[:200]
        return code_grade
    if jg["passed"]:
        # upgrade, preserving provenance: BOTH grades are kept in the record
        return {"passed": True, "score": jg["score"],
                "detail": f"code-FAIL upgraded by lenient judge ({judge_model}): "
                          f"{jg['detail']} | code said: {code_grade.get('detail', '')[:80]}",
                "code_grade": code_grade, "judge_grade": jg}
    return code_grade


def run_benchmark(model, conditions, tasks, dry_run=True,
                  core_text=PORTABLE_CORE_STUB, reference_model="claude-fable-5",
                  judge_model=None, spec_extra=None):
    """Run every (task x condition) cell through adapter + grader.

    Returns a list of result rows. In dry-run (default) the adapter returns a
    placeholder and nothing spends budget; this proves the pipeline wiring.

    An infra-failed cell (adapter returncode != 0) is NEVER scored as a model
    failure: its grade carries ``score: None`` so the scorer excludes it, and
    the failure is loud in the row. (Live Phase-2 lesson: a transient CLI
    failure otherwise poisons means/lift/gap as a legitimate-looking 0.0.)

    ``judge_model`` (optional, budget-spending): a DIFFERENT model that re-judges
    only the cells a code grader FAILED, blind, as a lenient fallback.
    """
    results = []
    for t in tasks:
        for cond in conditions:
            spec, system_core = spec_and_core(cond, model, reference_model, dry_run, core_text)
            if spec_extra and cond != "R":
                # user-supplied adapter overrides (--adapter-json): base_url,
                # allow_keyless, timeout, or an adapter-name override for local
                # OpenAI-compatible servers. Never carries a key (keys stay env-only);
                # never applied to R — the reference bar must stay the untouched
                # reference adapter/model or gap compares the model to itself
                # (2026-07-17 review, demonstrated by execution).
                spec.update(spec_extra)
            try:
                r = adapters.run(spec, system_core, t["prompt"], tools=t.get("tools"))
            except Exception as e:  # noqa: BLE001
                # One hung/missing-CLI cell, OR a malformed HTTP-200 body
                # (JSONDecodeError / truncated read), must not abort the whole
                # (budget-spending) run: exclude the CELL, keep every completed
                # result (2026-07-16 + 2026-07-17 review findings; same philosophy
                # as rc != 0 below). This try wraps ONLY the adapter call, so a
                # caught exception is always adapter/infra origin, never a grader
                # bug; and an all-cells-excluded run is caught loudly in main().
                results.append({
                    "task_id": t["id"], "dimension": t["dimension"],
                    "condition": cond, "output": "",
                    "grade": {"passed": False, "score": None,
                              "detail": f"INFRA-FAILURE {type(e).__name__}; cell "
                                        f"excluded from scoring -- re-run this cell"},
                    "adapter_meta": {"exception": repr(e)[:200]},
                })
                print(f"[run] WARNING: infra-failure on {t['id']} x {cond} "
                      f"({type(e).__name__})")
                continue
            rc = r["meta"].get("returncode")
            if rc not in (0, None):
                g = {"passed": False, "score": None,
                     "detail": f"INFRA-FAILURE rc={rc}; cell excluded from scoring "
                               f"-- re-run this cell"}
                print(f"[run] WARNING: infra-failure on {t['id']} x {cond} (rc={rc})")
            else:
                g = graders.grade(t["grader"], r["output"])
                # the model that PRODUCED this cell (R is the reference model, not
                # --model) -- so the judge's never-self-grade guard sees the truth
                producer = reference_model if cond == "R" else model
                g = _maybe_judge_fallback(t, r["output"], g, producer, judge_model, dry_run)
            results.append({
                "task_id": t["id"],
                "dimension": t["dimension"],
                "condition": cond,
                "output": r["output"],
                "grade": g,
                "adapter_meta": r["meta"],
            })
    return results


def build_runlog(model, reference_model, conditions, tasks, results, dry_run, tasks_dir,
                 core_text=None, core_path=None):
    meta = {
        "harness_version": "0.1.0",
        "model": model,
        "reference_model": reference_model,
        "conditions": list(conditions),
        "dry_run": bool(dry_run),
        "n_tasks": len(tasks),
        # basename only -- keep machine-specific absolute paths out of the log
        "tasks_dir": Path(tasks_dir).name,
        "created": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "note": ("DRY-RUN: placeholder outputs, no model budget spent"
                 if dry_run else "LIVE run: model budget spent"),
    }
    if core_text is not None and any(c != "A0" and c != "R" for c in conditions):
        # Provenance: WHICH core produced the +core condition(s). Without this,
        # A1 (full core) and A1' (portable core) run-logs are indistinguishable
        # except by external bookkeeping (2026-07-16 review finding). Basename
        # only -- no machine paths in the log.
        meta["core"] = {
            "path": Path(core_path).name if core_path else "<builtin-phase0-stub>",
            "sha256": hashlib.sha256(core_text.encode("utf-8")).hexdigest(),
            "bytes": len(core_text.encode("utf-8")),
        }
    return {"meta": meta, "results": results}


def main(argv=None):
    p = argparse.ArgumentParser(
        description="Phase 0 amplification benchmark runner (dry-run by default; "
                    "no model budget is spent unless --no-dry-run is given).")
    p.add_argument("--model", default="claude-opus-4-8", help="model id under test")
    p.add_argument("--conditions", default="A0,A1",
                   help="comma-separated subset of A0,A1,R")
    p.add_argument("--tasks", default=str(HERE / "tasks"), help="tasks directory")
    p.add_argument("--out", default=None,
                   help="run-log JSON path (default: a timestamped file in the OS temp dir)")
    p.add_argument("--reference-model", default="claude-fable-5",
                   help="model id for condition R (the reference bar; "
                        "'fable-5' is NOT a valid CLI id -- probed 2026-07-16)")
    p.add_argument("--core", default=None,
                   help="path to portable-core text for A1 (default: built-in Phase-0 stub)")
    p.add_argument("--dry-run", dest="dry_run", action="store_true", default=True,
                   help="do not call any model (default)")
    p.add_argument("--no-dry-run", dest="dry_run", action="store_false",
                   help="ACTUALLY invoke the model adapter (Phase 1+, spends budget)")
    p.add_argument("--judge-fallback", default=None, metavar="MODEL",
                   help="a DIFFERENT model id to lenient-judge cells a code grader "
                        "FAILED (blind, ordinal; spends budget; must differ from --model; "
                        "routed via the claude CLI adapter, so it must be a "
                        "claude-CLI-reachable id)")
    p.add_argument("--adapter-json", default=None, metavar="JSON",
                   help="JSON object merged into every adapter spec, e.g. "
                        "'{\"name\":\"openai\",\"base_url\":\"http://localhost:11434/v1\","
                        "\"allow_keyless\":true}' for a local OpenAI-compatible server; "
                        "never pass keys here (keys stay env-only)")
    args = p.parse_args(argv)

    spec_extra = None
    if args.adapter_json:
        try:
            spec_extra = json.loads(args.adapter_json)
        except json.JSONDecodeError as e:
            p.error(f"--adapter-json is not valid JSON: {e}")
        if not isinstance(spec_extra, dict):
            p.error("--adapter-json must be a JSON object")
        def _cred_shaped(k):
            # credential-NAMED fields only; the boolean toggle allow_keyless must pass
            kl = k.lower()
            return (kl == "key" or kl.endswith("_key") or "apikey" in kl
                    or "token" in kl or "secret" in kl or "password" in kl
                    or "bearer" in kl or "credential" in kl or "authorization" in kl)
        leaked = [k for k in spec_extra if _cred_shaped(k)]
        if leaked:
            p.error(f"--adapter-json must not carry credentials ({leaked}); "
                    f"keys are env-var-only, never argv")
        bu = spec_extra.get("base_url")
        if isinstance(bu, str) and "@" in bu.split("//", 1)[-1].split("/", 1)[0]:
            p.error("--adapter-json base_url must not carry userinfo (user:pass@host); "
                    "keys are env-var-only, never URLs or argv")
        overridden = [k for k in ("model", "dry_run") if k in spec_extra]
        if overridden:
            p.error(f"--adapter-json must not carry {overridden}: the model id is "
                    f"--model and live-vs-dry is --dry-run/--no-dry-run — a spec-side "
                    f"override would silently contradict the runlog meta (2026-07-17 review)")

    if args.judge_fallback and args.judge_fallback == args.model:
        p.error("--judge-fallback model must DIFFER from --model (never self-grade)")
    if args.judge_fallback and args.judge_fallback == args.reference_model:
        # Asymmetric leniency: R's code-FAILs would hit the self-grade guard and
        # stay failed while A0/A1's get re-judged, biasing gap in A1's favor
        # (2026-07-16 review finding).
        p.error("--judge-fallback model must DIFFER from --reference-model "
                "(asymmetric leniency would bias the gap metric)")

    conditions = [c.strip() for c in args.conditions.split(",") if c.strip()]
    unknown = [c for c in conditions if c not in CONDITIONS]
    if unknown:
        p.error(f"unknown condition(s) {unknown}; choose from {CONDITIONS}")

    core_text = PORTABLE_CORE_STUB
    if args.core:
        core_text = Path(args.core).read_text(encoding="utf-8")

    tasks = load_tasks(args.tasks)
    results = run_benchmark(args.model, conditions, tasks,
                            dry_run=args.dry_run, core_text=core_text,
                            reference_model=args.reference_model,
                            judge_model=args.judge_fallback,
                            spec_extra=spec_extra)
    runlog = build_runlog(args.model, args.reference_model, conditions, tasks,
                          results, args.dry_run, args.tasks,
                          core_text=core_text, core_path=args.core)

    out = args.out or os.path.join(
        tempfile.gettempdir(), f"amp-runlog-{time.strftime('%Y%m%d-%H%M%S')}.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(runlog, fh, indent=2, ensure_ascii=False)

    mode = "DRY-RUN (no budget spent)" if args.dry_run else "LIVE (budget spent)"
    print(f"[run] {mode}: {len(results)} cells "
          f"({len(tasks)} tasks x {len(conditions)} conditions) -> {out}")
    print(f"[run] score it:  python \"{HERE / 'score.py'}\" \"{out}\"")
    # A run where EVERY cell was infra-excluded (e.g. auth expired mid-run)
    # produces no usable data and must not exit 0: a green process signal on an
    # all-excluded run reads as success (2026-07-17 review finding). Per-cell
    # loudness is already there; this makes the process-level signal honest too.
    scored = [r for r in results if r["grade"].get("score") is not None]
    if results and not scored:
        print(f"[run] ERROR: all {len(results)} cells were infra-excluded (no scored "
              f"cell) -- no usable data; check adapter/auth. Exiting non-zero.")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
