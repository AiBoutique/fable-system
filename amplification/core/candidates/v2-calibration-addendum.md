# Core tuning candidate v2 — calibration addendum

**Status: REJECTED by its own validation protocol (2026-07-16 live A/B, N=3+3).**
Result: v1 (unmodified core) intervals contained the truth 1/3 runs; v2
(+addendum) 0/3 — v2's bounds were essentially identical to v1's
(~[535–541k, 544–550k] vs truth 586,081), i.e. the addendum changed interval
behavior not at all. Mechanism (inferred): the model anchors on its prime-number
-theorem point estimate and does not self-classify it as "approximation-formula
knowledge", so the widen-trigger never fires; one appended paragraph also
competes against a 43 KB core. Kept as a recorded null result — the "validate
every core change by lift delta, not taste" rule is the deliverable here, and it
worked: a plausible-sounding discipline edit measurably did nothing. Next
candidates should try (a) mechanical widening ("multiply your interval width by
3 before answering"), or (b) a worked overconfidence example, and must use a
held-out calibration task.

**Motivating evidence (Phase 2 live run, 2026-07-16):** on
`calib-prime-count-001`, bare Opus 4.8 (A0) and Opus + full core (A1) both
produced 90% intervals that MISSED the code-verified truth (586,081) —
A0: [538,000, 545,000]; A1: [541,000, 543,200] (~0.4% wide). The reference model
(bare Fable 5) produced an interval that contained it. Per-dimension lift on
calibration was exactly 0.000: the current core's one-line "Calibrate" rule does
not change interval behavior. Overconfident-interval failure is the classic
calibration result (base rate: untrained forecasters' "90%" intervals contain
the truth roughly 30–50% of the time), so a targeted, generic counter-rule is
the cheapest plausible lift.

**The addendum (appended verbatim to the core under test):**

---

## Calibration of stated intervals

When asked for a confidence interval on a quantity you can neither compute
exactly nor cite from a source you have opened: form the point estimate, then
name (to yourself) the weakest input in the estimate — the interval must be wide
enough to survive that input being wrong. For a 90% interval, you should be
willing to bet 9:1 that the truth falls inside; almost everyone who states an
interval from memory makes it several times too narrow, so after setting bounds,
WIDEN them until the upper bound is at least 1.5x the lower bound for any
quantity known only through approximation formulas or analogy. An overconfident
tight interval is a failing check; an interval that is merely wide is not.

---

**Validation protocol:** N=3 runs of `calib-prime-count-001` under A1 with the
unmodified core (v1) vs the core + addendum (v2), same model, same day. Success
= v2's intervals contain the truth in at least 2/3 runs while v1's contain it in
fewer. Declared caps: single-task validation (a held-out calibration task is
future work — tuning validated on one task risks fitting the ruler), N=3.

**Provenance gap (2026-07-16 fable review):** the raw runlog for this A/B was
never saved to `private\amplification-runs\` — the v1 1/3 vs v2 0/3 result is
therefore unauditable after the fact. The rejection itself stands (it is
against-interest, and the motivating-evidence intervals quoted above match the
phase-2 runlog exactly), but the A/B numbers cannot be re-derived. Standing
policy since: every live runlog is saved before any verdict is drawn, and
runlog meta records the injected core's sha256 (README §3).
