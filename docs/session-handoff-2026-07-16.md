# Session Handoff — 2026-07-16 (final; for the next-session Fable review)

A cold-start resume snapshot. Pairs with machine-local memory (`~/.claude/projects/<slug>/memory/` → `project-fable-north-star.md`, `project-fable-mode-skill.md`), mirrored to `private/memory/`. **Next session's job: a full Fable review of everything below.**

## Objective (north star)
The fable system is a **model-amplification harness**: maximize the reasoning/planning/credibility/accuracy of whatever model runs it, to **match or exceed Fable 5**, measured per task-class. Architecture: a **portable amplification core** (`amplification/core/portable-core.md`) vs a swappable **platform adapter**; amplification logic never lives in the adapter.

## Ground truth
- Repo: `sharable/` on `master`, HEAD **`eb97e9b`** (kit r23). Six commits this session: `59c86d6` Phases 2–5, `7d79202` standing-up round, `2c4c80a` v4 A/B + Stability axis, `d06e011` core adoption, `897057f` doc scrub, `eb97e9b` kit r23. No git remote; **history predates the PII scrub — re-root before any first push.**
- Kit: **r23** — `EXE\FableSetup.exe` (102,912 bytes) rebuilt and sandbox-verified (INSTALL PASSED; installed CLAUDE.md hash == src; adopted section present). Manifest 21 files; installer selftest `TOTAL: 126 passed, 0 failed`.
- Env: Windows; Opus 4.8 host; `claude` CLI v2.1.211; Python 3.14.6; pwsh 7 / node 24. Reference model id **`claude-fable-5`** (`fable-5` invalid). **No Opus 5 exists** (verified 2026-07-16): tier = Fable 5 (bar) / Opus 4.8 (host) / Sonnet 5 / Haiku 4.5.
- Ops lesson: build the exe via PowerShell natively — `-OutFile ..\EXE\...` through bash mangles backslashes (caught live; stray deleted; recorded in memory).

## Headline result of this session
**The first A/B-validated core change shipped end-to-end.** The v4 tight-anchor calibration bed (4 held-out tasks, truths code-verified) discriminates: plain core 0.833 hit-rate (`calib-primes-8digit` missed 2/3, N=3). Both candidate edits fixed it (1.000, Stability 1.000, zero regressions); the owner adopted the **[0,20] "Stating calibrated confidence" section**, applied verbatim to all three carriers (kit src CLAUDE.md + live CLAUDE.md lockstep + portable core), hash-verified content-identical to the tested winning arm, and shipped in kit r23. Everything else measured stays at bare-Opus ceiling (honest lift 0.000 on the Phase-2 gradient; A1 ≥ R on 5/6 dimensions, gap −0.028).

## What exists now (all committed)
- **Benchmark:** 18 gradient tasks + 2 domain + 6 extreme-magnitude calib + 4 tight-anchor calib; every truth in `verify_answers.py` (**28 facts**). Harness selftest **238 assertions**. Graders incl. `interval_contains` + `llm_judge` (blind different-model lenient fallback, off by default). Scoring reports **V / S / A separately** (Stability = pairwise agreement over repeated runs; never optimize agreement alone).
- **Conditions:** A0 / A1 / A1′(portable) / R via `run.py` (`--dry-run` default; infra-failed cells excluded as score:None; `--judge-fallback MODEL`).
- **Adapters:** claude_cli (live-proven); grok + openai dry-run-verified (targets in `core/adapter-targets.md`; live needs `XAI_API_KEY`/`OPENAI_API_KEY` — never handled in plaintext).
- **Continuous:** `regression_gate.py` **6 rungs** (selftest, provenance, config-drift incl. settings-discipline-minus-personal-overlays, non-negotiable lint, currency baseline, contamination guard) — registered as the biweekly scheduled task **`fable-amplification-gate`** (1st + 15th, 08:13, diagnose-only, ~26-run review cap; undo = delete the task). Run-logs + gate reports in `private\amplification-runs\`.
- **Candidate trail:** v2 (inert, rejected) → v3 ([0,20]: rejected on the saturated open bed, ADOPTED after the tight-anchor win) → v4 plan (resolution + intent-gate finding + amended future protocol: majority of BELOW-CEILING tasks).

## Open decisions for the Fable review
1. **Kit membership (dossier P0.1):** recommendation recorded — resolve via the plugin path (P0.2), not by growing the exe; interim keep the 24 expertise skills separate. Adjudicate + execute here.
2. **Live cross-model runs:** one command in `adapter-targets.md` once the owner exports API keys.
3. **Calibration next:** broaden the tight-anchor bed (the v4 falsifier: a bed where [0,20] misses but the widen rule contains); consider re-measuring A1′ (portable core now carries the addendum).
4. **Publish:** git-history re-root + license choice before first push.
5. **Off-machine backup of `private\` + repo:** still manual, still pending (memory has NO automated backup since r19).

## Resume checklist
1. Read this + memory (`project-fable-north-star.md`) + `amplification/README.md` §5–§7.
2. `git -C sharable status` clean at `eb97e9b`+; `python amplification/harness/regression_gate.py` → 6 rungs PASS.
3. Live runs spend budget — per-run greenlight; `claude auth status` → loggedIn:true.
4. Treat every claim here as unverified until re-checked against the tree.
