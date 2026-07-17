"""Aggregate a run-log into per-dimension / per-condition scores + lift/gap.

Importable (``load_runlog`` / ``aggregate`` / ``format_report``) and runnable:

    python score.py <runlog.json>

Metrics (README section 3):
    lift = mean(A1) - mean(A0)     # does the portable core help this model?
    gap  = mean(R)  - mean(A1)     # distance to the reference bar; gap <= 0 means
                                   # matched/exceeded the reference on that class.
Scores are the graders' 0..1 scores; means carry sd and n over the scored cells.
"""

from __future__ import annotations

import json
import math
import sys
from collections import defaultdict

__all__ = ["load_runlog", "aggregate", "format_report", "main"]


def load_runlog(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def _mean(xs):
    return sum(xs) / len(xs) if xs else 0.0


def _sd(xs):
    """Sample standard deviation; 0.0 for n < 2 (no exception on a single cell)."""
    n = len(xs)
    if n < 2:
        return 0.0
    m = _mean(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / (n - 1))


def aggregate(runlog):
    """Return a nested summary dict:

        {
          "conditions": {cond: {mean, sd, n, pass_rate}},
          "dimensions": {dim: {cond: {mean, sd, n}}},
          "overall":    {lift?, gap?},
          "dimension_lift_gap": {dim: {lift?, gap?}},
        }
    """
    results = runlog.get("results", [])
    by_cond = defaultdict(list)
    by_dim_cond = defaultdict(lambda: defaultdict(list))
    pass_by_cond = defaultdict(list)
    tasks_by_cond = defaultdict(lambda: defaultdict(list))
    dim_tasks_by_cond = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    excluded = []

    def _cond_key(r):
        # A/B runlogs tag rows with an "arm" (e.g. A1-base vs A1-v3scale) under
        # one condition; pooling arms silently mixes treatment groups
        # (2026-07-16 review finding), so the arm becomes the grouping key.
        c = r.get("condition", "?")
        arm = r.get("arm")
        if arm and arm != c:
            return arm if arm.startswith(c) else f"{c}:{arm}"
        return c

    for r in results:
        try:
            s = float(r["grade"]["score"])
            passed = bool(r["grade"]["passed"])
        except (KeyError, TypeError, ValueError):
            # infra-failed (score: None) or malformed cells: excluded LOUDLY,
            # never averaged in as zeros (live Phase-2 lesson)
            excluded.append(f"{r.get('task_id', '?')}x{_cond_key(r)}")
            continue
        c = _cond_key(r)
        d = r.get("dimension", "?")
        t = r.get("task_id", "?")
        by_cond[c].append(s)
        by_dim_cond[d][c].append(s)
        pass_by_cond[c].append(1.0 if passed else 0.0)
        tasks_by_cond[c][t].append(s)
        dim_tasks_by_cond[d][c][t].append(s)

    cond_stats = {
        c: {"mean": _mean(v), "sd": _sd(v), "n": len(v), "pass_rate": _mean(pass_by_cond[c])}
        for c, v in by_cond.items()
    }

    # Stability (S) -- adopted from the ActionAudit separate-axes principle
    # (Validity / Stability / Agreement, never one score; via the KnowledgePrime
    # review pack, 2026-07-16): for every (task, condition) cell with REPEATED
    # runs, the mean pairwise agreement of pass/fail across runs. 1.0 = the cell
    # always lands the same way; low S = a flaky cell (like the migration-marker
    # oscillation observed live). Only computable when n_runs >= 2; omitted else.
    runs_by_cell = defaultdict(list)
    for r in results:
        try:
            s_raw = r["grade"]["score"]
            if s_raw is None:
                continue
            float(s_raw)  # a malformed score is excluded from V; S must agree
            passed = bool(r["grade"]["passed"])
        except (KeyError, TypeError, ValueError):
            continue
        runs_by_cell[(r.get("task_id", "?"), _cond_key(r))].append(passed)
    stab_by_cond = defaultdict(list)
    for (tid, c), outcomes in runs_by_cell.items():
        n = len(outcomes)
        if n < 2:
            continue
        pairs = [(i, j) for i in range(n) for j in range(i + 1, n)]
        agree = sum(1 for i, j in pairs if outcomes[i] == outcomes[j]) / len(pairs)
        stab_by_cond[c].append(agree)
    stability = {c: {"mean": _mean(v), "n_cells": len(v)} for c, v in stab_by_cond.items()}
    dim_stats = {
        d: {c: {"mean": _mean(v), "sd": _sd(v), "n": len(v)} for c, v in cm.items()}
        for d, cm in by_dim_cond.items()
    }

    def lift_gap(task_maps):
        """lift/gap over the INTERSECTION of tasks scored in both conditions.

        Under per-condition infra-exclusions, an unpaired difference of means
        silently compares different task subsets (2026-07-16 review finding:
        a cell excluded in ONE condition shifted lift by its full weight).
        Dropped (unpaired) tasks are named so no truncation is silent. On equal
        task sets with equal run counts this reduces to the old mean difference.
        """
        e = {}
        def _paired(base, other):
            a, b = task_maps.get(base), task_maps.get(other)
            if not a or not b:
                return None
            shared = set(a) & set(b)
            if not shared:
                return None
            delta = (_mean([_mean(b[t]) for t in shared])
                     - _mean([_mean(a[t]) for t in shared]))
            return delta, sorted((set(a) | set(b)) - shared)
        got = _paired("A0", "A1")
        if got is not None:
            e["lift"] = got[0]
            if got[1]:
                e["lift_unpaired_dropped"] = got[1]
        got = _paired("A1", "R")
        if got is not None:
            e["gap"] = got[0]
            if got[1]:
                e["gap_unpaired_dropped"] = got[1]
        return e

    overall = lift_gap(tasks_by_cond)
    dim_lift_gap = {d: lift_gap(m) for d, m in dim_tasks_by_cond.items()}

    return {
        "conditions": cond_stats,
        "dimensions": dim_stats,
        "overall": overall,
        "dimension_lift_gap": dim_lift_gap,
        "excluded": excluded,
        "stability": stability,
    }


def format_report(runlog, agg=None):
    """Render a readable text report. Pure (returns a string)."""
    if agg is None:
        agg = aggregate(runlog)
    meta = runlog.get("meta", {})
    L = []
    bar = "=" * 64
    L.append(bar)
    L.append("AMPLIFICATION BENCHMARK REPORT (Phase 0 scaffold)")
    L.append(bar)
    L.append(f"model            : {meta.get('model', '?')}")
    if meta.get("reference_model"):
        L.append(f"reference (R)    : {meta.get('reference_model')}")
    L.append(f"dry_run          : {meta.get('dry_run', '?')}")
    L.append(f"tasks / results  : {meta.get('n_tasks', '?')} / {len(runlog.get('results', []))}")
    if agg.get("excluded"):
        L.append(f"EXCLUDED cells   : {len(agg['excluded'])} not scored "
                 f"(infra-failed/malformed): {', '.join(agg['excluded'])}")
    if meta.get("note"):
        L.append(f"note             : {meta['note']}")
    L.append("")

    L.append("Per condition  (score 0..1; mean +/- sd over scored cells):")
    cw = max(8, max((len(c) for c in agg["conditions"]), default=0) + 2)
    L.append(f"  {'cond':<{cw}}{'n':>4}{'mean':>10}{'sd':>9}{'pass_rate':>11}")
    for c in sorted(agg["conditions"]):
        s = agg["conditions"][c]
        L.append(f"  {c:<{cw}}{s['n']:>4}{s['mean']:>10.3f}{s['sd']:>9.3f}{s['pass_rate']:>11.3f}")
    L.append("")

    dims = sorted(agg["dimensions"])
    conds = sorted({c for d in dims for c in agg["dimensions"][d]})
    colw = max(9, max((len(c) for c in conds), default=0) + 2)
    L.append("Per dimension x condition  (mean score):")
    L.append("  " + f"{'dimension':<24}" + "".join(f"{c:>{colw}}" for c in conds))
    for d in dims:
        row = "  " + f"{d:<24}"
        for c in conds:
            cell = agg["dimensions"][d].get(c)
            row += (f"{cell['mean']:>{colw}.3f}" if cell else f"{'-':>{colw}}")
        L.append(row)
    L.append("")

    if agg.get("stability"):
        L.append("Stability S (pairwise pass/fail agreement across repeated runs; "
                 "1.0 = deterministic outcome):")
        scw = max(8, max((len(c) for c in agg["stability"]), default=0) + 2)
        for c in sorted(agg["stability"]):
            s = agg["stability"][c]
            L.append(f"  {c:<{scw}}S={s['mean']:.3f} over {s['n_cells']} repeated cell(s)")
        L.append("")

    ov = agg["overall"]
    L.append("Amplification metrics (contract sec.3):")
    if "lift" in ov:
        tag = "harness helps" if ov["lift"] > 0 else "no help / regression"
        L.append(f"  lift = mean(A1) - mean(A0) = {ov['lift']:+.3f}   ({tag})")
    else:
        L.append("  lift = n/a (needs plain A0 and A1 groups; arm-tagged groups report separately)")
    if "gap" in ov:
        tag = "matched/exceeded R" if ov["gap"] <= 0 else "below R"
        L.append(f"  gap  = mean(R)  - mean(A1) = {ov['gap']:+.3f}   ({tag})")
    else:
        L.append("  gap  = n/a (needs plain A1 and R groups; arm-tagged groups report separately)")
    for key, lbl in (("lift_unpaired_dropped", "lift"), ("gap_unpaired_dropped", "gap")):
        if ov.get(key):
            L.append(f"  WARNING: {lbl} paired over shared tasks only; dropped "
                     f"(scored in one condition): {', '.join(ov[key])}")

    if agg["dimension_lift_gap"]:
        L.append("")
        L.append("  per-dimension lift / gap:")
        for d in sorted(agg["dimension_lift_gap"]):
            e = agg["dimension_lift_gap"][d]
            parts = []
            if "lift" in e:
                parts.append(f"lift {e['lift']:+.3f}")
            if "gap" in e:
                parts.append(f"gap {e['gap']:+.3f}")
            L.append(f"    {d:<24}{('  '.join(parts)) if parts else '(n/a)'}")
    L.append(bar)
    return "\n".join(L)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        print("usage: python score.py <runlog.json>", file=sys.stderr)
        return 2
    runlog = load_runlog(argv[0])
    print(format_report(runlog))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
