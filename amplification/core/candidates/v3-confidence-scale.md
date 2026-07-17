# Core tuning candidate v3 — [0,20] confidence scale + meta-d′ reporting

**Status: ADOPTED (2026-07-16, owner-approved) — after a two-stage history.**
Stage 1 (below): REJECTED on the open order-of-magnitude bed, where the baseline
was saturated (nothing to gain). Stage 2 ([[v4-tight-anchor-plan]]): on the
discriminating tight-anchor bed it **eliminated the reproducible calibration miss**
(`calib-primes-8digit` 0.33 → 1.00, N=3, S=1.000, zero regressions) — the program's
first measured positive core delta. Adopted verbatim (the exact tested text) into
all three core carriers: `src/claude-home/CLAUDE.md`, the live `~/.claude/CLAUDE.md`
(lockstep, drift-gate green), and `portable-core.md`; the adopted kit CLAUDE.md is
content-identical (EOL-normalized) to the A/B's winning-arm artifact, verified by
hash. NOTE: `FableSetup.exe` is now stale vs src — next `/refresh-kit` rebuilds it.

*(Stage-1 record below, kept verbatim for the audit trail.)*

**Stage-1 status was: REJECTED by its pre-stated A/B (2026-07-16 live, Opus 4.8, N=3;
re-graded after fresh-eyes review).** Result on the 6 held-out extreme-magnitude
tasks: **v1 (plain core) 1.000 interval hit-rate; v3 (core + [0,20] addendum)
1.000 — a TIE; v3 raises hit-rate on 0/6 tasks.** Not adopted (the pre-stated rule
requires v3 to RAISE hit-rate). Runlog (arm-tagged rows):
`private/amplification-runs/phase3-v3ab-calibration-opus48-2026-07-16.json`.

*(Correction: the first pass reported v3 0.944 with a deck-52 "miss". A fresh-eyes
review found the grader's number parser could not read `1×10^67`-style notation,
mis-scoring one v3 cell whose interval actually contained the truth. The parser was
fixed, all stored outputs re-graded — phase2 unaffected, 0 flips — and v3 is a clean
1.000 tie. The REJECT verdict is unchanged; the corrected error had made v3 look
worse than it was.)*

Two findings, both more useful than the rejection itself:
1. **The addendum is NOT inert (unlike v2):** it measurably widened intervals —
   median P95/P5 width ratio **1.24× (v1) → 1.53× (v3)**. It did exactly what it
   said; there was simply nothing to gain on an already-saturated baseline.
2. **The calibration "headroom" did not reproduce — the key revision.** Bare-core
   Opus 4.8 achieved **100% interval coverage** on all 6 held-out tasks (bare
   Fable-5 also contained every cell it produced). The Phase-2 "8/9 miss" was
   specific to `calib-prime-count-001`'s framing (a *difference* of prime counts
   within a fixed band, which invites a too-tight anchor), NOT a dimension-wide
   gap. Open-ended order-of-magnitude questions get naturally-wide hedged
   intervals that contain. So the earlier "calibration is our one measured
   headroom" claim was **partly a single-task artifact** — which is exactly what a
   held-out A/B exists to catch, and it caught it before any core edit shipped.

**Consequence for next candidates:** a calibration task only discriminates when it
invites an over-tight point anchor (the `calib-prime-count-001` shape). Any future
calibration tuning must A/B on that shape, not on open order-of-magnitude estimation
— on a saturated baseline (v1 already 1.000) the "must-raise" rule can only ever
reject, so the real signal here is "these held-out tasks don't discriminate," and
the next A/B needs a task class where the plain core scores *below* ceiling.

---

**Original candidate rationale (kept for the record):** Supersedes the rejected v2
calibration addendum ([[v2-calibration-addendum]]) with an evidence-backed lever.
Never merged into the live CLAUDE.md or the kit without an owner decision; adopted
only if it passes the validation protocol below by a lift delta. *(It did not.)*

**Motivating evidence (research 2026-07-16, `docs/research-amplification-enhancements-2026-07-16.md`):**
"Rescaling Confidence" (arXiv:2603.09309, rev 2026-06-15) — across 6 LLMs incl.
frontier GPT-5.2 / Gemini 3.1 Pro, >78% of verbalized-confidence responses cluster
on ~3 round numbers, and a **[0,20] confidence scale beats the standard [0,100]** on
metacognitive efficiency (meta-d′), significant on every model tested. The paper
also recommends reporting **meta-d′ alongside ECE** (ECE is unreliable under heavy
round-number discretization) and inspecting the empirical confidence distribution.

Our Phase-2 evidence: Opus 4.8's 90% intervals missed the code-verified truth in
8/9 runs across conditions; the full 43 KB core added **zero** calibration lift
(A0 = A1 = 0.750 on the calibration dimension). The v2 addendum (a widen-your-interval
instruction) was rejected 0/3 vs 1/3. This candidate changes the *elicitation scale*
rather than exhorting wider bounds.

**The addendum (appended verbatim to the core under test):**

---

## Stating calibrated confidence

When asked for a confidence or a probability, do not answer on a 0–100(%) scale —
that scale collapses in practice to a few round numbers and hides real
discrimination. Use an integer **0–20 scale** (0 = certainly wrong, 20 = certainly
right, 10 = even odds) and map it back only if the task demands a percentage.
For an interval, state the point estimate, then set bounds by asking which single
input, if wrong, would move the answer most — the interval must survive that input
being wrong. For a stated 90% interval you should genuinely expect to be inside 9
times in 10; near-frontier models are consistently too narrow, so widen until that
9-in-10 bet feels fair, not merely plausible.

---

**Validation protocol (pre-stated, before any run):**
- Held-out calibration tasks REQUIRED (v2's lesson: single-task validation fits the
  ruler). Build ≥3 extreme-magnitude quantity tasks (enhancement #1 in the research
  memo) plus the existing `calib-prime-count-001`; none seen while writing the addendum.
- Conditions: A1 with unmodified core (v1) vs A1 with core+addendum (v3), Opus 4.8,
  same day, N=3 per task. Also record the reference model (R) as the bar.
- Metrics: interval hit-rate (the `interval_contains` grader) AND the empirical
  distribution of stated confidences (per the paper — hit-rate alone can be confounded
  by round-number clustering). Report meta-d′ if point-confidence probes are added.
- Success = v3 raises hit-rate over v1 on a majority of held-out tasks without
  regressing the non-calibration suite (guard against the Phase-1 overhead effect).
- Declared caps: interval-transfer is unproven (paper measured point-confidence, not
  intervals); N=3; single model.

**Do not run without a budget greenlight** (nested `claude -p`, spends model budget).
