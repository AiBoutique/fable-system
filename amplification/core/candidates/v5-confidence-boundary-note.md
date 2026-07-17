# v5 candidate — confidence-vs-probability boundary note (core Calibration bullet)

Status: **BUILT, measurement BLOCKED** (2026-07-17: `claude auth status` → `loggedIn:false`; the
A/B needs isolated `claude -p` arms — in-session agents inherit the live system and cannot serve
as clean arms). Unblock = `claude auth login`, then run the protocol below.

## What it is

r27 disambiguated CLAUDE.md's Calibrate bullet: event-probabilities and stated confidence are
different instruments (probability/range for forecasts; the 0–20 scale for claim confidence).
The portable core carries the measured [0,20] section and a Calibration bullet, but NOT this
boundary — a core-driven model asked "how confident are you?" has no instruction to keep the
two instruments apart. This candidate syncs the note, platform-neutral.

## Exact proposed edit (core `## Calibration` bullet, portable-core.md:38)

Append to the existing bullet:

> That is event-probability; how confident you are in a claim or answer is stated on the
> 0–20 scale ("Stating calibrated confidence" below), not a percent — the two are different
> instruments, not a contradiction.

Nothing else changes; the A/B-adopted [0,20] section itself stays byte-identical.

## Pre-stated protocol (before any outcome is seen)

1. **Non-regression, tight-anchor bed** (the bed that produced the +16.7pp win): A1 with the
   edited core, `tasks-calib-tight`, N=3. Adopt only if hit-rate ≥ the stored winning-arm 1.000
   − one cell's noise (i.e., no new miss attributable to the edit across 12 cells) and
   Stability S = 1.000.
2. **Gradient spot**: A1 on the 18-task gradient, N=1, vs the stored adopted-core run
   (`private\amplification-runs\phase6-gradient-regression-adopted-2026-07-17.json`): zero
   regressions (identical-or-better per cell, contamination cell excluded as always).
3. Wording is the treatment; any regression = reject, record the null here, core untouched.

## Falsifier for adoption

A single tight-anchor cell that the current core passes and the edited core fails, reproduced
once (2 of 2 runs), kills the candidate regardless of aggregate scores.
