# Calibration next step — v4 plan: discriminating tasks first, then a candidate

**Status: A/B RUN (2026-07-16, Opus 4.8, N=3 per arm, 36 live cells). Results:**

| arm (core) | hit-rate | stability S | `calib-primes-8digit` |
|---|---|---|---|
| A1-base — plain 43 KB CLAUDE.md | 0.833 | 0.833 | **0.33** (missed 2/3; e.g. interval [5.10M, 5.18M] vs truth 5,096,876) |
| A1-widen — + triple-half-width rule | **1.000** | 1.000 | 1.00 |
| A1-v3scale — + [0,20]-scale addendum | **1.000** | 1.000 | 1.00 |

**Stage 1 — the class DISCRIMINATES.** Baseline below ceiling (0.833): the
tight-anchor shape reproduces the Phase-2 calibration failure at N=3 (the "drop
calibration as a target" falsifier did NOT fire — calibration headroom is real,
but only on this shape; open order-of-magnitude estimation stays saturated).

**Stage 2 — both candidates eliminate the measured miss** (0.33 → 1.00 on the one
below-ceiling task, zero regressions anywhere, S = 1.000). Exact widen-rule text
tested: *"For any quantity you can only estimate (no exact computation or opened
source), construct your interval, then TRIPLE its half-width around your median
before answering: estimation intervals stated from knowledge are consistently
several times too narrow, and a 90% interval you would only slightly bet on is
not a 90% interval. Apply this mechanically - do not re-judge whether your
particular estimate deserves an exception."* (The [0,20] text is in
[[v3-confidence-scale]].)

**INTENT-GATE FINDING (surfaced, not reconciled).** The pre-stated adoption rule
("raise hit-rate on a MAJORITY of tasks") returns REJECT for both — because only
1 of 4 tasks had headroom, so better-on-1-of-4 can never be a majority. The
rule's letter is structurally unsatisfiable on a mostly-saturated suite (the
exact pathology the v3 postmortem identified); its evident intent (raise where
headroom exists, regress nowhere) is satisfied perfectly by both candidates.
Per the intent gate this disagreement is the finding: reported under both
readings, never silently reconciled toward either. **Protocol amendment for
FUTURE A/Bs (forward-looking only, adopted after seeing this run's data — which
is why this run's verdict stays a recommendation):** adopt iff the candidate
raises hit-rate on a majority of BELOW-CEILING tasks with zero regressions
elsewhere.

**RESOLUTION: the owner adopted the [0,20]-scale addendum (2026-07-16)** — applied
verbatim to all three core carriers (kit src CLAUDE.md, live CLAUDE.md in lockstep,
portable core), hash-verified content-identical to the tested winning arm; drift
gate green. Original recommendation kept below.

**RECOMMENDATION (as made — owner decision; core edits are never self-applied):** adopt
the **[0,20]-scale addendum (v3)** into the next core revision; runner-up the
mechanical widen rule. Why v3 over widen: independent literature support
(arXiv:2603.09309), and it behaved well on BOTH beds (harmless interval-widening
1.24×→1.53× on the saturated open set; fixes the miss here), while the blunter
widen rule is untested for over-widening side-effects beyond these 4 tasks.
**Falsifier for the pick:** a broader held-out calibration bed where v3scale's
intervals miss but widen's contain. Runlog:
`private/amplification-runs/phase3-v4-tightanchor-opus48-2026-07-16.json`.

---

*Original plan (kept for the record):*

## Why this exists
The v3 [0,20]-scale candidate ([[v3-confidence-scale]]) was rejected because the
held-out extreme-magnitude tasks turned out non-discriminating: bare-core Opus 4.8
already hit 100% interval coverage on open order-of-magnitude questions. The v3 A/B
established the rule: **a calibration task only discriminates when it invites an
over-tight point anchor** (the Phase-2 `calib-prime-count-001` shape — a specific
structured count within a fixed band, where a plausible estimate sits close enough
to tempt a too-narrow interval).

## What was built (this session, verified)
`harness/tasks-calib-tight/` — 4 held-out tight-anchor calibration tasks, every
truth exact-verified in `verify_answers.py` and covered by selftest:
- `calib-primes-8digit-001` — 8-digit prime count = 5,096,876 (PNT anchor low+tight)
- `calib-twin-primes-1e6-001` — twin-prime pairs below 1e6 = 8,169 (no closed form)
- `calib-palindrome-squares-1e6-001` — palindromic squares below 1e6 = 14 (tiny count)
- `calib-primes-band-1e6-2e6-001` — primes in [1e6, 2e6] = 70,435 (fixed band)

## The A/B to run (ready; not yet executed — spends budget)
First establish that this class DISCRIMINATES (the precondition v3's set failed):
```
# baseline: does bare-core Opus actually MISS on these? (if it already passes, they
# don't discriminate either -- same lesson as v3)
python run.py --no-dry-run --model claude-opus-4-8 --conditions A1 \
       --core ../../src/claude-home/CLAUDE.md --tasks tasks-calib-tight   # x3 runs
```
Only if bare-core Opus scores **below** ceiling here is a candidate core edit worth
testing. Then A/B the candidate (v3's [0,20] addendum, or a new one) the same way,
adopt strictly by the pre-stated "must raise hit-rate on a majority of tasks" rule.

## Candidate core edits to try (in order), each A/B'd against a below-ceiling baseline
1. **Mechanical widening** — "for any quantity you can only estimate, multiply your
   interval half-width by 3 before answering." Blunt but directly attacks the
   too-narrow failure; measurable.
2. **The v3 [0,20] addendum** — re-test here (it measurably widened intervals
   1.24×→1.53×; on a below-ceiling set that widening might now convert misses to
   hits, which it couldn't on a saturated baseline).
3. **Worked overconfidence example** — a one-shot showing a tight "90%" interval
   that missed, then the corrected wide one.

## Falsifier for the whole calibration-headroom thesis
If bare-core Opus 4.8 also hits ~100% coverage on these tight-anchor tasks, then the
Phase-2 8/9 miss was specific to that one task's exact framing and there is **no
reproducible calibration headroom on Opus 4.8** — record that and drop calibration
as an amplification target, per the same evidence-over-taste rule that rejected v2/v3.
