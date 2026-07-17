"""Phase 5 continuous-verification gate (dossier P0.3, README section 5).

Zero-budget by default: asserts the measurement machinery and the amplification
core's structural integrity without a single model call. Rungs:

  1. harness selftest        (selftest.py subprocess -> SELFTEST: PASS)
  2. answer provenance       (verify_answers.py subprocess -> exit 0)
  3. config-drift guard      (live ~/.claude files == kit src/claude-home copies:
                              EXACT files by SHA-256; TEMPLATED files by marker;
                              settings.json by discipline content minus personal
                              overlays -- see MIRRORED_* below)
  4. non-negotiable lint     (shared non-negotiable markers present in the live
                              CLAUDE.md, the fable-mode skill, AND the portable core)
  5. currency baseline       (dated facts in core/currency-baseline.json not
                              older than their max_age_days)
  6. contamination guard     (no grader answer-key echoed verbatim in an injected
                              core, beyond the known/accepted set)

An optional live canary (--live-canary <tasks-dir>) re-measures lift on a small
task set; it SPENDS MODEL BUDGET and stays off unless explicitly passed — never
wire it into an unattended schedule without a per-run greenlight.

    python regression_gate.py [--report out.txt] [--claude-home DIR] [--kit-src DIR]

Exit 0 = all rungs pass; exit 1 = at least one failure (report says which).
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
AMP = HERE.parent                      # amplification/
DEFAULT_KIT_SRC = AMP.parent / "src" / "claude-home"
DEFAULT_CLAUDE_HOME = Path(os.path.expanduser("~")) / ".claude"
DEFAULT_BASELINE = AMP / "core" / "currency-baseline.json"
PORTABLE_CORE = AMP / "core" / "portable-core.md"

# The kit-mirrored files (src/claude-home relative). The 24 expertise skills are
# deliberately NOT here: their kit membership is an open owner decision (dossier
# P0.1) and the gate guards only what the kit claims to mirror.
#
# EXACT      -> refresh-kit syncs these live->src verbatim; compared by SHA-256.
# TEMPLATED  -> the refresh-kit scrub gate deliberately genericizes the kit copy
#               (personal profile lines), so hash equality is the WRONG check;
#               instead both copies must exist and carry the load-bearing marker.
# SETTINGS   -> settings.json legitimately diverges by PERSONAL OVERLAY (only `tui`
#               is genuinely live-only here; the kit template already ships theme/
#               autoUpdatesChannel/skipWorkflowUsageWarning) and by cosmetic JSON
#               key order, so a whole-file HASH false-flags it. Compared instead on
#               its DISCIPLINE content: the full parsed settings MINUS the personal
#               keys (order-insensitive; catches drift in hooks, matchers, timeouts,
#               and any non-personal top-level key -- not just hook commands).
MIRRORED_EXACT = [
    "CLAUDE.md",
    "skills/fable-mode/SKILL.md",
    "skills/fable-mode/references/gold-standards.md",  # reclassify to TEMPLATED if a future scrub genericizes it
    "skills/refresh-kit/SKILL.md",
    "scheduled-tasks/fable-health-check/SKILL.md",
]
MIRRORED_TEMPLATED = {
    "skills/invest-research/SKILL.md": "never write holdings",
    "skills/organize/SKILL.md": "never uploaded",
}
# Top-level settings keys that are personal/machine preferences (UI/update prefs);
# their presence or divergence in the live home vs the kit is expected, not drift.
# `tui` is live-only here; theme/autoUpdatesChannel/skipWorkflowUsageWarning are in
# both. Stripping all four from both sides before compare tolerates the overlay
# while everything else (hooks, matchers, timeouts, other keys) must match.
SETTINGS_PERSONAL_KEYS = {"theme", "tui", "autoUpdatesChannel",
                          "skipWorkflowUsageWarning"}


def _settings_discipline(settings_path):
    """The full parsed settings.json with personal-overlay keys removed -- the
    discipline surface. Dict compare is order-insensitive, so it tolerates JSON
    key reordering while catching ANY substantive change (a hook command, a
    matcher, a timeout, or a new/removed non-personal top-level key)."""
    data = json.loads(Path(settings_path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"settings.json is not a JSON object (got {type(data).__name__})")
    return {k: v for k, v in data.items() if k not in SETTINGS_PERSONAL_KEYS}

# Shared non-negotiables that must appear (case-insensitive) in the live
# discipline file, the fable-mode skill, and the portable core alike.
NON_NEGOTIABLE_MARKERS = ["manufactured pass", "never obey", "recovery path", "secrets"]


def _sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(65536), b""):
            h.update(block)
    return h.hexdigest()


class Gate:
    def __init__(self):
        self.lines = []
        self.failures = 0

    def result(self, rung, ok, detail):
        self.lines.append(f"[{'PASS' if ok else 'FAIL'}] {rung}: {detail}")
        if not ok:
            self.failures += 1

    def report(self):
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        head = f"REGRESSION GATE {stamp} -> {'PASS' if self.failures == 0 else 'FAIL'}"
        return "\n".join([head, *self.lines,
                          f"{len(self.lines)} rungs, {self.failures} failure(s)"])


def rung_selftest(g):
    p = subprocess.run([sys.executable, str(HERE / "selftest.py")],
                       capture_output=True, text=True, encoding="utf-8",
                       errors="replace", timeout=300)
    ok = p.returncode == 0 and "SELFTEST: PASS" in (p.stdout or "")
    tail = (p.stdout or p.stderr or "").strip().splitlines()[-1:]
    g.result("harness selftest", ok, tail[0] if tail else f"rc={p.returncode}")


def rung_answers(g):
    p = subprocess.run([sys.executable, str(HERE / "verify_answers.py")],
                       capture_output=True, text=True, encoding="utf-8",
                       errors="replace", timeout=300)
    ok = p.returncode == 0
    tail = (p.stdout or p.stderr or "").strip().splitlines()[-1:]
    g.result("answer provenance", ok, tail[0] if tail else f"rc={p.returncode}")


def rung_drift(g, claude_home, kit_src):
    drifted, missing = [], []
    for rel in MIRRORED_EXACT:
        live, src = claude_home / rel, kit_src / rel
        if not src.is_file():
            missing.append(f"kit:{rel}")
        elif not live.is_file():
            missing.append(f"live:{rel}")
        elif _sha256(live) != _sha256(src):
            drifted.append(rel)
    for rel, marker in MIRRORED_TEMPLATED.items():
        for side, base in (("live", claude_home), ("kit", kit_src)):
            f = base / rel
            if not f.is_file():
                missing.append(f"{side}:{rel}")
            elif marker.lower() not in f.read_text(encoding="utf-8",
                                                   errors="replace").lower():
                drifted.append(f"{side}:{rel} (marker {marker!r} missing)")
    # settings.json: compare DISCIPLINE (everything minus personal overlays)
    live_s, src_s = claude_home / "settings.json", kit_src / "settings.json"
    if not live_s.is_file() or not src_s.is_file():
        missing.append("settings.json")
    else:
        try:
            if _settings_discipline(live_s) != _settings_discipline(src_s):
                drifted.append("settings.json (discipline content differs -- real "
                               "drift in hooks/matchers/timeouts or a non-personal "
                               "key, not a personal-pref/ordering diff)")
        except (ValueError, KeyError, TypeError, AttributeError) as e:
            drifted.append(f"settings.json (unparseable/malformed: {e!r})")
    ok = not drifted and not missing
    detail = ("exact mirrors identical; templated mirrors carry their markers; "
              "settings discipline (minus personal overlays) matches" if ok else
              f"drifted={drifted} missing={missing} -- diff them, then /refresh-kit "
              f"(live->kit) or reinstall (kit->live); never blind-overwrite")
    g.result("config-drift guard", ok, detail)


def rung_non_negotiables(g, claude_home, kit_src):
    files = [claude_home / "CLAUDE.md",
             kit_src / "skills" / "fable-mode" / "SKILL.md",
             PORTABLE_CORE]
    live_skill = claude_home / "skills" / "fable-mode" / "SKILL.md"
    if live_skill.is_file():
        files.append(live_skill)  # lint the live skill too, not just the kit copy
    problems = []
    for f in files:
        if not f.is_file():
            problems.append(f"missing: {f.name}")
            continue
        text = f.read_text(encoding="utf-8", errors="replace").lower()
        for m in NON_NEGOTIABLE_MARKERS:
            if m not in text:
                problems.append(f"{f.name} lacks {m!r}")
    g.result("non-negotiable lint", not problems,
             "all shared markers present in all three carriers" if not problems
             else "; ".join(problems))


def rung_currency(g, baseline_path):
    if not baseline_path.is_file():
        g.result("currency baseline", False, f"missing: {baseline_path}")
        return
    try:
        data = json.loads(baseline_path.read_text(encoding="utf-8"))
        if not data.get("entries"):
            # a baseline with no dated facts guards nothing -- a green "0 facts
            # fresh" rung reads as protection it doesn't provide (2026-07-17 review)
            g.result("currency baseline", False, "baseline lists no dated facts (nothing to guard)")
            return
        today = _dt.date.today()
        stale = []
        for e in data.get("entries", []):
            age = (today - _dt.date.fromisoformat(e["verified"])).days
            if age > int(e["max_age_days"]):
                stale.append(f"{e['fact']} (verified {e['verified']}, {age}d old, "
                             f"max {e['max_age_days']}d)")
    except (ValueError, KeyError, TypeError) as e:
        # a malformed baseline is a FAILING rung, never an unreported traceback
        g.result("currency baseline", False, f"malformed baseline: {e!r}")
        return
    g.result("currency baseline", not stale,
             f"{len(data.get('entries', []))} dated facts fresh" if not stale
             else "STALE: " + "; ".join(stale))


def rung_live_canary(g, tasks_dir, core):
    """Budget-spending optional rung: tiny live A0/A1 re-measure via run.py."""
    import tempfile
    # never write model outputs into the publishable repo tree
    out = Path(tempfile.gettempdir()) / f"amp-canary-{time.strftime('%Y%m%d-%H%M%S')}.json"
    cmd = [sys.executable, str(HERE / "run.py"), "--no-dry-run",
           "--conditions", "A0,A1", "--tasks", str(tasks_dir), "--out", str(out)]
    if core:
        cmd += ["--core", str(core)]
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                       errors="replace", timeout=3600)
    ok = p.returncode == 0 and out.is_file()
    detail = f"rc={p.returncode} runlog={out.name if out.is_file() else 'MISSING'}"
    if ok:
        import score  # local import; sits next to this file
        agg = score.aggregate(score.load_runlog(str(out)))
        detail += f" lift={agg['overall'].get('lift', float('nan')):+.3f}"
    g.result("live canary (budget spent)", ok, detail)


# Prompt-echo contamination that is KNOWN and documented (the task carries a
# contamination warning + is excluded from lift claims). New overlaps must be
# reviewed, not silently accepted. Keyed by (task, core) so accepting the known
# hit in CLAUDE.md never silently pre-accepts a NEW echo of it in another core.
KNOWN_CONTAMINATION = {("plan-zero-downtime-migration-001", "CLAUDE.md")}


def rung_contamination(g, kit_src):
    """Static prompt-echo contamination: does any grader's answer key sit verbatim
    in an injected core? (Zero budget; the Phase-2 migration artifact is the known
    true positive, pre-accepted here.)"""
    try:
        import contamination_check as cc
    except Exception as e:  # noqa: BLE001
        g.result("contamination guard", False, f"could not import checker: {e!r}")
        return
    cores = [kit_src / "CLAUDE.md", PORTABLE_CORE]
    cores = [str(c) for c in cores if c.is_file()]
    if not cores:
        # zero cores on disk = a vacuous scan that always "passes"; if the core
        # paths move, this rung must FAIL loudly, not green out (2026-07-17 review)
        g.result("contamination guard", False, "no injected cores found on disk (guard is vacuous)")
        return
    tasks_dirs = [str(HERE / "tasks"),
                  *[str(p) for p in (HERE / "tasks-domain").glob("*") if p.is_dir()],
                  # every calibration suite too — the guard previously scanned only
                  # tasks/ + tasks-domain/, leaving the calib beds (including the
                  # +16.7pp tight-anchor suite) unscanned (2026-07-17 review)
                  *[str(p) for p in sorted(HERE.glob("tasks-calib-*")) if p.is_dir()]]
    hits, n = cc.scan(tasks_dirs, cores)
    if n == 0:
        g.result("contamination guard", False, "no tasks scanned (guard is vacuous)")
        return
    unexpected = [h for h in hits if (h["task"], h["core"]) not in KNOWN_CONTAMINATION]
    detail = (f"{n} tasks x {len(cores)} cores; {len(hits)} known/{len(unexpected)} new"
              if hits else f"{n} tasks x {len(cores)} cores; no answer-key echo")
    if unexpected:
        detail += " -- NEW: " + ", ".join(f"{h['task']}({h['leg']})" for h in unexpected)
    g.result("contamination guard", not unexpected, detail)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Amplification regression gate "
                                             "(zero-budget by default).")
    ap.add_argument("--claude-home", default=str(DEFAULT_CLAUDE_HOME))
    ap.add_argument("--kit-src", default=str(DEFAULT_KIT_SRC))
    ap.add_argument("--baseline", default=str(DEFAULT_BASELINE))
    ap.add_argument("--report", default=None, help="also write the report to this path")
    ap.add_argument("--live-canary", default=None, metavar="TASKS_DIR",
                    help="OPTIONAL budget-spending lift re-measure on this task dir")
    ap.add_argument("--canary-core", default=None,
                    help="core file for the canary's A1 (default: run.py stub)")
    args = ap.parse_args(argv)

    if str(HERE) not in sys.path:
        sys.path.insert(0, str(HERE))

    g = Gate()
    rung_selftest(g)
    rung_answers(g)
    rung_drift(g, Path(args.claude_home), Path(args.kit_src))
    rung_non_negotiables(g, Path(args.claude_home), Path(args.kit_src))
    rung_currency(g, Path(args.baseline))
    rung_contamination(g, Path(args.kit_src))
    if args.live_canary:
        rung_live_canary(g, Path(args.live_canary), args.canary_core)

    rep = g.report()
    print(rep)
    if args.report:
        Path(args.report).parent.mkdir(parents=True, exist_ok=True)
        Path(args.report).write_text(rep + "\n", encoding="utf-8")
    return 0 if g.failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
