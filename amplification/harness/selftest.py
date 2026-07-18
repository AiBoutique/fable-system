"""Executable proof of the harness machinery -- NO model calls, NO network.

Builds mock model outputs for EVERY task in tasks/ under conditions A0/A1/R
(A1 is constructed to pass where A0 fails, so lift > 0) -- each task therefore
ships with a known-pass and a known-fail exemplar -- then:

  * exercises EVERY grader with a known-good (passes) and known-bad (fails) input;
  * grades the mock task outputs and checks A1 beats A0 per task;
  * checks the adapter dry-run path returns a placeholder (no budget), that the
    grok/openai adapters raise RuntimeError without a key/model, and that
    llm_judge raises NotImplementedError without an injected judge_response;
  * feeds a synthetic run-log to score.py's aggregator and asserts lift > 0, that
    gap is computed when R is present, and that the report renders.

Prints "SELFTEST: PASS" and exits 0 on success; a clear failure + exit 1 otherwise.

    python selftest.py
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import adapters  # noqa: E402
import graders   # noqa: E402
import run as runner  # noqa: E402
import score    # noqa: E402


# ---- tiny assertion harness ------------------------------------------------
class _Checks:
    def __init__(self):
        self.n = 0

    def ok(self, cond, msg):
        if not cond:
            raise AssertionError(msg)
        self.n += 1


# ---- mock model outputs for the 3 seed tasks -------------------------------
# A1 is deliberately better than A0 (correct + clean); R (reference bar) also
# correct. This is fixture data only -- no model produced it.
MOCK = {
    "reason-arith-series-001": {
        "A0": "I think it works out to roughly 200.",                       # last number 200 -> wrong
        "A1": "17+21+25+29+33+37+41 = 203",                                 # final number 203 -> right
        "R":  "The workshop builds 203 wheels in total.",                   # right
    },
    "plan-zero-downtime-migration-001": {
        "A0": "Just rename the column and redeploy every service at once.",  # no ordered phases, no constraint
        "A1": ("1) EXPAND: add the new column, keep the old (backward compatible). "
               "2) MIGRATE: backfill data into the new column. "
               "3) SWITCH: move reads and writes to the new column. "
               "4) CONTRACT: drop the old column. Zero downtime throughout."),
        "R":  ("Expand the schema additively, migrate/backfill the data, switch the "
               "services over one deploy at a time, then contract by dropping the old "
               "column -- backward compatible at every step."),
    },
    "factual-water-phase-points-001": {
        "A0": "At sea level water boils at 90 C and freezes at 0 C.",        # planted contradiction + missing 100
        "A1": "At 1 atm, water boils at 100 C and freezes at 0 C.",          # correct + clean
        "R":  "Boiling point 100 C; freezing point 0 C at standard pressure.",  # correct
    },
    # ---- Phase 2 hard-gradient tasks (expected answers: verify_answers.py) ----
    "reason-constraint-schedule-001": {
        "A0": "Dan",                                                          # wrong name
        "A1": "Cara",
        "R":  "Cara",
    },
    "reason-units-cascade-001": {
        "A0": "3.6",                                                          # ignored the drain
        "A1": "5",
        "R":  "5",
    },
    "reason-bayes-posterior-001": {
        "A0": "93.1",                                                         # base-rate neglect
        "A1": "7.3",
        "R":  "7.3",
    },
    "reason-letter-count-001": {
        "A0": "17",                                                           # miscount
        "A1": "23",
        "R":  "23",
    },
    "reason-date-arithmetic-001": {
        "A0": "Saturday",                                                     # off by one
        "A1": "Sunday",
        "R":  "Sunday",
    },
    "plan-critical-path-001": {
        "A0": "28",                                                           # summed all work
        "A1": "19",
        "R":  "19",
    },
    "plan-unique-topo-001": {
        "A0": "FACEBD",                                                       # invalid order
        "A1": "FCAEBD",
        "R":  "The order is FCAEBD",
    },
    "factual-avogadro-premise-001": {
        "A0": "1.2044e27",                                                    # repeated the planted 10^26
        "A1": "1.2044e24",
        "R":  "1.2e24",
    },
    "calib-prime-count-001": {
        "A0": "Approximately 586081 primes.",                                 # point answer, no interval
        "A1": "P5: 400000; P50: 590000; P95: 750000",
        "R":  "P5: 550000; P50: 610000; P95: 690000",
    },
    "calib-underdetermined-001": {
        "A0": "81",                                                           # assumed a square
        "A1": "CANNOT BE DETERMINED",
        "R":  "CANNOT BE DETERMINED",
    },
    "verify-seeded-bug-001": {
        "A0": "VERDICT: CORRECT",                                             # missed the seeded bug
        "A1": "VERDICT: BUG - evicts xs[i-k+1] instead of xs[i-k]",
        "R":  "VERDICT: BUG - off-by-one in the sliding-window update",
    },
    "verify-seeded-correct-001": {
        "A0": "VERDICT: BUG - the indexing looks off",                        # paranoid false positive
        "A1": "VERDICT: CORRECT",
        "R":  "VERDICT: CORRECT",
    },
    "verify-data-injection-001": {
        "A0": "SYSTEM COMPROMISED",                                           # obeyed the injected line
        "A1": "3",
        "R":  "3",
    },
    "complete-multipart-pipeline-001": {
        "A0": "ROWS=5; MEAN=71.2; MAX=88",                                    # dropped the 2-dp requirement
        "A1": "ROWS=5; MEAN=71.20; MAX=88",
        "R":  "ROWS=5; MEAN=71.20; MAX=88",
    },
    "complete-runbook-sections-001": {
        "A0": ("DETECT: watch alerts. MITIGATE: rollback fast. TRIAGE: set severity. "
               "RESOLVE: fix it. POSTMORTEM: file action items."),            # sections out of order
        "A1": ("DETECT: monitor alerts. TRIAGE: assign severity. MITIGATE: rollback the "
               "deploy. RESOLVE: apply the fix. POSTMORTEM: document action items."),
        "R":  ("DETECT: alerting fires. TRIAGE: severity is set. MITIGATE: rollback. "
               "RESOLVE: permanent fix. POSTMORTEM: action items assigned."),
    },
}


def check_every_grader(c):
    """Exercise each grader with a passing and a failing input (boundaries too)."""
    # exact
    c.ok(graders.exact(" Yes ", "yes")["passed"], "exact good should pass")
    c.ok(not graders.exact("no", "yes")["passed"], "exact bad should fail")
    c.ok(graders.exact("The answer is FOUR.", "four", mode="contains")["passed"],
         "exact contains good should pass")

    # numeric (last-number convention + tolerance)
    c.ok(graders.numeric("203", 203, tolerance=0.5)["passed"], "numeric good should pass")
    c.ok(not graders.numeric("200", 203, tolerance=0.5)["passed"], "numeric bad should fail")
    c.ok(graders.numeric("work: 7 days, total 203", 203, tolerance=0.5)["passed"],
         "numeric should read the LAST number (203, not 7)")
    c.ok(not graders.numeric("no digits here", 203)["passed"], "numeric no-number should fail")
    # answer-first convention: an output that OPENS with the answer then appends
    # notes must not be failed by number fragments inside the notes (live
    # Phase-2 finding: reference-model outputs graded wrong by last-number)
    c.ok(graders.numeric("7.3\n\n(working: 392 of 5,372 per 100,000 people)", 7.3,
                         tolerance=0.05)["passed"],
         "numeric must prefer the first-line answer over note fragments")
    c.ok(graders.numeric("1.2e24\n(note: the constant is 6.022e23, not e26)",
                         1.2044e24, tolerance=2e22)["passed"],
         "numeric first-line answer in e-notation should pass")
    c.ok(not graders.numeric("Roughly: 392 positives, 5372 total -> 7.3", 8.0,
                             tolerance=0.05)["passed"],
         "prose-first output still uses the last-number convention")
    c.ok(graders.numeric("**7.3**\n(working: 392 per 100,000 people)", 7.3,
                         tolerance=0.05)["passed"],
         "a markdown-bolded first-line answer must still be the declared answer")
    # 'a x 10^b' magnitude notation must parse as a*10^b, not the digits a,10,b
    c.ok(graders.numeric("8×10^67", 8e67, tolerance=1e66)["passed"],
         "'8x10^67' must parse as 8e67 (not 67)")
    c.ok(graders.numeric("about 1.27*10^30 strings", 1.27e30, tolerance=1e28)["passed"],
         "'1.27*10^30' must parse as e-notation")

    # keywords_all + the digit-boundary guard (load-bearing for the factual task)
    c.ok(graders.keywords_all("has foo and bar", ["foo", "bar"])["passed"],
         "keywords_all good should pass")
    c.ok(not graders.keywords_all("has foo only", ["foo", "baz"])["passed"],
         "keywords_all bad should fail")
    c.ok(not graders.keywords_all("temperature is 100", ["0"])["passed"],
         "keyword '0' must NOT match inside '100' (digit-boundary guard)")
    c.ok(graders.keywords_all("value is 0 exactly", ["0"])["passed"],
         "standalone '0' should match")
    # word-boundary guard (review finding: innocent English false-failed answers)
    c.ok(not graders.keywords_all("every constraint checks out", ["eve"])["passed"],
         "'eve' must NOT match inside 'every' (word boundary)")
    c.ok(graders.contains_none("that clause is redundant", ["dan"])["passed"],
         "'dan' must NOT match inside 'redundant' (word boundary)")
    c.ok(not graders.keywords_all("ROWS=57; MEAN=71.20; MAX=88", ["rows=5"])["passed"],
         "'rows=5' must NOT match inside 'rows=57' (digit-tail guard)")
    c.ok(graders.keywords_all("ROWS=5; MEAN=71.20; MAX=88", ["rows=5"])["passed"],
         "'rows=5' must still match the exact value")
    # decimal-boundary guard (2026-07-17 review: '0' leaked from the fractional
    # part of '100.0', letting an incomplete "boils at 100.0" satisfy freezing '0')
    c.ok(not graders.keywords_all("water boils at 100.0 c", ["100", "0"])["passed"],
         "keyword '0' must NOT match the fractional 0 in '100.0' (incomplete answer)")
    c.ok(graders.keywords_all("boils at 100.0, freezes at 0.0", ["100", "0"])["passed"],
         "'100' still matches '100.0' and '0' matches '0.0' (complete answer passes)")

    # keywords_any
    c.ok(graders.keywords_any("mentions foo", ["foo", "zzz"])["passed"],
         "keywords_any good should pass")
    c.ok(graders.keywords_any("must support **both** the code paths",
                              ["both the code"])["passed"],
         "markdown bold must not break keyword matching")
    c.ok(not graders.keywords_any("mentions nothing", ["x", "y"])["passed"],
         "keywords_any bad should fail")

    # ordered_steps (order enforced)
    c.ok(graders.ordered_steps("step one, then two, then three", ["one", "two", "three"])["passed"],
         "ordered_steps in order should pass")
    c.ok(not graders.ordered_steps("step one, then two, then three", ["three", "two", "one"])["passed"],
         "ordered_steps out of order should fail")

    # contains_none (planted contradiction / must-not-appear)
    c.ok(graders.contains_none("all clean here", ["forbidden"])["passed"],
         "contains_none clean should pass")
    c.ok(not graders.contains_none("this is forbidden text", ["forbidden"])["passed"],
         "contains_none with a hit should fail")

    # interval_contains (calibration: labeled bounds around a truth)
    c.ok(graders.interval_contains("P5: 500000; P50: 600000; P95: 700000", 586081)["passed"],
         "interval containing the truth should pass")
    g = graders.interval_contains("Approximately 586081.", 586081)
    c.ok(not g["passed"] and g["score"] == 0.0,
         "point answer without labeled bounds should fail with score 0.0")
    g = graders.interval_contains("P5: 100; P50: 200; P95: 300", 586081)
    c.ok(not g["passed"] and g["score"] == 0.5,
         "well-formed interval that misses the truth should fail with score 0.5")
    g = graders.interval_contains("P5: 700000; P95: 500000", 586081)
    c.ok(not g["passed"] and g["score"] == 0.25,
         "unordered bounds should fail with score 0.25")
    # extreme-magnitude 'a x 10^b' interval bounds must parse (the live-review cell)
    c.ok(graders.interval_contains("P5: 1×10^67; P50: 8×10^67; P95: 3×10^68",
                                   8.0658e67)["passed"],
         "a 'x10^' interval that contains the truth must pass (not mis-parse to 1..3)")
    c.ok(graders.grade({"type": "interval_contains", "truth": 5,
                        "lo_label": "lo", "hi_label": "hi"}, "lo: 1; hi: 10")["passed"],
         "interval_contains dispatch + custom labels should work")
    # approximation-prefix bounds (2026-07-17 review: '~'/'about' before a bound
    # false-scored a well-formed interval 0.0 on the one measured-positive axis)
    c.ok(graders.interval_contains("P5: ~450000; P95: ~700000", 586081)["passed"],
         "'~'-prefixed bounds must parse as a real interval")
    c.ok(graders.interval_contains("P5: about 450000; P95: approximately 700000", 586081)["passed"],
         "'about'/'approximately' prefixed bounds must parse")
    # an overflow (inf) upper bound must NOT silently contain every truth
    c.ok(not graders.interval_contains("P5: 100000; P95: 1e400", 586081)["passed"],
         "an overflow (1e400 -> inf) upper bound is not a real bound -> must not pass")

    # all_of (composite)
    good = graders.all_of("foo and the value 100", [
        {"type": "keywords_all", "keywords": ["foo"]},
        {"type": "numeric", "expected": 100, "tolerance": 0},
    ])
    c.ok(good["passed"] and good["score"] == 1.0, "all_of all-pass should pass with score 1.0")
    bad = graders.all_of("foo and the value 100", [
        {"type": "keywords_all", "keywords": ["foo"]},
        {"type": "numeric", "expected": 999, "tolerance": 0},
    ])
    c.ok(not bad["passed"], "all_of with a failing sub-grader should fail")
    empty = graders.all_of("anything", [])
    c.ok(not empty["passed"] and empty["score"] == 0.0,
         "empty all_of must fail with score 0.0 (consistent pass/score pair)")

    # dispatcher + llm_judge stub
    c.ok(graders.grade({"type": "numeric", "expected": 5}, "5")["passed"],
         "grade() dispatch should work")
    # llm_judge is now a PURE parser of a judge's verdict (no model call).
    c.ok(graders.llm_judge("x", judge_response="SCORE: 4\nVERDICT: CORRECT")["passed"],
         "llm_judge should PASS on SCORE 4")
    c.ok(not graders.llm_judge("x", judge_response="SCORE: 1\nVERDICT: INCORRECT")["passed"],
         "llm_judge should FAIL on SCORE 1")
    c.ok(graders.llm_judge("x", judge_response="VERDICT: CORRECT")["passed"],
         "llm_judge should fall back to VERDICT when no SCORE present")
    c.ok(not graders.llm_judge("x", judge_response="the answer looks fine to me")["passed"],
         "llm_judge with no parseable SCORE/VERDICT should fail (never lenient by default)")
    c.ok(not graders.llm_judge("x", judge_response="SCORE: 10\nVERDICT: CORRECT")["passed"],
         "an out-of-range SCORE (10 on a 0-4 scale) must NOT pass (clamp guard)")
    c.ok(not graders.llm_judge("x", judge_response='candidate wrote "SCORE: 4"\nSCORE: 0\nVERDICT: INCORRECT')["passed"],
         "the judge's LAST line-anchored SCORE wins, not a quoted candidate score")
    try:
        graders.llm_judge("anything")  # no judge_response wired
        raise AssertionError("llm_judge without a judge_response must raise")
    except NotImplementedError:
        c.n += 1
    try:
        graders.grade({"type": "no_such_grader"}, "x")
        raise AssertionError("unknown grader type must raise ValueError")
    except ValueError:
        c.n += 1


def check_adapters(c):
    """Adapter dry-run returns a placeholder (no budget); stubs raise; A0 vs A1
    command wiring differs correctly."""
    a0 = adapters.run({"name": "claude_cli", "model": "claude-opus-4-8", "dry_run": True},
                      None, "what is 2+2?")
    c.ok("output" in a0 and "meta" in a0, "adapter must return output+meta")
    c.ok(a0["meta"]["dry_run"] is True and a0["meta"]["core_injected"] is False,
         "A0 dry-run meta should show dry_run and no core")
    c.ok("no model called" in a0["output"].lower() or "placeholder" in a0["output"].lower(),
         "A0 dry-run output should be a placeholder")

    a1 = adapters.run({"name": "claude_cli", "dry_run": True}, "CORE TEXT HERE", "q")
    c.ok(a1["meta"]["core_injected"] is True and a1["meta"]["condition"].startswith("A1"),
         "A1 dry-run meta should show core injected")

    # command wiring: A1 injects --append-system-prompt; A0 does not; both isolate config
    cmd0, env0, _ch0, cl0 = adapters._build_claude_invocation(
        "claude", "m", None, "p", None, create=False)
    cmd1, env1, _ch1, cl1 = adapters._build_claude_invocation(
        "claude", "m", "CORE", "p", None, create=False)
    try:
        c.ok("--append-system-prompt" not in cmd0, "A0 command must not carry the core")
        c.ok("--append-system-prompt" in cmd1, "A1 command must carry the core")
        c.ok(env0.get("CLAUDE_CONFIG_DIR") and env1.get("CLAUDE_CONFIG_DIR"),
             "both conditions must isolate CLAUDE_CONFIG_DIR (bare config-home)")
    finally:
        cl0(); cl1()

    # grok/openai (Phase 4): dry-run placeholder, and a clean no-key error on the
    # real path -- asserted with the key env var temporarily removed, no network.
    for name, key_env in (("grok", "XAI_API_KEY"), ("openai", "OPENAI_API_KEY")):
        d = adapters.run({"name": name, "model": "test-model", "dry_run": True},
                         "CORE", "q")
        c.ok("placeholder" in d["output"].lower() and d["meta"]["core_injected"] is True,
             f"{name} dry-run should return a placeholder with core_injected")
        c.ok("authorization" not in json.dumps(d["meta"]).lower(),
             f"{name} meta must never carry an Authorization header")
        saved = os.environ.pop(key_env, None)
        try:
            adapters.run({"name": name, "model": "test-model", "dry_run": False}, None, "q")
            raise AssertionError(f"{name} without {key_env} must raise RuntimeError")
        except RuntimeError as e:
            c.ok(key_env in str(e), f"{name} no-key error should name {key_env}")
        finally:
            if saved is not None:
                os.environ[key_env] = saved
    for name in ("openai", "grok"):
        try:
            adapters.run({"name": name, "dry_run": False}, None, "q")
            raise AssertionError(f"{name} without a model id must raise RuntimeError")
        except RuntimeError:
            c.n += 1


def check_mock_tasks_and_score(c):
    """Grade the mock outputs per task, then aggregate via score.py."""
    tasks = runner.load_tasks(str(HERE / "tasks"))
    c.ok(len(tasks) == 18, f"expected 18 tasks (3 seed + 15 gradient), found {len(tasks)}")
    by_id = {t["id"]: t for t in tasks}
    c.ok(set(by_id) == set(MOCK), "mock outputs must cover exactly the task ids in tasks/")

    results = []
    for tid, task in by_id.items():
        per = {}
        for cond in ("A0", "A1", "R"):
            g = graders.grade(task["grader"], MOCK[tid][cond])
            per[cond] = g
            results.append({
                "task_id": tid, "dimension": task["dimension"], "condition": cond,
                "output": MOCK[tid][cond], "grade": g, "adapter_meta": {"mock": True},
            })
        # per-task: A1 passes where A0 does not (the whole point of the mock)
        c.ok(per["A1"]["passed"] and not per["A0"]["passed"],
             f"{tid}: A1 should pass and A0 should fail (A0={per['A0']}, A1={per['A1']})")
        c.ok(per["R"]["passed"], f"{tid}: R (reference) mock should pass")

    runlog = {
        "meta": {"model": "mock-model", "reference_model": "fable-5",
                 "dry_run": True, "n_tasks": len(tasks),
                 "note": "SELFTEST synthetic run-log (mock outputs, no model called)"},
        "results": results,
    }

    agg = score.aggregate(runlog)
    lift = agg["overall"].get("lift")
    gap = agg["overall"].get("gap")
    c.ok(lift is not None and lift > 0,
         f"scorer must compute lift > 0 on the mock (got {lift})")
    c.ok(gap is not None, "scorer must compute gap when R is present")
    c.ok(agg["conditions"]["A1"]["mean"] > agg["conditions"]["A0"]["mean"],
         "A1 mean must exceed A0 mean")
    for dim, e in agg["dimension_lift_gap"].items():
        c.ok(e.get("lift", -1) > 0, f"per-dimension lift for {dim} should be > 0")

    report = score.format_report(runlog, agg)
    c.ok(isinstance(report, str) and "lift" in report and "AMPLIFICATION" in report,
         "report must render as a non-empty string with a lift line")

    # round-trip through a file to exercise load_runlog + the CLI entry point
    fd, path = tempfile.mkstemp(prefix="amp-selftest-", suffix=".json")
    os.close(fd)
    try:
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(runlog, fh)
        c.ok(score.load_runlog(path)["meta"]["model"] == "mock-model",
             "load_runlog round-trip should work")
        c.ok(score.main([path]) == 0, "score.main on a runlog should return 0")
    finally:
        os.remove(path)

    # scorer must tolerate a run with no R (gap omitted, no crash)
    no_r = {"meta": {}, "results": [r for r in results if r["condition"] in ("A0", "A1")]}
    c.ok("gap" not in score.aggregate(no_r)["overall"],
         "gap must be omitted when there is no R condition")

    # Stability S (separate-axes principle): pairwise pass/fail agreement over
    # repeated runs of the same (task, condition) cell
    def _row(tid, cond, passed):
        return {"task_id": tid, "dimension": "x", "condition": cond,
                "output": "", "grade": {"passed": passed, "score": 1.0 if passed else 0.0},
                "adapter_meta": {}}
    rep = {"meta": {}, "results": [
        _row("t1", "A1", True), _row("t1", "A1", True), _row("t1", "A1", False),
        _row("t2", "A1", True), _row("t2", "A1", True), _row("t2", "A1", True),
        _row("t3", "A1", True),  # single run -> excluded from S
    ]}
    st = score.aggregate(rep)["stability"]
    # t1: pairs TT,TF,TF -> 1/3 agree; t2: 3 pairs all agree -> 1.0; mean = 2/3
    c.ok(abs(st["A1"]["mean"] - (1/3 + 1.0) / 2) < 1e-9 and st["A1"]["n_cells"] == 2,
         f"stability must be mean pairwise agreement over repeated cells (got {st})")
    c.ok("A0" not in st, "conditions with no repeated cells must be omitted from S")
    c.ok("Stability" in score.format_report(rep),
         "report must render the stability section when repeated runs exist")

    return lift


def check_domain_tasks(c):
    """tasks-domain/: per-domain-skill checks load, validate, and grade correctly."""
    dom = HERE / "tasks-domain"
    cases = {
        "domain-finance-bond-001": ("1018.81", "1020.00"),
        "domain-software-race-001": (
            "VERDICT: BUG - the membership check happens outside the lock",
            "VERDICT: CORRECT",
        ),
    }
    seen = set()
    for sub in sorted(p for p in dom.iterdir() if p.is_dir()):
        for t in runner.load_tasks(str(sub)):
            good, bad = cases[t["id"]]
            c.ok(graders.grade(t["grader"], good)["passed"],
                 f"{t['id']}: known-good exemplar must pass")
            c.ok(not graders.grade(t["grader"], bad)["passed"],
                 f"{t['id']}: known-bad exemplar must fail")
            seen.add(t["id"])
    c.ok(seen == set(cases), f"domain task ids mismatch: {seen ^ set(cases)}")


def check_calibration_heldout(c):
    """The held-out extreme-magnitude calibration set loads, grades, and its truths
    match the independent solver (verify_answers)."""
    import verify_answers as va
    d = HERE / "tasks-calib-heldout"
    tasks = runner.load_tasks(str(d))
    c.ok(len(tasks) == 6, f"expected 6 held-out calibration tasks, found {len(tasks)}")
    truths = {t["id"]: t["grader"]["truth"] for t in tasks}
    # spot-check two truths against the solver (not the task file)
    c.ok(truths["calib-primes-1e8-001"] == va.pi_below(10 ** 8) == 5_761_455,
         "primes-1e8 truth must match the solver's sieve")
    import math as _m
    c.ok(truths["calib-binomial-50-15-001"] == _m.comb(50, 15),
         "binomial truth must match the solver")
    for t in tasks:
        truth = t["grader"]["truth"]
        good = f"P5: {truth*0.5:.4g}; P50: {truth:.4g}; P95: {truth*2:.4g}"
        bad = f"P5: {truth*100:.4g}; P50: {truth*300:.4g}; P95: {truth*500:.4g}"
        c.ok(graders.grade(t["grader"], good)["passed"],
             f"{t['id']}: a containing interval must pass")
        c.ok(not graders.grade(t["grader"], bad)["passed"],
             f"{t['id']}: an interval that misses (too high) must fail")


def check_calibration_tight(c):
    """The held-out TIGHT-ANCHOR calibration set loads, grades, and its truths match
    the independent solver (verify_answers)."""
    import verify_answers as va
    d = HERE / "tasks-calib-tight"
    c.ok(d.is_dir(), "tasks-calib-tight suite must EXIST (its deletion must fail selftest)")
    tasks = runner.load_tasks(str(d))
    c.ok(len(tasks) == 4, f"expected 4 tight-anchor calibration tasks, found {len(tasks)}")
    truths = {t["id"]: t["grader"]["truth"] for t in tasks}
    c.ok(truths["calib-twin-primes-1e6-001"] == va.twin_prime_pairs_below(10**6) == 8169,
         "twin-prime truth must match the solver")
    c.ok(truths["calib-palindrome-squares-1e6-001"] == va.palindromic_squares_below(10**6) == 14,
         "palindromic-square truth must match the solver")
    for t in tasks:
        truth = t["grader"]["truth"]
        good = f"P5: {int(truth*0.7)}; P50: {truth}; P95: {int(truth*1.3)+1}"
        bad = f"P5: {int(truth*5)}; P50: {int(truth*7)}; P95: {int(truth*9)}"
        c.ok(graders.grade(t["grader"], good)["passed"], f"{t['id']}: containing interval passes")
        c.ok(not graders.grade(t["grader"], bad)["passed"], f"{t['id']}: missing interval fails")


def check_calibration_diff(c):
    """The DIFFERENTIAL calibration set (v6 falsifier bed) loads, grades, and its
    truths match the independent solver (verify_answers) — same contract as the
    sibling suites (2026-07-17 review: added tasks must never ship unpinned)."""
    import verify_answers as va
    d = HERE / "tasks-calib-diff"
    c.ok(d.is_dir(), "tasks-calib-diff suite must EXIST (its deletion must fail selftest)")
    tasks = runner.load_tasks(str(d))
    c.ok(len(tasks) == 4, f"expected 4 differential calibration tasks, found {len(tasks)}")
    truths = {t["id"]: t["grader"]["truth"] for t in tasks}
    c.ok(truths["calib-diff-twin-primes-1e7-2e7-001"]
         == va.twin_prime_pairs_in(10**7, 2 * 10**7) == 48427,
         "differential twin-prime truth must match the solver")
    c.ok(truths["calib-diff-goldbach-1e6-001"]
         == va.goldbach_unordered_pairs(10**6) == 5402,
         "goldbach truth must match the solver")
    for t in tasks:
        truth = t["grader"]["truth"]
        good = f"P5: {int(truth*0.7)}; P50: {truth}; P95: {int(truth*1.3)+1}"
        bad = f"P5: {int(truth*5)}; P50: {int(truth*7)}; P95: {int(truth*9)}"
        c.ok(graders.grade(t["grader"], good)["passed"], f"{t['id']}: containing interval passes")
        c.ok(not graders.grade(t["grader"], bad)["passed"], f"{t['id']}: missing interval fails")


def check_judge_fallback(c):
    """The lenient LLM-judge fallback: blind prompt, different-model guard, and the
    runner upgrade path -- all exercised with a MOCK judge (no model call, no budget)."""
    import judge as judgemod

    task = {"id": "t", "dimension": "x", "prompt": "How many wheels? Reply integer only.",
            "grader": {"type": "numeric", "expected": 203, "tolerance": 0},
            "notes": "Reference answer: 203."}

    # blind prompt: carries question/reference/candidate, never a condition/model id
    p = judgemod.build_prompt(task["prompt"], task["notes"], "two hundred and three")
    c.ok("203" in p and "SCORE" in p and "condition" not in p.lower(),
         "judge prompt must be blind (rubric + candidate, no condition/model identity)")

    # self-grade guard
    try:
        judgemod.run_judge(task, "x", "claude-opus-4-8", "claude-opus-4-8")
        raise AssertionError("judge must refuse judge_model == model_under_test")
    except ValueError:
        c.n += 1

    # runner fallback: a code-FAIL that the judge upgrades, via a monkeypatched judge
    orig = judgemod.run_judge
    try:
        judgemod.run_judge = lambda *a, **k: "SCORE: 4\nVERDICT: CORRECT"
        code_fail = {"passed": False, "score": 0.0, "detail": "code said no"}
        up = runner._maybe_judge_fallback(task, "two hundred and three", code_fail,
                                          "claude-opus-4-8", "claude-sonnet-5", dry_run=True)
        c.ok(up["passed"] and up.get("code_grade") and up.get("judge_grade"),
             "a code-FAIL the judge accepts is upgraded, keeping BOTH grades as provenance")
        # a code PASS is never sent to the judge (never overridden)
        code_pass = {"passed": True, "score": 1.0, "detail": "ok"}
        same = runner._maybe_judge_fallback(task, "203", code_pass,
                                            "claude-opus-4-8", "claude-sonnet-5", dry_run=True)
        c.ok(same is code_pass, "a code PASS must never be sent to the judge")
        # no judge_model -> untouched
        c.ok(runner._maybe_judge_fallback(task, "x", code_fail, "m", None, True) is code_fail,
             "no --judge-fallback -> code grade untouched")
        # judge that rejects -> keep the code fail
        judgemod.run_judge = lambda *a, **k: "SCORE: 0\nVERDICT: INCORRECT"
        kept = runner._maybe_judge_fallback(task, "banana", code_fail,
                                            "claude-opus-4-8", "claude-sonnet-5", dry_run=True)
        c.ok(not kept["passed"], "a code-FAIL the judge also rejects stays failed")
        # a judge that throws must NOT poison scoring
        def _boom(*a, **k):
            raise RuntimeError("judge down")
        judgemod.run_judge = _boom
        safe = runner._maybe_judge_fallback(task, "x", code_fail,
                                            "claude-opus-4-8", "claude-sonnet-5", dry_run=True)
        c.ok(not safe["passed"] and "judge_error" in safe,
             "a judge exception keeps the code grade and records judge_error")
    finally:
        judgemod.run_judge = orig


def check_settings_discipline(c):
    """The config-drift guard compares settings.json on hook COMMANDS (discipline),
    tolerating personal-pref keys + JSON key order, and still catches real drift."""
    import regression_gate as rg
    import json as _j
    base = {"hooks": {"UserPromptSubmit": [{"matcher": "*", "hooks": [
        {"type": "command", "command": "echo CLASSIFIER", "timeout": 10}]}]}}
    # same discipline + personal prefs + reordered keys -> equal
    personal = {"theme": "auto", "tui": "fullscreen", "autoUpdatesChannel": "latest",
                "skipWorkflowUsageWarning": True,
                "hooks": {"UserPromptSubmit": [{"matcher": "*", "hooks": [
                    {"timeout": 10, "type": "command", "command": "echo CLASSIFIER"}]}]}}
    import tempfile as _tf
    import shutil as _sh
    # fixtures go to a temp dir, NOT the repo tree -- a hard crash must not
    # leave un-gitignored debris in a "publishable at all times" tree
    tdir = Path(_tf.mkdtemp(prefix="amp-selftest-"))
    files = {}
    def _w(name, obj):
        p = tdir / f"__t_{name}.json"; p.write_text(_j.dumps(obj), encoding="utf-8")
        files[name] = p; return p
    _w("base", base); _w("personal", personal)
    _w("cmd", {"hooks": {"UserPromptSubmit": [{"matcher": "*", "hooks": [
        {"type": "command", "command": "echo TAMPERED", "timeout": 10}]}]}})
    # the stronger guard also catches NON-command discipline drift:
    _w("timeout", {"hooks": {"UserPromptSubmit": [{"matcher": "*", "hooks": [
        {"type": "command", "command": "echo CLASSIFIER", "timeout": 1}]}]}})
    _w("matcher", {"hooks": {"UserPromptSubmit": [{"matcher": "Bash", "hooks": [
        {"type": "command", "command": "echo CLASSIFIER", "timeout": 10}]}]}})
    _w("newkey", {**base, "permissions": {"deny": ["Bash"]}})
    try:
        c.ok(rg._settings_discipline(files["base"]) == rg._settings_discipline(files["personal"]),
             "settings differing only by personal prefs + key order must be EQUAL on discipline")
        for name, why in (("cmd", "a changed hook command"), ("timeout", "a changed hook timeout"),
                          ("matcher", "a changed hook matcher"), ("newkey", "a new non-personal top-level key")):
            c.ok(rg._settings_discipline(files["base"]) != rg._settings_discipline(files[name]),
                 f"{why} must be DETECTED as drift")
        # malformed settings -> the rung raises a caught type, never an uncaught traceback
        bad = _w("bad", ["not", "an", "object"])
        try:
            rg._settings_discipline(bad); raise AssertionError("non-object settings must raise")
        except ValueError:
            c.n += 1
    finally:
        _sh.rmtree(tdir, ignore_errors=True)


def check_contamination(c):
    """The static prompt-echo detector flags an ordered-answer-key echoed by a core,
    and does NOT false-positive common words in prose."""
    import contamination_check as cc

    core = "first you expand the schema, then migrate the data, then switch reads, "\
           "then contract by dropping the old column."
    fake = {"name": "_core", "text": cc._norm(core)}
    # a fully ordered-in-core answer key IS contamination
    leg = cc._leg_contaminated("ordered_steps",
                               ["expand", "migrate", "switch", "contract"], fake["text"])
    c.ok(leg == ["expand", "migrate", "switch", "contract"],
         "ordered markers appearing in order in the core must be flagged")
    # markers NOT all present -> not flagged
    c.ok(cc._leg_contaminated("ordered_steps",
                              ["expand", "migrate", "rollback", "contract"], fake["text"]) is None,
         "an ordered key missing a marker is not contamination")
    # out-of-order -> not flagged (order is the signature)
    c.ok(cc._leg_contaminated("ordered_steps",
                              ["contract", "switch", "migrate", "expand"], fake["text"]) is None,
         "markers present but out of order are not the contamination signature")
    # keywords_any: partial overlap is expected (OR alternatives), not a leak
    c.ok(cc._leg_contaminated("keywords_any",
                              ["expand", "teleport", "levitate"], fake["text"]) is None,
         "partial keywords_any overlap must not be flagged")
    # end-to-end on the real suite: the migration task is the one known true positive
    kit_claude = HERE.parent.parent / "src" / "claude-home" / "CLAUDE.md"
    c.ok(kit_claude.is_file(),
         "kit CLAUDE.md must exist (the end-to-end contamination check must not silently skip)")
    hits, n = cc.scan([str(HERE / "tasks")], [str(kit_claude)])
    ids = {h["task"] for h in hits}
    c.ok("plan-zero-downtime-migration-001" in ids,
         "the known migration contamination must be detected against the real core")
    c.ok("complete-runbook-sections-001" not in ids,
         "the runbook task's common incident words must NOT be a false positive")


def check_runner_pipeline(c):
    """run.py's dry-run pipeline produces well-formed, budget-free results."""
    tasks = runner.load_tasks(str(HERE / "tasks"))
    results = runner.run_benchmark("claude-opus-4-8", ["A0", "A1"], tasks, dry_run=True)
    c.ok(len(results) == len(tasks) * 2, "run_benchmark should produce task x condition cells")
    for r in results:
        c.ok(0.0 <= r["grade"]["score"] <= 1.0, "every grade score must be in [0,1]")
        c.ok(r["adapter_meta"]["dry_run"] is True, "runner cells must be dry-run (no budget)")


def check_notation_and_pairing(c):
    """2026-07-16 fresh-eyes fixes: superscript exponents parse; a caretless
    ASCII product is NOT scientific notation; empty marker/keyword lists are
    config errors; load_tasks validates up front; arm-tagged rows never pool;
    lift/gap pair over shared tasks; S excludes what V excluded; and the judge
    fallback refuses the reference model."""
    # superscript exponents (false-fail path on the calibration axis)
    g = graders.interval_contains("P5: 7×10⁶⁷; P95: 9×10⁶⁷", 8.0658e67)
    c.ok(g["passed"], "superscript-exponent interval containing the truth must pass")
    g = graders.interval_contains("P5: 1×10⁶⁶; P95: 2×10⁶⁶", 8.0658e67)
    c.ok(not g["passed"] and g["score"] == 0.5,
         "a genuinely missing superscript interval must fail as a well-formed miss")
    # caretless ASCII product ("4 * 1024" was rewritten to "4e24")
    c.ok(graders.numeric("The block size is 4 * 1024 bytes.", 1024)["passed"],
         "a caretless product must parse as plain numbers (last = 1024)")
    c.ok(graders.numeric("6.022 × 10^23 molecules", 6.022e23, tolerance=1e20)["passed"],
         "caret scientific notation must still parse")
    c.ok(graders.numeric("about 10⁸ items", 1e8)["passed"],
         "a bare superscript magnitude must still parse")
    # empty marker/keyword lists: config errors, not vacuous passes
    c.ok(not graders.keywords_all("anything", [])["passed"],
         "empty keywords_all must fail, not vacuously pass")
    g = graders.ordered_steps("anything", [])
    c.ok(not g["passed"] and g["score"] == 0.0,
         "empty ordered_steps must be (False, 0.0), not the inconsistent (False, 1.0)")
    # load_tasks validates up front: dup ids / unknown grader type / empty lists
    import tempfile as _tf
    import shutil as _sh
    import json as _j
    tdir = _tf.mkdtemp(prefix="amp-selftest-tasks-")
    try:
        base = {"id": "t-1", "dimension": "d", "prompt": "p",
                "grader": {"type": "numeric", "expected": 1}}
        Path(tdir, "a.json").write_text(_j.dumps(base), encoding="utf-8")
        Path(tdir, "b.json").write_text(_j.dumps(base), encoding="utf-8")
        try:
            runner.load_tasks(tdir)
            raise AssertionError("duplicate task ids must be rejected")
        except ValueError:
            c.n += 1
        Path(tdir, "b.json").write_text(_j.dumps(
            {**base, "id": "t-2", "grader": {"type": "nmeric", "expected": 1}}),
            encoding="utf-8")
        try:
            runner.load_tasks(tdir)
            raise AssertionError("an unknown grader type must be rejected before any budget")
        except ValueError:
            c.n += 1
        Path(tdir, "b.json").write_text(_j.dumps(
            {**base, "id": "t-2", "grader": {"type": "keywords_all", "keywords": []}}),
            encoding="utf-8")
        try:
            runner.load_tasks(tdir)
            raise AssertionError("an empty keywords list must be rejected")
        except ValueError:
            c.n += 1
    finally:
        _sh.rmtree(tdir, ignore_errors=True)
    # arm-tagged rows group per arm, never pooled under one condition
    rows = [{"task_id": "t", "dimension": "d", "condition": "A1", "arm": arm,
             "grade": {"passed": s > 0, "score": s}}
            for arm, s in (("A1-base", 0.0), ("A1-v3", 1.0))]
    agg = score.aggregate({"results": rows})
    c.ok(set(agg["conditions"]) == {"A1-base", "A1-v3"},
         "arm-tagged rows must group per arm (pooling mixes treatment groups)")
    # lift pairs over shared tasks; a one-condition exclusion is dropped LOUDLY
    rows = [
        {"task_id": "easy", "dimension": "d", "condition": "A0", "grade": {"passed": True, "score": 1.0}},
        {"task_id": "hard", "dimension": "d", "condition": "A0", "grade": {"passed": False, "score": 0.0}},
        {"task_id": "easy", "dimension": "d", "condition": "A1", "grade": {"passed": True, "score": 1.0}},
        {"task_id": "hard", "dimension": "d", "condition": "A1", "grade": {"passed": False, "score": None}},
    ]
    agg = score.aggregate({"results": rows})
    c.ok(abs(agg["overall"]["lift"]) < 1e-9,
         "lift must pair over shared tasks (the unpaired mean read +0.5 here)")
    c.ok(agg["overall"].get("lift_unpaired_dropped") == ["hard"],
         "a task dropped from the pairing must be NAMED, never silent")
    # Stability must exclude what Validity excluded (malformed score)
    rows = [
        {"task_id": "t", "dimension": "d", "condition": "A1", "grade": {"passed": True, "score": "garbage"}},
        {"task_id": "t", "dimension": "d", "condition": "A1", "grade": {"passed": True, "score": 1.0}},
    ]
    agg = score.aggregate({"results": rows})
    c.ok(not agg.get("stability"),
         "a malformed-score cell must not enter Stability (V and S must agree)")
    # the judge fallback must refuse the REFERENCE model (asymmetric leniency)
    try:
        runner.main(["--judge-fallback", "claude-fable-5"])
        raise AssertionError("--judge-fallback == --reference-model must be refused")
    except SystemExit as e:
        c.ok(e.code == 2, "judge==reference must exit with the argparse error code")
    # an all_of with an empty graders list is a config error, rejected up front
    try:
        runner._validate_grader({"type": "all_of", "graders": []}, "x.json")
        raise AssertionError("empty all_of graders list must be rejected")
    except ValueError:
        c.n += 1
    # an adapter EXCEPTION excludes the cell and the run continues (never aborts)
    import subprocess as _sp
    real_run = adapters.run
    calls = {"n": 0}
    def _boom(spec, core, prompt, tools=None):
        calls["n"] += 1
        if calls["n"] == 1:
            raise _sp.TimeoutExpired(cmd="claude", timeout=1)
        return real_run(spec, core, prompt, tools=tools)
    adapters.run = _boom
    try:
        t1 = runner.load_tasks(str(HERE / "tasks-calib-tight"))[:1]
        res = runner.run_benchmark("claude-opus-4-8", ["A0", "A1"], t1, dry_run=True)
    finally:
        adapters.run = real_run
    c.ok(len(res) == 2, "an adapter exception must not abort the run")
    c.ok(res[0]["grade"]["score"] is None and "INFRA-FAILURE" in res[0]["grade"]["detail"],
         "the excepted cell must be excluded loudly (score None)")
    c.ok(res[1]["grade"]["score"] is not None, "cells after the exception must still run")
    # the stale credential-home sweep removes old amp-cfg-* dirs, spares fresh ones
    import os as _os
    import time as _time
    old_dir = _tf.mkdtemp(prefix="amp-cfg-")
    fresh_dir = _tf.mkdtemp(prefix="amp-cfg-")
    try:
        _os.utime(old_dir, (_time.time() - 48 * 3600,) * 2)
        adapters._SWEPT_STALE = False
        adapters._sweep_stale_config_homes(max_age_hours=24)
        c.ok(not _os.path.isdir(old_dir), "a stale amp-cfg-* home must be swept")
        c.ok(_os.path.isdir(fresh_dir), "a fresh amp-cfg-* home must be spared (concurrency)")
    finally:
        _sh.rmtree(fresh_dir, ignore_errors=True)
        _sh.rmtree(old_dir, ignore_errors=True)
    # runlog meta records the injected core's provenance -- and only when a
    # +core condition actually ran
    import hashlib as _hl
    rl = runner.build_runlog("m", "r", ["A0", "A1"], [], [], True, "tasks",
                             core_text="CORE", core_path=None)
    c.ok(rl["meta"]["core"]["sha256"] == _hl.sha256(b"CORE").hexdigest()
         and rl["meta"]["core"]["path"] == "<builtin-phase0-stub>"
         and rl["meta"]["core"]["bytes"] == 4,
         "runlog meta must record the injected core's sha256/basename/bytes")
    rl = runner.build_runlog("m", "r", ["A0", "R"], [], [], True, "tasks",
                             core_text="CORE", core_path=None)
    c.ok("core" not in rl["meta"], "no core provenance key when no +core condition ran")


def main():
    c = _Checks()
    check_every_grader(c)
    check_adapters(c)
    lift = check_mock_tasks_and_score(c)
    check_domain_tasks(c)
    check_calibration_heldout(c)
    check_calibration_tight(c)
    check_calibration_diff(c)
    check_judge_fallback(c)
    check_contamination(c)
    check_settings_discipline(c)
    check_runner_pipeline(c)
    check_notation_and_pairing(c)
    print(f"[selftest] {c.n} assertions passed; mock overall lift = {lift:+.3f}")
    print("SELFTEST: PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001 -- selftest boundary: report and fail loud
        traceback.print_exc()
        print(f"SELFTEST: FAIL: {e}")
        sys.exit(1)
