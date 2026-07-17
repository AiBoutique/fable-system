# Amplification enhancement research — 2026-07-16

What the latest (2025–2026) primary literature says can measurably improve a portable **discipline-core + eval-benchmark** system (bare vs +core vs reference, deterministic code graders). Produced by a fan-out/verify research pass (25 sources fetched, 124 claims extracted, top 25 adversarially 3-vote verified → 22 confirmed / 3 refuted). Every finding is tagged with where it maps: **[core]** prompt-layer edit · **[harness]** benchmark feature · **[task]** new task class · **[adapter]** platform/model layer.

## Headline: the research validates this session's honest null

The single most important result is convergent, not new: **generic reasoning scaffolds add little-to-negative accuracy on models that already reason by default, and gains concentrate where baseline accuracy is low.** That is exactly what our Phase-2 run measured (bare Opus 4.8 at ceiling; lift ≈ 0; the one dimension with headroom was calibration). Two independent primaries:

- Wharton *Prompting Science Report 2* (arXiv:2506.07142, 2025-06-08): on GPQA Diamond, explicit CoT gave only +0.029/+0.031 on reasoning models and a **significant −0.033 for Gemini 2.5 Flash**; the strict "100% correct across 25 trials" metric *declined* for most non-reasoning models. **[harness]** direct warning: CoT raises answer variability and degrades strict repeated-run pass/fail scoring — the exact shape our deterministic graders use across runs.
- Clinical-tasks study (arXiv:2512.22966, 2025-12-28): MedPrompt-style few-shot "significantly improved the task with lowest baseline accuracy… counterproductive for others"; "highly model- and task-dependent."

**Mapping:** keep the core gated to task classes with real headroom, keep measuring per-task-class, never claim uniform lift. Our README §7 conclusion already says this — the literature confirms it as a frontier-wide pattern, not a quirk of our suite.

## Axis 2 — Calibration: our one measured headroom, confirmed as the highest-yield target

- **[task] Frontier-wide overconfidence is real and worst at extreme magnitudes.** QuantSightBench (arXiv:2604.15859, 2026-04-17): *none* of 11 frontier/open models hit 90% interval coverage (best: Gemini 3.1 Pro 79.1%, Grok 4 76.4%, GPT-5.4 75.3%); "calibration degrades sharply at extreme magnitudes." FermiEval (arXiv:2510.26995, 2025-10-30): nominal 99% intervals cover the truth only ~65% of the time. **Our 8/9 interval miss is a textbook instance.** → Add an **extreme-magnitude quantity-estimation task class** — the most discriminating calibration probe, with published bare-model baselines to score against. (Our `calib-prime-count-001` is one such task; broaden it.)
- **[core] candidate — the [0,20] confidence scale.** "Rescaling Confidence" (arXiv:2603.09309, rev 2026-06-15): across 6 LLMs incl. GPT-5.2 / Gemini 3.1 Pro, >78% of verbalized confidences cluster on ~3 round numbers; a **[0,20] scale beats [0,100]** on metacognitive efficiency (meta-d′), significant on every model. Recommends reporting **meta-d′ alongside ECE** and inspecting the empirical confidence distribution. *Caveat: measured on point-confidence, not intervals — so this is a candidate to A/B, not a proven fix.* → replaces the rejected v2 calibration addendum as the next P3 candidate.
- **[harness] post-hoc conformal calibration.** FermiEval: a conformal adjustment restored **accurate 99% coverage and cut the Winkler score 54%**; the LLM-judge analogue (arXiv:2509.18658, EMNLP 2025) gives coverage-guaranteed score intervals. *Caveat: needs a labeled exchangeable calibration set and gives marginal (not per-instance) coverage — transfer to our code-verified-truth setting is unproven.* → medium-term harness layer, test in-domain first.
- **[adapter] the biggest calibration gains need training, not prompting.** CritiCal (arXiv:2510.24505): critique-calibration fine-tuning beats prompt-only "self-critique," which was *worse than vanilla*. One rule *is* liftable to the core: **answer-specific** confidence critique for multiple-choice, **question-focused** uncertainty critique for open-ended.

## Axis 3 — Test-time compute: gate it, don't bake it in

- **[harness] self-consistency has steep diminishing returns near ceiling.** arXiv:2511.00751 (rev 2026-05-07): Gemini-2.5-Pro on MATH-500 went 98% → 99.6% at **~15× compute** (+1.6pp). → measure per-class single-pass reliability first, enable voting only below a threshold. (Single-author preprint; directionally corroborated. A stronger "near-zero lift" framing was **refuted 1-2** in verification — don't overclaim.)
- **[adapter] Thinking Intervention** (arXiv:2503.24370, Princeton+NVIDIA): editing tokens inside the reasoning trace beats plain prompting (up to +6.7% instruction-following) **but needs write access to the thinking stream — closed frontier APIs don't expose it.** → open-weight / thinking-prefill adapters only; a pure system-prompt core on Anthropic/OpenAI can't do it.
- **[harness] logit-free consistency confidence** (SelfCheckGPT lineage, arXiv:2303.08896): multi-run agreement as a confidence signal, no logits — implementable on any closed API, scored by our own graders. *Caveat: documented "worst for overconfident frontier models," so not a guaranteed calibration fix.*

## Axis 4 — Eval methodology: the two artifacts we hit today have named fixes

These came through the fetch/claim stage as primary-sourced leads (not carried into the final 3-vote synthesis — treat as strong leads, verify before relying):

- **[harness] grader design — keyword matching is measurably lossy.** arXiv:2606.24839: a last-number heuristic parser recovered **26%** of ground-truth matches; a keyword-anchored parser **86%** (+60pp); an **LLM-lenient grader reached 97%** recall vs human labels. → exactly our keyword-vocabulary false-negative failure (which we just fixed with word/digit boundaries). Next step: wire the existing `llm_judge` stub as an **optional lenient fallback** (blind, ordinal, different grader model), used only when a code grader fails — recovers the residual false-negatives without losing determinism as the default.
- **[harness] contamination — prompt-echo is a known family.** ConStat (arXiv:2405.16281) redefines contamination as *performance-based* (inflated, non-generalizing) — detectable from outputs alone, no training-data access, so it works on closed APIs. String-match decontam is bypassed by paraphrase (arXiv:2311.04850). → our migration-task marker-echo contamination (already flagged) is one instance; a performance-delta check between "markers-in-core" vs "markers-absent" task variants would detect it automatically.
- **[harness] benchmark hygiene.** The Agentic Benchmark Checklist (arXiv:2507.02825) found setup/reward flaws distorting measured agent performance by **up to 100% relative**; an automated audit of 168 benchmarks / 34,285 tasks found **25.7%** of tasks had task-invalidating issues. → adopt an ABC-style validity checklist as a `tasks/` authoring gate; our `verify_answers.py` (independent answer re-derivation) is already one column of it.

## Axis 5 — Model/API landscape (verified today, 2026-07-16)

- **No Claude Opus 5.** Anthropic models page (fetched 2026-07-16): current tier = **Fable 5 (`claude-fable-5`, GA 2026-06-09, "most capable widely released") / Opus 4.8 / Sonnet 5 / Haiku 4.5**, plus invitation-only Mythos 5 (`claude-mythos-5`, Project Glasswing). Latest Opus is **4.8**; knowledge cutoff Jan 2026. → **corrects the roadmap's "Opus 5 ~late July 2026"**: the next-gen widely-released model that actually shipped is Fable 5 — and it *is* our reference bar (R = `claude-fable-5`, confirmed correct). `effort` defaults to `high` on Opus 4.8 (all surfaces) and Sonnet 5 (API/Claude Code) — relevant to the effort-dial adapter item.
- **[adapter] cross-vendor flagships** for the portability adapters: GPT-5.x (OpenAI), Gemini 3.x (Google), Grok 4.x (xAI) — confirmed as the flagship tier (benchmark-incidental, ~Apr 2026 snapshot, partly superseded within weeks: GPT-5.4→5.5, Grok 4→4.3). Concrete API-surface deltas were **not** established this pass — an open question for the adapters.

## Implementation status (2026-07-16, same day)

Four items were greenlit and built this session (see CHANGELOG):
- **[task] extreme-magnitude calibration class — DONE.** 6 held-out tasks (`tasks-calib-heldout/`, 1e6–1e67, all exact-code-verified in `verify_answers.py`); the v3 A/B ran on them.
- **[core] [0,20]-scale candidate (v3) — BUILT + A/B RUN → REJECTED.** v1 1.000 vs v3 1.000 interval hit-rate (a tie) on the held-out set; the addendum measurably widened intervals (1.24×→1.53×, so not inert like v2) but bare-core Opus was already at 100% coverage. **Key revision this produced:** the Phase-2 "8/9 miss" was a single-task artifact of `calib-prime-count-001`'s tight-anchor framing, not a dimension-wide calibration gap — the held-out A/B caught it before any core edit shipped. Details in `core/candidates/v3-confidence-scale.md`.
- **[harness] `llm_judge` lenient fallback — DONE.** Pure verdict-parser in `graders.py` + blind different-model judge in `judge.py` + `run.py --judge-fallback` (off by default, code-PASS never overridden).
- **[harness] prompt-echo contamination guard — DONE.** `contamination_check.py` (per-leg, ordered-key-in-order detection) + a `regression_gate.py` rung; auto-detects the migration artifact, no false-positive on the runbook.

## Prioritized enhancement menu (recommendation → your call)

| # | Enhancement | Layer | Effort | Evidence | Recommend |
|---|---|---|---|---|---|
| 1 | Extreme-magnitude calibration task class (broaden `calib-prime-count`) | task | S | high (2 primaries) | **Yes** — our one measured headroom, published baselines |
| 2 | [0,20]-scale + meta-d′ calibration candidate (replaces rejected v2) | core | S | med (1 strong primary; interval-transfer unproven) | **Yes, as a P3 A/B candidate** — cheap, matches our validate-by-delta rule |
| 3 | `llm_judge` lenient-fallback grader (blind/ordinal/different model) | harness | M | med-high (26%→86%→97% recall) | Yes, medium-term — closes residual keyword false-negatives |
| 4 | Performance-delta contamination check (marker-in-core vs absent) | harness | M | med (ConStat primary; lead) | Yes — automates the artifact we hit manually today |
| 5 | ABC-style task-authoring validity checklist | harness | S | high | Yes — cheap hygiene, `verify_answers.py` is column 1 |
| 6 | Post-hoc conformal calibration layer | harness | L | high but transfer unproven | Later — needs a calibration set; test in-domain first |
| 7 | Difficulty-gated self-consistency voting | harness | M | med (diminishing returns near ceiling) | Only for classes below a reliability threshold |
| 8 | Thinking-Intervention adapter | adapter | L | med; **blocked on closed APIs** | Defer to open-weight adapters only |
| 9 | Concrete GPT-5.x / Grok 4.x / Gemini 3.x API-surface sweep | adapter | S | gap — not established | Do before any live cross-model run |

## Caveats (carried from verification)

- **Domain-transfer is the biggest caveat:** calibration evidence is on Fermi-estimation / world-event forecasting / point-confidence QA — *not* our code-verified-truth interval setting. The failure *mode* transfers cleanly; the specific remedies (conformal, [0,20], consistency) are candidates to test, not proven fixes.
- **Four of nine findings rest on single non-peer-reviewed preprints** (self-consistency, [0,20] scale, CritiCal, Thinking Intervention); figures are directionally corroborated but statistically fragile.
- **Refuted in verification (do not rely on):** a stronger "voting gives near-zero lift" framing (1-2); log-prob elicitation + quantile adjustment as extra core fixes (0-3); a blanket "verbalized confidence is systematically overconfident" claim (1-2).
- **Open:** in-domain interval-calibration transfer; conformal without a calibration set; concrete OpenAI/xAI API deltas; Claude Code plugin/Agent SDK specifics (not swept this pass).

### Sources (primary, dated)
arXiv:2506.07142 · 2512.22966 · 2604.15859 · 2510.26995 · 2603.09309 · 2510.24505 · 2509.18658 · 2511.00751 · 2503.24370 · 2303.08896 · 2412.12767 · 2606.24839 · 2405.16281 · 2311.04850 · 2507.02825 · Anthropic models overview (fetched 2026-07-16).
