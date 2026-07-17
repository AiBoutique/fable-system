# v6 — differential calibration bed (the v4 falsifier program)

Status: **RESOLVED NEGATIVE — null recorded** (2026-07-17, same day; auth restored, Arm A run).
Arm A (the adopted core, N=3, 12 cells): **contained all four truths 12/12**, 0 infra exclusions
— the validity gate never opened, Arm B never ran (no budget spent on a non-discriminating bed),
and the whole-thesis falsifier below fired exactly as written: close-but-biased anchors are
already handled by the adopted [0,20] core; **the mechanical widen rule has no remaining
constituency and is retired**. With v3 (extreme magnitudes: saturated), v4 (tight anchors: the
one real gap, closed by the adopted section), and this bed all resolved, the calibration-headroom
program is COMPLETE. Runlogs: `private\amplification-runs\phase7-v6-armA-*.json`.

## Why this exists

v4 ([[v4-tight-anchor-plan]]) left the calibration-headroom thesis with an untested falsifier:
*a bed where the adopted [0,20] addendum misses but the blunt mechanical rule ("multiply your
interval half-width by 3") contains* — if no such bed exists, the [0,20] adoption is complete;
if one does, the widen rule earns a place. This bed is built to discriminate exactly that:
tasks whose natural anchor is close-but-biased (5%–2×), where interval WIDTH — not anchor
quality — decides containment.

## The bed (`harness/tasks-calib-diff/`, truths in `verify_answers.py`, 29→33 facts)

| task | truth | anchor bias shape |
|---|---|---|
| calib-diff-twin-primes-1e7-2e7-001 | 48,427 | HL scaling from the known below-1e6 count; moderate bias |
| calib-diff-prime-triplets-1e6-001 | 1,393 | twin→triplet density scaling, 1.5–3× off |
| calib-diff-goldbach-1e6-001 | 5,402 | naive n/(2 ln²n) ≈ 2,600 — ~2× low without the singular series |
| calib-diff-two-squares-1e6-001 | 215,907 | Landau–Ramanujan leading term ~205k — tight ~5% low anchor |

Every truth re-derived by direct sieve/enumeration in `verify_answers.py` (the command is the
citation); prompts use the standard P5/P50/P95 interval format; grader `interval_contains`.

## Pre-stated protocol (rules fixed before any outcome)

1. **Arm A (current adopted core, carries [0,20])**: A1, N=3, all 4 tasks (12 cells).
   *Bed validity gate*: the bed discriminates only if Arm A MISSES ≥1 task (≥2 of 3 runs on
   that task outside the stated interval). Arm A at ceiling ⇒ record the null (same lesson as
   v3), stop — the falsifier resolves NEGATIVE and the [0,20] adoption stands complete.
2. **Arm B (adopted core + mechanical-widen addendum)** — run ONLY if the validity gate opens:
   append exactly: *"For any quantity you can only estimate, multiply your interval half-width
   by 3 before answering."* Same 12 cells.
3. **Adoption rule**: the widen rule is adopted only if, on the tasks Arm A missed, Arm B
   contains on a majority of BELOW-CEILING tasks (the v4-amended letter), with zero
   regressions on tasks-calib-tight re-run at N=3 (the widen rule must not blow up the win
   already banked). Otherwise: record, keep [0,20] alone.
4. Runlogs to `private\amplification-runs\` with core-sha256 provenance, as always.

## Falsifier for the whole differential thesis

Arm A containing all four truths at N=3 (12/12) — then close-but-biased anchors are already
handled by the adopted core and the mechanical rule has no remaining constituency.
