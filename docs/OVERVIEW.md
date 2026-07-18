# What the Fable System Provides — features & measured performance

*Kit r39 · as of 2026-07-18.*

An honest overview: what the system *is*, what it *does*, and — the part most write-ups fabricate — what it has been **measured** to do, with the numbers and their limits. If you came here for a big "makes your model N% smarter across the board" headline, the short version is: **that number does not exist, and this document explains why the honest answer is more useful than an invented one.**

---

## 1. What it is

The Fable System is a portable **operating discipline** for an AI coding/agent model, plus the machinery to install it, enforce it, extend it into specialist domains, and — critically — **measure whether it actually helps.** It is designed so the reasoning discipline is model-agnostic (a *portable core*) and only the enforcement layer is platform-specific (a swappable *adapter*), so the same discipline can front Claude today and other models later.

Two design commitments run through everything:

- **Measure before claiming.** No rule change ships without an eval delta; nulls and failures are recorded, not hidden.
- **Scale ceremony to stakes.** The discipline is heavy for high-blast-radius work and gets out of the way for trivial edits.

---

## 2. What it does — features & enhancements

| Capability | What it provides |
|---|---|
| **Discipline core** (`src/claude-home/CLAUDE.md`, ~46 KB) | The rulebook: non-negotiables, a task Loop, rigor tiers by blast radius, domain rules (science/finance/medicine/UI), playbooks, a verification ladder, an intent gate + artifact-authority order, and memory scope-gates. This is the amplification content — model-agnostic prompt discipline. |
| **Operating-method skill** (`fable-mode`) | The *how*: decomposition into checkable sub-claims, hypothesis-driven probing, adversarial verification, orchestration patterns, evidence-labeled reporting — a 24-move reasoning set with worked exemplars. |
| **Portable core** (`amplification/core/portable-core.md`, ~12 KB) | The same discipline distilled to **~28% of the full core's size** with zero platform-specific tokens — the artifact you port to another model. Measured to preserve the full core's benchmark behavior (§3). |
| **Domain expertise layer** (`fable-expertise` plugin) | 24 master-practitioner domain skills + an `expertise-atlas` router spanning **63 professional & scientific domains** (finance, medicine, law, cyber, physics, chemistry, supply chain, …). Each ships a verbatim-term coverage file, structure-linted and audited. Installs as a Claude Code plugin; skills namespace as `fable-expertise:<name>` and auto-trigger by description. |
| **Enforcement hooks** (3, in `settings.json`) | A SessionStart standing order, a prompt classifier that flags high-risk/multi-step work, and a subagent verify-order injection — the deterministic layer that makes the discipline fire without relying on the model to remember. |
| **Eval harness** (`amplification/harness/`) | The measurement contract made runnable: a task suite with code-derived truths, deterministic graders (V/S/A separate axes), A0/A1/R conditions, infra-failure exclusion, and a 280-assertion self-test. This is how every performance claim below was produced. |
| **Regression gate** (`regression_gate.py`, twice monthly — 1st + 15th) | 6 zero-budget rungs (self-test, answer provenance, config-drift, non-negotiable lint, currency baseline, prompt-echo contamination) that catch drift between runs. |
| **Cross-model adapters** | Claude (live-proven) + Grok/OpenAI (dry-run-verified) behind one interface, so the portable core can be measured on other models when keys are supplied (a local OpenAI-compatible endpoint runs keyless via `--adapter-json` + loopback-only `allow_keyless`). |
| **Self-verifying installer** | One-click Windows exe with a SHA-256 integrity gate, backup-then-merge (never clobbers foreign config), previous-version cleanup via an install ledger (stale old-kit files removed and backed up; your edits kept), and a 188-assertion install self-test. |

---

## 3. Measured performance — the honest numbers

All figures are from this system's own eval harness on **Opus 4.8** as the host, with **`claude-fable-5` as the reference bar (R)**. Conditions: **A0** = bare model, **A1** = model + core, **R** = the reference model bare. Run logs live in `private\amplification-runs\` (not published); the aggregates below are re-derived from them.

### The headline, stated honestly

**There is no measured across-the-board percentage lift — because on the tasks tested, the bare host model is already at ceiling.** On an 18-task single-shot, tools-off text suite spanning six dimensions:

| Condition | Mean score | Source |
|---|---|---|
| A0 (bare Opus 4.8) | **0.965** | phase-2 gradient, N=1/cell |
| A1 (+ discipline core) | **0.972** | phase-2 gradient, N=1/cell |
| R (bare `claude-fable-5`, the bar) | **0.944** | phase-2 gradient, N=1/cell |

- **Measured lift (A1 − A0) = +0.007, read as 0.000.** An independent eval-validity review traced the entire nominal +0.007 to one contaminated cell (a task whose answer markers appear verbatim in the injected core); excluding it, the lift is zero. The bare model had no headroom to amplify here.
- **The harness held the frontier line: A1 matched or exceeded the Fable-5 reference on 5 of 6 dimensions** (gap = R − A1 = **−0.028**, N=1). Reaching the bar, not beating it by points, is the honest claim for this suite.

### Where a core change *did* measurably help

The one place the discipline produced a measured, reproducible gain is **calibration** — how well the model's stated confidence intervals contain the truth. On a held-out tight-anchor calibration bed (4 tasks, N=3/arm), adding a one-paragraph "[0,20] confidence scale" rule to the core:

| Arm | Interval hit-rate | Stability |
|---|---|---|
| base core | **0.833** | 0.833 |
| + [0,20] addendum | **1.000** | 1.000 |

**+16.7 percentage points on interval hit-rate (0.833 → 1.000), N=3, zero regressions.** This is the program's first measured positive core delta — and it is narrow and shape-specific (tight-anchor counting tasks), not a broad lift. Two honesty caveats: (a) a second candidate rule (a mechanical interval-widening instruction) tied at 1.000, so the [0,20] rule is *an* effective fix, not the uniquely effective one — it was the one adopted, with the widen rule as runner-up; (b) the change did **not** clear its own pre-stated "adopt iff a majority of tasks improve" bar — 3 of the 4 tasks were already at ceiling, making that rule unsatisfiable as written — so adoption was an **owner decision informed by the A/B**, not an automatic protocol pass. It is honest to call this *A/B-supported and owner-adopted*, not *A/B-mandated*.

### Regression safety of that change

Adopting the calibration addendum was re-run across the full 18-task gradient (base core vs adopted core, both fresh, N=1/arm; the two cores differ by exactly the 13 added lines):

- **0 regressions, 0 infra-exclusions.** 16 of 18 cells identical across arms; 2 cells rose but at N=1 both are run-to-run noise **not** attributable to a calibration rule (one is the known contaminated cell, one a base-arm miscount on an injection task the addendum cannot mechanistically affect). The raw mean shift (0.91 → 0.97) is *those two noisy cells*, not a real broad lift — reported here as "no regressions," never as a percentage gain.

### Efficiency

- **Portable core: ~28% of the full core's size (≈12.8 KB vs ≈46 KB today; measured when the full core was ≈43 KB), matching the full core's benchmark behavior.** The portable core measured **0.965** on the 18-task suite — equal to the full core once the single contaminated cell is excluded (the full core's raw 0.972 *is* that contaminated cell; §3 headline). That measurement was taken on the portable core in its prior form; it has since gained the same 13-line calibration addendum as the full core, which the gradient re-run showed causes 0 regressions. Net: the discipline's measured effect at roughly a quarter of the token cost, in a model-agnostic form.

---

## 4. What we deliberately did **not** claim

- **No "N% smarter across the board."** The measurement says lift ≈ 0 on single-shot tools-off text tasks because the base model is at ceiling there. Inventing a percentage would contradict the system's own evidence.
- **No blanket dimension wins.** The support for "the harness reaches the frontier bar" is *A1 ≥ R on 5/6 dimensions at N=1* — stated with that N, not inflated.
- **Recorded nulls stand.** Two earlier core-change candidates were rejected by their pre-stated A/B protocols; those nulls are kept on the record, not buried.

---

## 5. What is not yet measured (where lift is *plausible* but unproven)

The tested suite is single-shot, tools-off, and text-only — the conditions least favorable to scaffolding. The discipline's mechanisms that this suite **cannot** exercise, and where measured lift is expected but not yet demonstrated here:

- **Tool-dependent tasks** — the "do arithmetic through code, not mental math" rule is inert when no tools run.
- **Multi-turn, long-horizon jobs** — the ledger, compaction checkpoints, and milestone re-verification only pay off over many steps.
- **Adversarial verification / multi-agent** — independent-reviewer and refutation patterns need a fleet to show their effect.
- **Cross-model porting** — the portable core is measured on Claude; Grok/OpenAI runs await API keys.

Until those are measured, the honest framing is: **proven to hold the frontier line and to fix calibration on single-shot text; expected-but-unproven to lift harder, tool-using, long-horizon work.**

---

## 6. How the numbers are produced (reproducibility)

- Every code-checkable task truth is re-derived by an independent solver (`verify_answers.py`, 33 facts, 0 failures).
- Graders are deterministic and report **V** (validity/pass-rate), **S** (stability across repeated runs), and **A** (agreement with the reference bar) as *separate* axes — agreement is never optimized alone.
- Infra failures (e.g. a transient CLI/auth error) are excluded loudly as `score: None`, never scored as zeros.
- A 280-assertion self-test and a 6-rung twice-monthly regression gate guard the machinery itself.
- N is small (often N=1/cell) and is **always declared**; single runs are not presented as variance-characterized results.

Provenance: the aggregates cite `private\amplification-runs\` run logs; the detailed narrative is in [`../amplification/README.md`](../amplification/README.md) §7. Any external research percentages you may see in `docs/advancement-dossier-2026-07.md` are **directional context about the underlying techniques**, drawn from third-party literature — not measured claims about this system, and not quoted as such.

---

*This document reports measured results with their sample sizes and limits. If a figure here ever appears without its N or its source, treat that as a bug in the document, not a stronger claim.*
