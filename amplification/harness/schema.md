# Task JSON schema (Phase 0)

Each seed task is a single JSON object in `tasks/*.json`. The runner (`run.py`)
loads every `*.json` in the tasks dir, runs it under each condition through the
model adapter (`adapters.py`), and grades the output with a deterministic code
grader (`graders.py`). Prefer code-checkable graders — fast, objective,
reproducible, cheat-resistant (README section 3).

## Top-level fields

| field | type | required | meaning |
|---|---|---|---|
| `id` | string | yes | Stable unique id for the task (used in the run-log). |
| `dimension` | enum string | yes | One of: `reasoning`, `long_horizon_planning`, `factual_accuracy`, `calibration`, `verification`, `task_completion`. Maps to the amplified-intelligence dimensions in README section 1. |
| `prompt` | string | yes | The exact task text sent to the model as the user prompt. Self-contained; for code-graded tasks, ask for the answer in a checkable form (e.g. "reply with the final integer only"). |
| `grader` | object | yes | A grader object (see below). Dispatched by its `type`. Must be code-checkable for Phase 0. |
| `notes` | string | no | Author notes: the reference answer, why it is code-checkable, any planted flaw, balance rationale. Never sent to the model under test; when the lenient judge-fallback runs and the task has no `judge_reference`, the judge model receives `notes` as its grading reference. |
| `judge_reference` | string | no | Preferred reference answer for the lenient judge-fallback (`judge.py` uses it over `notes` when present). Never sent to the model under test. |
| `tools` | array | no | Reserved for Phase 1+ (tool-groundable tasks). Recorded in the run-log, not enforced in Phase 0. |

`dimension` is a label for aggregation; it does not change grading. A task is
graded solely by its `grader`.

## Grader object

A grader is an object with a `type` plus type-specific parameters. Every grader
returns `{passed: bool, score: float in 0..1, detail: str}`.

| `type` | params | passes when |
|---|---|---|
| `exact` | `expected` (str), `mode` = `"equals"` (default) or `"contains"` | normalized output equals (or contains) normalized `expected`. Normalization = lowercase + strip markdown emphasis (`*`, `` ` ``) + collapse whitespace. Word-like keywords match on word boundaries ("eve" never matches inside "every"); keywords ending in a digit refuse a following digit ("rows=5" never matches "rows=57"). |
| `numeric` | `expected` (number), `tolerance` (number, default 0), `which` = `"last"` (default) or `"first"` | a number parsed from the output is within `tolerance` of `expected`. When the first non-empty line OPENS with a number, that is the declared answer (answer-first convention — trailing explanatory notes cannot fail a correct answer); otherwise `which="last"` takes the final number (the "final answer" convention), so shown working is not penalised. |
| `keywords_all` | `keywords` (list of str) | every keyword appears (case-insensitive). Score = fraction present. A purely-numeric keyword is matched with digit boundaries, so `"0"` does not match inside `"100"`. |
| `keywords_any` | `keywords` (list of str) | at least one keyword appears (case-insensitive). |
| `ordered_steps` | `markers` (list of str) | every marker appears **in the given order** (each searched forward from the previous match). Score = fraction found in order. Use words/phrases, not bare numbers. KNOWN LIMITS (2026-07-16 review): grades vocabulary presence, not structure — an intro sentence enumerating the markers can satisfy it, and a synonym for a marker word fails it; and a marker sequence that also appears in an injected core contaminates that condition (grades prompt echo). Prefer it for format compliance, not plan quality. |
| `contains_none` | `forbidden` (list of str) | **none** of the forbidden strings appear. The planted-contradiction / must-not-appear check that directly measures verification & factual discipline. |
| `interval_contains` | `truth` (number), `lo_label` (default `"P5"`), `hi_label` (default `"P95"`) | the output carries labeled bounds (`P5: <n>` ... `P95: <n>`) with `lo < hi` and `lo <= truth <= hi`. The calibration grader: 1.0 contained; 0.5 well-formed but missed (overconfident); 0.25 unordered bounds; 0.0 no parseable interval (point answer). KNOWN LIMIT: no width requirement — an absurdly wide interval passes; pair with a width cap or judge when gaming is a concern. Each labeled bound is taken at its FIRST occurrence in the output (a later restated bound is ignored — unlike the judge's last-SCORE-line rule). |
| `all_of` | `graders` (list of grader objects) | **all** sub-graders pass. Score = mean of sub-scores. Lets one task assert several things at once (e.g. correct facts present AND a planted contradiction absent). |
| `llm_judge` | `judge_response` (str), `scale_max` (default 4), `threshold` (default 3) | **Pure parser of a different-model judge's verdict** — never calls a model itself. Parses `SCORE: <int>` (ordinal) or `VERDICT: CORRECT/INCORRECT`; passes iff `SCORE >= threshold`. The model call lives in `judge.py` and is wired by the runner as a **lenient fallback**: consulted only for cells a code grader FAILED, blind, on a model that must DIFFER from the one under test (`run.py --judge-fallback MODEL`; off by default, spends budget). It upgrades a code-FAIL the judge accepts (keeping both grades as provenance) and never overrides a code PASS. Motivation: keyword parsers are lossy (26%→86%→97% recall across parser types, arXiv:2606.24839). |

## Examples

Reasoning (exact numeric answer):

```json
{ "type": "numeric", "expected": 203, "tolerance": 0.5, "which": "last" }
```

Long-horizon planning (ordered steps AND a stated constraint):

```json
{ "type": "all_of", "graders": [
    { "type": "ordered_steps", "markers": ["expand", "migrate", "switch", "contract"] },
    { "type": "keywords_any", "keywords": ["backward compatible", "zero downtime"] }
] }
```

Factual accuracy (required facts AND a planted contradiction it must not repeat):

```json
{ "type": "all_of", "graders": [
    { "type": "keywords_all", "keywords": ["100", "0"] },
    { "type": "contains_none", "forbidden": ["boils at 90", "90 degrees"] }
] }
```

## Balanced / seeded-error design (README section 3)

- Build sets where a behavior should **and** should-not fire. `contains_none`
  and the "planted contradiction" pattern are the should-not side: a
  plausible-but-wrong answer must fail.
- Seeded-error tasks (a planted flaw the model must catch or must not repeat)
  directly measure the `verification` dimension.
- Grade the **outcome**, not the path: graders inspect the final output text,
  never the model's intermediate steps.

## Run conditions (set by `run.py`, not stored in the task)

Each task is run under one or more conditions (README section 3):

- **A0 — bare:** host model, no portable core (empty config-home). The floor.
- **A1 — +core:** same model with the portable core injected. The product.
- **R — reference bar:** the strongest reference model, bare.

`lift = mean(A1) - mean(A0)` and `gap = mean(R) - mean(A1)` are computed by
`score.py` per dimension and per condition.
