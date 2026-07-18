# Amplification regression gate — standing-run instruction file

Self-contained prompt for a scheduled (or manually recurring) gate run. Everything
the run needs is in this file; it assumes no memory of prior sessions.

## Scope (exactly this, nothing more)

1. From the repo's `amplification/harness/` directory, run:

   ```
   python regression_gate.py --report "<container>\private\amplification-runs\gate-<YYYY-MM-DD>.txt"
   ```

   (`<container>` = the project folder holding `sharable\` and `private\`.)
2. Read the report. `PASS` → done; log one line. `FAIL` → report the failing
   rung(s) verbatim to the user. **Diagnose only; never fix**: a drifted config
   is re-synced by the user via `/refresh-kit` or a reinstall — the gate run
   itself edits NOTHING outside its report file (no repo files, no `~/.claude`
   files, no schedule changes).
3. The gate is zero-budget. NEVER pass `--live-canary` in a scheduled run — it
   spends model budget and requires a fresh per-run user greenlight.

## Output channel

- The dated report file written by `--report` (kept in `private\amplification-runs\`).
- One summary line to the user: `gate PASS` or `gate FAIL: <rungs>`.

## Escalation path

- A FAIL is surfaced, never auto-remediated. Include the decisive report lines.
- Two consecutive runs failing the same way: stop re-running the checks and
  shrink to surfacing the standing failure each run until the user intervenes
  (per the standing-automation rule in CLAUDE.md); propose — never self-apply —
  any schedule change.

## Stop condition

- Run cap: 26 runs (~13 months at the registered 1st-and-15th cadence — 24 runs
  per year, not a true biweekly 26) or an explicit user stop, whichever comes
  first. On reaching the cap, ask the user whether to renew.

## Registration — DONE (2026-07-16)

Registered as the local scheduled task **`fable-amplification-gate`**
(`~/.claude/scheduled-tasks/fable-amplification-gate/SKILL.md`), cron
`13 8 1,15 * *` = 08:13 local on the 1st and 15th of each month (~biweekly, an
off-minute so the fleet doesn't cluster). It runs while the app is open (fires on
next launch if closed), notifies on completion, and is **diagnose-only** (never
edits files, never `/refresh-kit`, never `--live-canary`). The task prompt is a
self-contained copy of this file's essentials.

**Undo path:** delete the scheduled task `fable-amplification-gate` (via the
Scheduled section in the sidebar, or the scheduled-tasks facility). Nothing else
to clean up. Review/renew after ~1 year of runs. Per the standing-automation rule,
a rung failing the same way twice consecutively stops re-diagnosing and just
surfaces the standing failure until a user intervenes.
