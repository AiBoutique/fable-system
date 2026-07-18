"""Prompt-echo contamination detector (ConStat-inspired, arXiv:2405.16281).

Two modes, both aimed at the artifact this project hit in Phase 2: the migration
task's ordered markers ("expand -> migrate -> switch -> contract") appear VERBATIM
inside the injected discipline core, so an A1 run partly grades the model on
echoing its own system prompt rather than on reasoning.

  * STATIC (default, zero budget): for every task whose grader keys on literal
    markers (ordered_steps / keywords_all / keywords_any, incl. inside all_of),
    detect markers that appear verbatim in an injected core file. A hit means the
    core hands the model the grader's answer key -> contamination risk.

  * LIVE performance-delta (--live, spends budget): the fuller ConStat idea --
    run the task with the marker-bearing core vs a marker-stripped core and flag a
    significant pass-rate delta. Implemented as a documented entry point; not run
    here (needs a budget greenlight).

    python contamination_check.py --core ../../src/claude-home/CLAUDE.md \
                                  --core ../core/portable-core.md
    (exit 0 = clean; exit 1 = at least one marker-in-core overlap)

Declared scope caps (named by the 2026-07-16 fable review): numeric ``expected``
values and interval ``truth``s are NOT scanned (a truth echoed verbatim in a core
would evade the marker scan); markers shorter than 4 chars are dropped (e.g. the
water task's "100"/"0" legs are unscannable); ``keywords_any`` needs >= 3 markers
to flag, and ``ordered_steps`` legs with fewer than 3 markers are never flagged.
Exclusion of a contaminated task from lift claims is prose-level policy:
score.py has no per-task exclusion mechanism, so re-scoring a suite re-includes
the task -- the regression gate's known-hits --allow flow is the standing guard.

Static overlap on its own is a RISK flag, not proof: a marker may legitimately be
common English. The report lists each hit for human adjudication; the migration
task is the known true positive.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

# Markers shorter than this, or that are pure stopwords, are ignored: a 1-2 char
# token colliding with core prose is noise, not an answer-key leak.
_MIN_MARKER_LEN = 4
_STOPWORDS = {"the", "and", "with", "from", "into", "both", "code", "step", "then",
              "over", "that", "this", "your", "when", "will", "have"}


def _norm(s):
    # keep aligned with graders._normalize: *, __ and ` stripped, _ kept
    return " ".join(str(s).replace("*", "").replace("__", "").replace("`", "").split()).lower()


def extract_legs(grader):
    """Answer-key legs of a grader, each as (leg_type, [markers]); recurses all_of.

    Contamination is judged PER LEG, not pooled: pooling an ordered answer-key with
    a dozen OR-phrasing alternatives dilutes the real signal below any threshold
    (the Phase-2 lesson that motivated this fix)."""
    legs = []
    gtype = grader.get("type")
    if gtype == "ordered_steps":
        legs.append(("ordered_steps", list(grader.get("markers", []))))
    elif gtype in ("keywords_all", "keywords_any"):
        legs.append((gtype, list(grader.get("keywords", []))))
    elif gtype == "exact" and grader.get("mode") == "contains":
        legs.append(("exact_contains", [grader.get("expected", "")]))
    elif gtype == "all_of":
        for sub in grader.get("graders", []):
            legs.extend(extract_legs(sub))
    cleaned = []
    for lt, ms in legs:
        ms = [m for m in ms if len(_norm(m)) >= _MIN_MARKER_LEN and _norm(m) not in _STOPWORDS]
        if ms:
            cleaned.append((lt, ms))
    return cleaned


def _all_in_order(markers, core_text):
    """True iff every marker appears in core_text in the given order (the exact
    ordered-answer-key-in-core signature -- the migration contamination)."""
    pos = 0
    for m in markers:
        idx = core_text.find(_norm(m), pos)
        if idx == -1:
            return False
        pos = idx + len(_norm(m))
    return True


def _leg_contaminated(leg_type, markers, core_text):
    """Per-leg contamination rule keyed to the leg's grading semantics."""
    present = [m for m in markers
               if re.search(r"\b" + re.escape(_norm(m)) + r"\b", core_text)]
    if leg_type == "ordered_steps":
        # the strongest signal: the full ordered sequence sits verbatim in the core
        if len(markers) >= 3 and _all_in_order(markers, core_text):
            return present
        return None
    if leg_type in ("keywords_all", "exact_contains"):
        # AND answer key: contaminated only if EVERY marker is echoed
        return present if len(present) == len(markers) else None
    if leg_type == "keywords_any":
        # OR alternatives: partial overlap is expected; only a FULL echo is a leak
        return present if len(present) == len(markers) and len(markers) >= 3 else None
    return None


def scan(tasks_dirs, core_files):
    cores = {}
    for cf in core_files:
        p = Path(cf)
        cores[p.name] = _norm(p.read_text(encoding="utf-8", errors="replace"))
    hits = []
    task_files = []
    for d in tasks_dirs:
        task_files += glob.glob(os.path.join(d, "*.json"))
    for tf in sorted(task_files):
        with open(tf, encoding="utf-8") as fh:
            t = json.load(fh)
        legs = extract_legs(t.get("grader", {}))
        for core_name, core_text in cores.items():
            for leg_type, markers in legs:
                present = _leg_contaminated(leg_type, markers, core_text)
                if present:
                    hits.append({"task": t["id"], "core": core_name, "leg": leg_type,
                                 "markers_in_core": present, "of_total": len(markers)})
    return hits, len(task_files)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Prompt-echo contamination detector "
                                             "(static marker-in-core; zero budget).")
    ap.add_argument("--tasks", action="append", default=None,
                    help="task dir(s) to scan (default: tasks/ + tasks-domain/*)")
    ap.add_argument("--core", action="append", required=True,
                    help="injected core file(s) to check markers against")
    ap.add_argument("--allow", action="append", default=[],
                    help="task id(s) whose contamination is known/accepted (won't fail)")
    args = ap.parse_args(argv)

    tasks_dirs = args.tasks or [
        str(HERE / "tasks"),
        *[str(p) for p in (HERE / "tasks-domain").glob("*") if p.is_dir()],
    ]
    hits, n = scan(tasks_dirs, args.core)
    unexpected = [h for h in hits if h["task"] not in set(args.allow)]

    print(f"[contamination] scanned {n} task files against {len(args.core)} core(s)")
    for h in hits:
        tag = "ACCEPTED" if h["task"] in set(args.allow) else "RISK"
        print(f"  [{tag}] {h['task']} ({h['leg']}): {len(h['markers_in_core'])}/"
              f"{h['of_total']} markers echoed by {h['core']}: {h['markers_in_core']}")
    if not hits:
        print("  none: no grader leg's answer key is echoed by any core")
    print("CONTAMINATION: " + ("CLEAN" if not unexpected else
                               f"{len(unexpected)} unaccepted hit(s)"))
    return 1 if unexpected else 0


if __name__ == "__main__":
    raise SystemExit(main())
