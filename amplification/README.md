# Amplification Foundation

The fable system's purpose, stated as a testable contract: **make whatever model runs it reason, plan, and self-check like a higher tier — measurably — and stay portable across models.** Target bar: match or exceed the strongest reference model (Fable 5 / Mythos) on the task classes that matter. Near-term host: Opus 4.8, then Opus 5. Future hosts: Grok / ChatGPT via adapters.

This directory is **Phase 0** — the measurement foundation. You cannot improve, credibly claim, or port an amplification you cannot measure, so the first building block is the ruler and the architecture it measures across. Everything else builds on this.

## 1. What "amplified intelligence" means here (operational)
Not a vibe — a set of measurable dimensions, each with a scoring approach:

| Dimension | What it captures | How it's scored |
|---|---|---|
| **Reasoning** | correct multi-step deduction/analysis | code-checkable answer (exact/numeric/structured) or blind rubric |
| **Long-horizon planning** | decomposition, ordering, dependency & constraint handling over many steps | rubric against a reference plan + constraint-satisfaction checks |
| **Accuracy / factual credibility** | grounded, correct claims; citations that resolve | fact-checks, source-resolution, contradiction detection |
| **Calibration** | uncertainty expressed as ranges/probabilities; no overconfident errors | scored on calibration of stated confidence vs outcome |
| **Verification discipline** | catches its own errors, labels evidence, refuses to fake a pass | seeded-error tasks: does it find the planted flaw? |
| **Task completion** | actually finishes the multi-step job end-to-end | outcome graders on a final artifact |

"Match/exceed Fable 5" is always **per-dimension, per-task-class, measured** — never a blanket claim. Honest boundary: scaffolding closes (and can exceed) a model-tier gap on decomposable / verifiable / tool-groundable work; single-shot reasoning on a hard novel problem stays bounded by the base model.

## 2. Architecture: portable core ⟷ platform adapter
The one structural rule that keeps this model-agnostic:

- **Portable amplification core** — the discipline (CLAUDE.md + fable-mode patterns) and the domain skills, expressed as **model-agnostic prompt content**. This is *what actually makes a model smarter*: decomposition into checkable sub-claims, rival hypotheses + discriminating probes, adversarial/independent verification, explicit planning + a persisted ledger, evidence labelling + calibration, retrieval-grounding. It must run on any model that accepts a system prompt + tools.
- **Platform adapter** — the host-specific enforcement layer: Claude Code hooks, plugin packaging, the `effort` dial, subagent frontmatter (`isolation: worktree`, per-agent `model`/`effort`/`skills`), `fallbackModel`. Later: Grok / OpenAI equivalents.

**Boundary rule (non-negotiable):** amplification logic never lives in the adapter. If a reasoning/verification/planning rule can only be expressed as a Claude Code hook, it is mis-placed — it belongs in the portable core as prompt content, with the adapter merely *enforcing* it. This is what makes Opus 5 a drop-in and Grok/GPT an adapter-swap rather than a rewrite.

## 3. The measurement contract
**Run conditions** (per task, per model):
- **A0 — bare model:** the host model with *no* fable core (clean config-home; see §4). The floor.
- **A1 — model + core:** the same model with the portable core injected. The product.
- **R — reference bar:** the strongest reference model (Fable 5) bare — the tier to match; optionally Fable 5 + core as the ceiling.

**Metrics:** `lift = score(A1) − score(A0)` (does the harness help this model?) · `gap = score(R) − score(A1)` (distance to the bar; `gap ≤ 0` = matched/exceeded Fable 5 on that task class). Report per dimension and per task-class, mean ± sd over N runs.

**Grading** (Anthropic eval guidance, verified 2026-07-15 at anthropic.com/engineering/demystifying-evals-for-ai-agents):
- Prefer **code-based deterministic graders** (fast, objective, reproducible, cheat-resistant). Use an **LLM judge only where needed**, with a *different* grader model, blind ordering, ordinal scores.
- **Grade the outcome, not the path.** Build **balanced** sets (tasks where a behavior should *and* should-not fire — e.g. does the harness correctly *decline* to over-engineer a trivial task?).
- Seeded-error tasks (a planted flaw) directly measure verification discipline.

**Reproducibility:** pin model version/ID + date; fix task inputs; N≥3 runs for variance; record everything to a run log. Model-graded scores are non-deterministic — pin the grader and act on sustained deltas, not single runs.

**Run-log provenance & exclusion policy** (added 2026-07-16, from the fable review): the runlog meta records the injected core's basename + sha256 + byte size (`run.py` writes it automatically — without this, A1 full-core and A1′ portable-core logs are indistinguishable except by external bookkeeping); every live runlog is saved to the container's `private\amplification-runs\` **before** any verdict is drawn (the v2 A/B's log was never saved — its numbers are permanently unauditable; recorded lesson); infra-failures follow ONE uniform policy across all conditions — loud exclusion (`score: None`, named in the report); the code never auto-retries, so any re-run of an excluded cell is manual, applied identically to every condition, and declared in the runlog note — never retries for treatment cells while reference cells get exclusions (asymmetry is bias-shaped even when harmless); and `lift`/`gap` are computed over the **intersection** of tasks scored in both conditions, with dropped tasks named in the report (an unpaired mean silently compares different task subsets under per-condition exclusions).

**Separate axes, never one score** (adopted 2026-07-16, after an ActionAudit-style eval-design review): report **V** (validity/pass-rate), **S** (stability — pairwise pass/fail agreement across repeated runs of the same cell; `score.py` computes it whenever a runlog carries repeats), and **A** (agreement with the reference bar = our `gap`) as distinct numbers — and **never optimize A alone**: a condition can agree with the reference while being invalid or unstable. Companion task-design principles: prefer **ecological sabotage** errors (mutate a year/scale/neighbor plausibly — our Avogadro 10²⁶ task is the scale form) over strawman hallucinations; and the frozen known-pass/known-fail exemplars in `selftest.py` are the deterministic replay layer — every gate must replay without a live model.

## 4. The model-adapter interface (the portability boundary)
The *only* model-specific surface. Contract:

```
adapter.run(system_core: str | None, task_prompt: str, tools: list | None) -> {output, meta}
```

- **`claude_cli` adapter (now):** invokes `claude -p` headless. **A0/bare** = a disposable, empty config-home (`CLAUDE_CONFIG_DIR` → temp dir with no CLAUDE.md/skills), mirroring the kit's `run-selftest.ps1` sandbox pattern so the baseline is genuinely core-free. **A1/+core** = a config-home (or `--append-system-prompt`) carrying only the portable core. Uses the CLI's existing auth — **no API key is handled.**
- **`grok` / `openai` adapters (Phase 4, implemented):** same signature over their OpenAI-compatible chat-completions APIs (endpoint shapes verified against provider docs 2026-07-16; base URLs overridable via spec or `<NAME>_BASE_URL` env var); `system_core` → the system message; key read from `XAI_API_KEY` / `OPENAI_API_KEY` at call time, never logged or passed on argv. Dry-run verified by selftest; **live behavior UNVERIFIED — no keys on this machine** (declared gap; first live cross-model run is a user-supplied-key step).

Because tasks, graders, and scoring sit *above* this interface, porting to a new model is: write one adapter, re-run the same benchmark. That is the whole portability story.

## 5. Phased program — foundation, then every level & blind corner
- **Phase 0 (this):** contract + architecture + runnable scaffold (`harness/`) + seed tasks + a mock-data self-test proving the machinery. No model budget spent.
- **Phase 1 — measure the lift:** run the seed benchmark on Opus 4.8 (A0 vs A1) and set the Fable-5 reference bar (R). First real lift/gap numbers. *(spends model budget — user-greenlit.)*
- **Phase 2 — cover all levels (DONE 2026-07-16):** 18-task suite across every §1 dimension + per-domain-skill checks; live A0/A1/R run. Results in §7.
- **Phase 3 — raise the ceiling (process live; first candidate rejected):** tune the portable core against the evals — every change validated by a lift delta, not taste. First candidate (calibration addendum) failed its pre-stated A/B protocol and was rejected — see `core/candidates/v2-calibration-addendum.md` for the recorded null.
- **Phase 4 — portability (DONE except live cross-model):** portable core extracted to `core/portable-core.md` (11.9 KB at extraction; 12.8 KB today after the adopted v5 boundary note; zero platform-specific tokens); Grok/OpenAI adapters implemented (dry-run verified; live runs await user-supplied keys); portable core re-measured on Claude — §7.
- **Phase 5 — continuous (built + REGISTERED):** `harness/regression_gate.py` (6 zero-budget rungs: selftest, answer provenance, config-drift guard, shared-non-negotiable lint, dated currency baseline, prompt-echo contamination guard; optional explicitly-flagged live canary) + the standing-run instruction file `../regression-gate.md`, registered as the biweekly local scheduled task `fable-amplification-gate` (diagnose-only). Its config-drift rung first flagged a `settings.json` divergence, which on inspection was entirely personal UI-pref keys + JSON key order (hook commands byte-identical) — so the guard was corrected to compare settings on discipline content minus personal overlays, and now passes against the live home.
- **Blind-corner checklist** (each becomes a tracked item): always-on pointer to the domain layer (audit axis5#5), shared-non-negotiable equality lint (axis5#4), config-drift guard, the dated currency baseline, kit-doc coherence, and the expertise-system kit-membership decision (dossier P0.1).

## 6. Status & how to run
Phase 0 scaffold lives in `harness/`. The machinery (schema → grader → scorer → report) is verified on mock model outputs with **no model calls or budget spent**:
```
python harness/selftest.py     # runs graders + scorer on fixture outputs; asserts the pipeline
```
A real measurement run (Phase 1) is a separate, budget-spending step, invoked explicitly:
```
python harness/run.py --model claude-opus-4-8 --conditions A0,A1 --tasks harness/tasks
```
Provenance: research trail in the advancement dossier (`../docs/advancement-dossier-2026-07.md`) and its sources.

### Phase 1 — first live run (2026-07-15)
Executed on **Opus 4.8**, seed set, core = `../src/claude-home/CLAUDE.md` (43 KB, injected by file), bare baseline = an isolated config-home with only the OAuth credentials copied in (so A0 authenticates yet loads no CLAUDE.md/skills/hooks). Result: **A0 (bare) mean 1.00, A1 (+core) mean 0.958 → lift −0.04**; the core slightly *perturbed* the easy planning task (1.00 → 0.875).
- **What it proves:** the live pipeline works end-to-end (auth, isolated bare baseline, file-injected core, deterministic grading, scoring).
- **What it means (honest):** the seed tasks are at bare-Opus ceiling (all 1.0) — no headroom to show amplification — and a large discipline prompt carries process overhead that can nudge a *trivial* task off the grader's exact expectation. This is live evidence for fable-mode's own "scale ceremony to stakes" rule, not a failure of the harness.
- **Next (P2):** measuring real lift requires a **difficulty gradient** — tasks hard enough that bare Opus fails (multi-step reasoning with error traps, constraint-heavy planning, factual prompts with planted contradictions the model must catch, verification tasks with seeded bugs). Expected shape: neutral/overhead on easy tasks, positive lift on hard ones. Add the Fable-5 reference condition (R) once the hard suite exists.

## 7. Phase 2–5 results (2026-07-16, live; run-logs in the container's `private\amplification-runs\`)

**Suite:** 18 tasks (3 seed + 15 gradient) over all six §1 dimensions + 2 domain tasks (`tasks-domain/`), plus three held-out calibration sets — 6 extreme-magnitude (`tasks-calib-heldout/`), 4 tight-anchor (`tasks-calib-tight/`), and 4 differential (`tasks-calib-diff/`, the v6 falsifier bed, added 2026-07-17). Every code-checkable truth is re-derived by an independent solver (`harness/verify_answers.py`, **33 facts, 0 failures**). Harness selftest: **280 assertions** (every task ships a known-pass and known-fail exemplar). New graders: `interval_contains` (calibration) and `llm_judge` (lenient fallback).

**Headline (Opus 4.8, core = the 43 KB discipline file, N=1 per cell — declared cap):**

| condition | mean | pass rate |
|---|---|---|
| A0 bare | 0.965 | 16/18 |
| A1 + full core | 0.972 | 17/18 |
| A1′ + portable core (11.9 KB) | 0.965 | 16/18 |
| R bare `claude-fable-5` | 0.944 | 17/18 |

`lift = +0.007`; `gap = −0.028` (A1 matched/exceeded the reference bar on this suite). **Read the lift as 0.000**: the independent eval-validity review traced the entire +0.007 to a single contaminated cell — the migration task's ordered markers ("expand → migrate → switch → contract") appear verbatim in the injected 43 KB core, so A1 was partly graded on echoing its own system prompt while A0's semantically complete plan lost 0.125 for phrasing the switch phase as "migrate reads" (0.125/18 = the whole headline lift). The task now carries a contamination warning and is excluded from lift claims under that core. The portable core preserves the full core's benchmark behavior at ~28% of its size.

**What actually discriminates:** bare Opus 4.8 passed nearly the whole gradient — constraint puzzles, unit cascades, Bayes, date arithmetic, letter counting, planted premises, seeded bugs, injection resistance, format pipelines are all at ceiling headless. Two real signals: (1) **calibration** — A0 = A1 = 0.750 vs R = 1.000: Opus states ~1%-wide "90%" intervals that miss the code-verified truth (586,081 seven-digit primes); the discipline core adds zero calibration lift, and the first tuning candidate targeting this failed its own A/B protocol (v1 1/3 vs v2 0/3 contained — recorded null, not adopted). (2) The reference model's only real failure was **letter counting** (tokenizer-level, tools-off). A grader-validity pass (answer-first numeric extraction, markdown-emphasis normalization, widened constraint keywords) fixed three false failures — all on the R condition, i.e. the fixes *lowered* the measured advantage of our own product's condition; stored outputs were re-graded, never re-run.

**Domain checks:** finance bond-pricing and concurrency-bug tasks pass 4/4 cells (A0 and A1 alike) — skill-as-core machinery verified end-to-end; no headroom on these two tasks.

**Calibration follow-up (2026-07-16, held-out A/B — revises the headroom claim).** A 6-task **held-out extreme-magnitude** calibration class (`tasks-calib-heldout/`, 1e6–1e67, all exact-code-verified) was built to test the one dimension that had shown headroom, and the evidence-backed [0,20]-confidence-scale core edit (`core/candidates/v3-confidence-scale.md`) was A/B-tested against it (Opus 4.8, N=3, + bare Fable-5 bar). **Result: bare-core Opus achieved 100% interval coverage on all 6 held-out tasks; the [0,20] addendum measurably widened intervals (median 1.24×→1.53×) but gained nothing (v3 also 1.000, a tie), so it was REJECTED by its pre-stated "must raise hit-rate" protocol.** The Phase-2 "8/9 miss" turned out specific to `calib-prime-count-001`'s framing (a difference-of-prime-counts within a fixed band, which invites a too-tight anchor) — **not a dimension-wide gap.** So the "calibration is our one measured headroom" claim was partly a single-task artifact, and the held-out A/B caught it before any core edit shipped.

**v4 tight-anchor A/B (2026-07-16, same day — the resolution).** A 4-task held-out **tight-anchor** class (`tasks-calib-tight/`) was built on exactly the discriminating shape and A/B'd (Opus 4.8, N=3/arm, + the new **Stability S** axis). Result: the shape **discriminates** — plain-core baseline 0.833, with `calib-primes-8digit` missing 2/3 runs — and **both candidate core edits eliminate the miss completely** (widen rule and [0,20]-scale addendum: 1.000 hit-rate, S=1.000, zero regressions). So the final calibration picture: headroom is real but shape-specific (tight-anchor counts, not open magnitudes), and it is **fixable by a one-paragraph prompt edit** — the first measured positive core delta in the program. Adoption of the [0,20] addendum (recommended; widen as runner-up) is an owner decision — see `core/candidates/v4-tight-anchor-plan.md`, including an intent-gate finding on the adoption rule itself. (Bare Fable-5 contained every held-out cell it produced; 3 of its 6 cells hit transient CLI failures and were correctly excluded from scoring — live proof of the infra-exclusion guard. A fresh-eyes review then caught that the interval grader could not parse `1×10^67`-style bounds; the parser was fixed and all stored outputs re-graded — phase2 unaffected, the one affected v3 cell corrected from a false miss to a contain, verdict unchanged.)

**Gradient non-regression re-run under the adopted core — DONE 2026-07-17 (0 regressions).** The one open gap the eval-validity review named: the adopted 43 KB+addendum core had never been run on the 18-task gradient, so "zero regressions" was proven only inside the 4-task tight-anchor bed. The clean A/B ran live on Opus 4.8 (base core vs adopted core, both fresh this session, 18 tasks × condition A1 = 36 cells; the two cores differ by exactly the 13-line addendum, verified by diff; N=1/arm declared). Runlogs: `private\amplification-runs\phase6-gradient-regression-{base,adopted}-2026-07-17.json`. **Result: 0 regressions, 0 infra-exclusions.** 16 of 18 cells identical across arms (14 at the 1.000 ceiling; `calib-prime-count` 0.5=0.5 — both miss the open-magnitude interval, the known class the addendum does not target; `calib-underdetermined` 1.0=1.0). Two cells rose at N=1 and are **NOT claimed as addendum benefits**: `plan-zero-downtime-migration` 0.875→1.0 is the known contamination cell (marker-phrasing variance), and `verify-data-injection` 0.0→1.0 is a base-arm miscount ("6" vs the correct "3") on an injection-counting task the calibration addendum has no mechanism to affect — i.e. run-to-run noise. So the broad-suite non-regression the v3 protocol required is now **confirmed at N=1**, no longer bed-proven only. (An earlier same-day attempt returned all-36 infra-excluded when the CLI OAuth session expired mid-program — a second live proof of the infra-exclusion guard; re-run after `claude auth login` produced the result above.)

**Honest conclusion:** on single-shot, tools-off text tasks of this class, bare Opus 4.8 is at ceiling and prompt-layer discipline neither helps nor hurts (measured lift = 0.000 once the contaminated cell is excluded); the measured amplification claim this suite CAN support is "A1 ≥ R on 5 of 6 dimensions, N=1". Both fresh-eyes reviews ran (correctness lens: PASS with 16 findings, the misgrade paths fixed and re-verified; eval-validity lens: SOUND on the post-hoc-fitting charge — the grader fixes flipped only reference-condition cells, i.e. they cut against our own product's headline). The next difficulty axes that could show real lift: tool-dependent tasks (the discipline's arithmetic-through-code rule is unexercisable headless), multi-turn long-horizon jobs, and adversarial verification suites. Calibration resolved (see the follow-ups above): headroom is real on the **tight-anchor** shape only, reproduces at N=3, and is eliminated by a one-paragraph core edit — the program's first measured positive core delta, **adopted (kit r23) and confirmed non-regressing on the 18-task gradient at N=1**.
