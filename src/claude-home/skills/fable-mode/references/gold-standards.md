# Gold standards — imitate these shapes

Exemplars beat abstractions: match the *shape* of these before inventing your own. Each entry earned its place by user praise or a top-tier review verdict. Keep the file under ten entries, one screen each; add only when an output earns explicit praise or a top-tier review verdict; prune anything that ages badly.

## 1. Mechanism sentence (before any fix)
> cache key omits locale → stale FR pages served → keying on (path, locale) interrupts it (cache.ts:42)

Cause → effect → why this diff interrupts it, anchored to a read line. One sentence. If it can't be written, diagnosis isn't done.

## 2. Evidence line (verified claim)
> verified: `json_valid=True; events=SessionStart,SubagentStart,UserPromptSubmit; other_hooks_intact=True`

The decisive output line pasted, not paraphrased, behind an explicit "verified" label. A claim without its line is an opinion.

## 3. Delegation brief (independent reviewer)
> Files (read them yourself): [paths]. User's request, verbatim: "…". Your lens: [ONE named lens]. Deliverable: PASS or FAIL, then EVERY finding as [severity][confidence] — finding — exact location — suggested fix. End with the exact checks you ran. Facts and findings only.

Artifact + verbatim request + one lens + forced finding format + checks-run demand — and zero author reasoning shared. A reviewer told what to expect is no longer independent.

## 4. Accepted-limitation disposition
> Accepted, documented: the grep covers the whole stdin JSON, so a repo path containing a stem (e.g. `auth-service`) fires every prompt — paths verified stem-free today. Trigger to revisit: stem-bearing repo path or classifier spam → ship the prompt-scoped v3.

Name the limit, prove it's currently harmless, attach the exact trigger that reopens it. Honest beats silently perfect. (Historical exemplar — the prompt-scoped v3 hook has since shipped; kept for its shape.)

## 5. Outcome-first report opener
> **Done — CLAUDE.md is now fable-aligned (v3), the skill is hardened to match, and the two files operate as a coupled system. Both passed independent two-lens review; all 18 findings fixed.** Full detail below.

The first sentence answers "what happened" completely; everything after is for readers who want more. Never open with process narration. (Historical exemplar — kept for its shape.)

## 6. Surprise handling (mid-task)
> `stale[Every rule below exists]=1` — expected 0. Halt: case-insensitive matcher caught the NEW "Nearly every rule below exists" phrasing — false positive in the probe, not a stale leftover. Confirmed with a case-sensitive re-check (`old_exact_casesensitive=0`), then continued.

Prediction stated, mismatch treated as signal, cheapest discriminating re-probe run, resolution recorded — no silent shrug, no panic rewrite.

## 7. INTENT line (before making a failing check pass)
> INTENT: code returns 10% (pricing.py:12) / test expects 15% (test_pricing.py:8) / README + docstring say 10% — the test is the outlier. Surfacing the conflict and fixing the test to match spec, not editing correct code to pass a wrong test.

Three-way statement — code / check / spec — written BEFORE any behavior-changing edit, with the authority order (user > spec > tests > code) resolving the disagreement out loud. The disagreement itself is the finding; never silently reconcile one side toward another. (Eval-proven: as a forced artifact at the decision point this moved weak executors from 0/4 to 4/4 on spec-vs-test traps.)

## 8. Data-quality judgment call (before any ranking or aggregate)
> Issues found and DECIDED, each with its rule: ticket 4412 appears 3× byte-identical → duplicate export rows, count once (no line-item or quantity column distinguishes them); ticket 4419 dated outside the reporting window → excluded, stated; assignee "m. chen" vs "M. Chen" → same person, folded; a −80 credit adjustment → netted, not dropped; one date "03 Jun 2026" in a day-first file → parsed, not discarded. Sensitivity: counting 4412 three times flips the top assignee — the dedupe call decides the answer, so it is stated with its rule, never silent.

Seeing every issue is table stakes; the graded act is the per-issue DECISION, its stated rule, and the sensitivity check showing which call changes the result. (Eval-derived: the trap class where executors list every issue and still aggregate wrong.)
