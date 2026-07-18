# Fable System — Restore Guide

This kit restores the complete fable system — frontier-grade process from any executor model — onto a fresh (or existing) Windows machine: the global discipline file (CLAUDE.md), four skills (fable-mode with its gold-standards references, refresh-kit, invest-research, organize), the three settings.json hooks, the monthly health-check task prompt, and user-scope MCP registrations from a redacted template. The kit's `claude-home\` tree maps to `~\.claude\` at install time — the dotless name keeps a cloned repo from registering duplicate scoped skills in sessions opened inside it.

## One-click restore

**Preferred — `FableSetup.exe`** (from the `EXE\` folder beside this repo, a GitHub Release, or your off-machine copy). Double-click it, or run unattended:

```
FableSetup.exe -Unattended [-TargetHome <dir>]
```

The exe carries the whole kit embedded: it extracts to a private %TEMP% staging dir, runs the kit's installer with your arguments passed through, propagates the exit code (0 pass / 1 fail / 2 user abort), and removes its staging dir.

**From a repo checkout or extracted kit:** double-click `INSTALL.bat`, or:

```
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

What the installer does (and won't do):

- **Integrity gate first**: every kit file is SHA-256-verified against `kit-manifest.json`, set-equality both ways — altered, missing, AND unlisted extra files all refuse the install. (Legacy rescue: if the gate fails and a `fable-restore-kit-*.zip` sits beside the script, it offers to extract and continue from the verified archive — retained for old zips in the wild; the zip model itself is retired since r19.)
- **Copies** CLAUDE.md, the four skills, and the scheduled health-check prompt. Anything it would overwrite is backed up to `.claude\fable-install-backup-<stamp>\` first.
- **Merges, never clobbers**: an existing `settings.json` keeps all foreign keys and hooks — the three fable hooks are added exactly once (deduped by command string, superseded fable variants replaced signature-gated, validation-gated with automatic rollback). Same for `~\.claude.json`: existing MCP servers are untouched; template entries are added only where absent.
- **Cleans previous versions (r25+)**: each install writes an install ledger (`.claude\fable-install-ledger.json`) recording what it placed with SHA-256 hashes. The *next* install removes files a previous r25+ kit installed that the new kit no longer ships — only while still byte-identical to what that install wrote (backed up first, emptied dirs pruned; never `settings.json`, credentials, memory, or backups). Anything you edited or created yourself is always kept. Prospective by design: the first r25 install writes a baseline only, so pre-r25 leftovers are not retroactively removed.
- **No personal data**: the public kit ships **no project memory** and an **empty MCP template**. Populate `mcp-servers.template.json` from your own machine with `node tools\export-mcp-template.js "%USERPROFILE%\.claude.json" mcp-servers.template.json` — secrets are auto-redacted to `<<SET-ME>>` and home paths tokenized to `<<HOME>>` (never commit a populated template without checking it).
- **Cleans up after itself**: rotates its own %TEMP% transcript logs (newest 10), removes stale extraction dirs, offers post-install cleanup of byte-verified duplicate kit files in the launch folder (default No inside a git repository — those are canonical sources), reports and optionally prunes old install backups (the 3 newest always kept).
- **Verifies itself**: ends with a PASS/FAIL table checked against the manifest; exits non-zero on any failure. **Idempotent**: safe to re-run.
- Flags: `-Unattended`, `-TargetHome`, `-ProjectPath`, `-ForceMemory` (only meaningful for private kits that ship memory).

## Post-install (two minutes, in a NEW session)

- `/fable-mode` → the skill loads.
- *"any standing orders?"* → the SessionStart standing order is cited.
- Submit *"refactor the auth module"* → transcript shows the `Prompt classifier (user hook)` line.
- Spawn any subagent and ask what standing orders it sees → the verify-before-reporting order.
- Re-create the monthly health check (the schedule lives in the app's own data, not in files): tell Claude *"Create a monthly scheduled task named fable-health-check, 1st of the month at 09:00, using the prompt file at .claude\scheduled-tasks\fable-health-check\SKILL.md"*, then click **Run now** once so its tool permissions get pre-approved.
- *Optional, advanced* — if you run the `amplification\` measurement program, its twice-monthly (1st + 15th) regression gate is a **machine-local** scheduled task (not shipped in the kit, since it hardcodes your container path): re-create it from the self-contained recipe in `amplification/regression-gate.md` (repo checkout only — not in the exe payload, which embeds `src\`), which carries its own cron, undo path, and stop condition.

Any failure: `claude --debug` shows hook execution — or point Claude at this kit and say **"restore and verify the fable system from this kit."**

macOS/Linux: same layout under `~/.claude/`; the hooks are bash-native and run as-is; use the manual steps in `restore-walkthrough.html`, adapting their paths as you go — those snippets are written in Windows PowerShell form (`"$HOME\.claude\..."`), so use forward slashes and `cp -r` (INSTALL.bat, install.ps1, and FableSetup.exe are Windows-specific).

## Contents

| File | What it is |
|---|---|
| `INSTALL.bat` + `install.ps1` | The installer (Windows PowerShell 5.1-compatible). |
| `kit-manifest.json` | SHA-256 manifest of every kit file — the integrity gate. Regenerated by `tools\make-manifest.ps1`. |
| `mcp-servers.template.json` | User-scope MCP registrations to add at install time. **Ships empty** in the public kit; populate locally with `tools\export-mcp-template.js` (secrets redacted, home paths tokenized). |
| `plugins-snapshot.json` | Marketplaces + plugin names present at build time (informational; `@inline` entries ship with the app). |
| `tools\fable-merge.js` | Safe JSON merges (hooks into settings.json; MCP servers into .claude.json). |
| `tools\export-mcp-template.js`, `tools\export-plugins.js`, `tools\make-manifest.ps1` | Kit-build tools. |
| `tools\run-selftest.ps1` | The full installer harness (157 assertions; the TOTAL line it prints is the count of record) — sandboxes under %TEMP%, needs PowerShell 7 + Node.js + Git Bash + `claude` on PATH. |
| `tools\build-exe.ps1` + `tools\setup-stub.cs` | Builds `FableSetup.exe`: embeds this kit as a payload in a small C# stub compiled with the .NET Framework `csc.exe` every Windows box ships. |
| `claude-home\CLAUDE.md` | The global discipline file: Rank-0 non-negotiables, the Loop, rigor tiers, playbooks, verification law, intent gate + artifact-authority order, binding minimum evidence sets, judge-stance verifier briefs, memory scope gates, doubt/innovation router. |
| `claude-home\skills\fable-mode\` | The operating method: 9 sections + 24-move reasoning list, plus `references\gold-standards.md` exemplars. |
| `claude-home\skills\refresh-kit\` | One-command kit rebuild: sync live → src, scrub gate, manifest, selftest, exe build + verify. |
| `claude-home\skills\invest-research\` | Domain playbook template for investment research (edit the profile line to taste; never executes trades). |
| `claude-home\skills\organize\` | The three-folder rule as a written order: classify → move → tidy any target folder (in doubt → private). |
| `claude-home\settings.json` | Three hooks + three benign prefs: SessionStart standing order; UserPromptSubmit prompt-scoped classifier v8; SubagentStart verify-order injection. |
| `claude-home\scheduled-tasks\fable-health-check\` | Monthly read-only audit prompt (preflight, pair consistency, hook behavior, adoption, kit freshness, memory scope integrity). |
| `restore-walkthrough.html` | This guide as a self-contained dark-mode page, with the manual restore steps. |

## Maintenance contract

- **CLAUDE.md and fable-mode SKILL.md are a coupled pair.** A threshold or rule change in one propagates to the other (shared numbers: 2-attempt cap; 1 reviewer default / 2 for High-risk; ≥3 pre-declared flake runs; Ledger threshold 3+ dependent edits or commands, or 3+ files).
- **No rule change without evidence.** The trap-suite regression harness lives at the repo root (`eval\` — fixtures adopted from Sahir619/fable-method, MIT): a change to CLAUDE.md, the fable-mode skill, or the hooks ships only with the suite passing at its prior level, or with the new failing trap added first; rounds are recorded in `eval\RESULTS.md`, nulls and failures included.
- **Material edits get a fresh-eyes two-lens review** (correctness; security/edges) on the strongest available model before adoption — every version shipped that way.
- **After any change: run `/refresh-kit`** — syncs live system files → `src\`, scrub-gates for personal data, regenerates the plugins snapshot and manifest, runs the full selftest (TOTAL line = the contract), rebuilds `FableSetup.exe` (to the sibling `EXE\` folder under the three-folder rule), verifies the shipped exe end-to-end, and mirrors the live memory into the container's `private\memory\`. Single-exe policy: no zips.
- **Off-machine copy is manual**: keep the repo (or at least `FableSetup.exe`) somewhere that isn't this machine. Since r19 the kit carries **no project memory** — personal memory under `~\.claude\projects\...\memory\` has no automated backup unless you set one up.

Version history: `CHANGELOG.md` at the repo root.
