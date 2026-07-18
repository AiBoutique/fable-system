"""Differential re-grade: does a graders.py change flip any grade?

Loads a REFERENCE graders.py (default: the committed HEAD version) and the
working-tree graders.py as two separate modules, grades a battery of probe
outputs per task through both, and reports every disagreement. Zero-budget:
no model calls, no network.

A grader edit is the highest-leverage way to silently move published numbers --
it can turn a real FAIL into a PASS across every stored run at once. This script
makes "the change flips nothing it should not" a reproducible claim instead of an
assertion, per README section 3 (code graders are preferred because they are
reproducible) and CLAUDE.md's rule that every reported number traces to a command.

    python grader_diff.py                    # working tree vs HEAD
    python grader_diff.py --ref <path.py>    # working tree vs an explicit file

Exit 0 always: disagreements are the OUTPUT, not a failure -- an intended fix
produces them by design. Read the list and confirm every line traces to the
intended change; anything else is a regression.
"""
from __future__ import annotations

import argparse
import glob
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TASK_DIRS = ("tasks", "tasks-calib-diff", "tasks-calib-heldout",
             "tasks-calib-tight", "tasks-domain/finance", "tasks-domain/software")


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def _ref_from_head(tmpdir):
    """Extract the committed graders.py; bytes, not text (source is UTF-8)."""
    blob = subprocess.run(
        ["git", "-C", HERE, "show", "HEAD:amplification/harness/graders.py"],
        capture_output=True).stdout
    if not blob:
        raise SystemExit("could not read HEAD:amplification/harness/graders.py "
                         "(not a git checkout? pass --ref instead)")
    p = os.path.join(tmpdir, "graders_ref.py")
    with open(p, "wb") as fh:
        fh.write(blob)
    return p


def probes(task):
    """Outputs to grade: the task's own answer strings plus boundary variants.

    Covers the two failure directions a grader edit can introduce: a correct
    answer that stops passing, and a wrong answer that starts passing.
    """
    out = []

    def walk(gr):
        if gr.get("type") == "all_of":
            for sub in gr.get("graders", []):
                walk(sub)
        for key in ("expected", "truth"):
            if key in gr:
                v = gr[key]
                out.append(str(v))
                out.append("The answer is %s." % v)
                if isinstance(v, (int, float)):
                    out.append("%s.0" % v)   # value-PRESERVING decimal: must still match
                    out.append("%s.5" % v)   # value-CHANGING decimal: must not match
        for key in ("keywords", "forbidden", "markers"):
            for k in gr.get(key, []) or []:
                out.append(str(k))
                out.append("**%s**" % k)     # asterisk bold
                out.append("__%s__" % k)     # underscore bold
                out.append("Answer: %s" % k)
        if gr.get("type") == "interval_contains":
            t = gr.get("truth", 0)
            out.append("P5: %s P95: %s" % (t * 0.5, t * 1.5))

    walk(task.get("grader", {}))
    out += ["", "0", "100", "100.0", "0.5", "rows=5", "rows=5.0", "rows=5.2",
            "snake_case_name", "cannot be determined"]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default=None,
                    help="reference graders.py (default: the committed HEAD version)")
    args = ap.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        ref_path = args.ref or _ref_from_head(tmp)
        ref = _load(ref_path, "graders_ref")
        cur = _load(os.path.join(HERE, "graders.py"), "graders_cur")

        files = []
        for d in TASK_DIRS:
            files += sorted(glob.glob(os.path.join(HERE, d, "*.json")))

        calls = 0
        diffs = []
        for tf in files:
            task = json.load(io.open(tf, encoding="utf-8"))
            gr = task.get("grader", {})
            for p in probes(task):
                def grade(mod):
                    try:
                        r = mod.grade(gr, p)
                        return (r.get("passed"), r.get("score"))
                    except Exception as e:            # a grader must never crash a run
                        return ("ERR:" + type(e).__name__, None)
                a, b = grade(ref), grade(cur)
                calls += 1
                if a != b:
                    diffs.append((os.path.basename(tf), p[:60], a, b))

        print("reference : %s" % ("HEAD" if args.ref is None else ref_path))
        print("tasks: %d | grade calls compared: %d" % (len(files), calls))
        print("DISAGREEMENTS: %d" % len(diffs))
        for name, probe, a, b in diffs:
            print("  %-42s probe=%-42r ref=%s cur=%s" % (name, probe, a, b))
        if not diffs:
            print("(identical behaviour on every probe)")


if __name__ == "__main__":
    main()
