# Fable System

A complete operating discipline for [Claude Code](https://claude.com/claude-code) — the process behind frontier-grade agent output, packaged so any Windows machine (and any executor model) can run it: a global rulebook, an operating-method skill, three enforcement hooks, a monthly self-audit, a behavioral trap-suite eval, and a one-click installer that verifies itself.

> **New here?** [`docs/OVERVIEW.md`](docs/OVERVIEW.md) explains what the system provides and — with sourced numbers and their sample sizes — what it has actually been *measured* to do (including where the honest answer is "no measurable lift, and here's why"). The same material, merged with this README as a single dark-mode page, is [`docs/index.html`](docs/index.html) (GitHub Pages-ready).

## Install

**Windows, one click:** run **`FableSetup.exe`** (from a GitHub Release, or build it yourself — below) — the whole kit is embedded; it extracts, installs, verifies, and cleans up. Unattended: `FableSetup.exe -Unattended`.

**From this checkout:** `src\INSTALL.bat` (same installer, same integrity gate).

**macOS/Linux:** manual steps in [src/restore-walkthrough.html](src/restore-walkthrough.html) (the hooks are bash-native; the installer is Windows-specific).

After installing, open a new session and run the two-minute check in [src/RESTORE.md](src/RESTORE.md).

**No personal data ships in the public kit**: no project memory, and an empty MCP template you populate locally (`src\tools\export-mcp-template.js` redacts secrets automatically).

## What's inside

| Piece | Purpose |
|---|---|
| [src/claude-home/CLAUDE.md](src/claude-home/CLAUDE.md) | The global discipline file: non-negotiables, the task Loop, rigor tiers, domain rules, playbooks, verification law, intent gate + artifact-authority order, memory scope gates. |
| [src/claude-home/skills/fable-mode/](src/claude-home/skills/fable-mode/SKILL.md) | The operating method: 9 sections + a 24-move reasoning list, with exemplar gold standards. |
| [src/claude-home/skills/refresh-kit/](src/claude-home/skills/refresh-kit/SKILL.md) | Rebuilds the kit + exe from live files, with a personal-data scrub gate. |
| [src/claude-home/skills/organize/](src/claude-home/skills/organize/SKILL.md) | The three-folder rule as a written order: classify → move → tidy any folder (public working repo / private / EXE; in doubt → private). |
| [src/claude-home/skills/invest-research/](src/claude-home/skills/invest-research/SKILL.md) | A domain-playbook template (finance research) showing how to specialize the system. |
| [src/claude-home/settings.json](src/claude-home/settings.json) | Three hooks: a SessionStart standing order, a prompt classifier, and a subagent verify-order injection. |
| [src/claude-home/scheduled-tasks/](src/claude-home/scheduled-tasks/fable-health-check/SKILL.md) | Monthly read-only health audit of the whole system. |
| [src/install.ps1](src/install.ps1) + [src/tools/](src/tools/) | The installer: SHA-256 set-equality integrity gate, backup-then-merge (never clobbers foreign config), an install ledger with previous-version cleanup (stale old-kit files removed, backed up; user files kept), self-verification table, plus the build and export tools. |
| [eval/](eval/README.md) | Trap-suite regression harness: 8 adversarial fixtures that test whether the rules actually change model behavior. |
| [amplification/](amplification/README.md) | The measurement program behind the numbers in [`docs/OVERVIEW.md`](docs/OVERVIEW.md): the portable core, a code-graded eval harness, a twice-monthly regression gate, and cross-model adapters. Not part of the installed kit — the evidence layer that keeps it honest. |
| [expertise-system/](expertise-system/README.md) | An optional domain layer: 24 master-practitioner skills + an `expertise-atlas` router over 63 professional & scientific domains, shipped as the `fable-expertise` Claude Code plugin. Installs alongside the kit, not inside `FableSetup.exe`. |

The payload directory is named `claude-home\` (not `.claude\`) so cloning this repo never registers duplicate scoped skills in your own sessions; the installer maps it to `~\.claude\` at install time. One expected quirk: working in a session *under* `src\claude-home\` loads the payload CLAUDE.md as directory context — it is the same rulebook you would install.

## The rules earn their keep

**No rule change ships without evidence.** The [eval/](eval/README.md) trap suite (fixtures adopted unchanged, MIT, from [Sahir619/fable-method](https://github.com/Sahir619/fable-method)) must pass at its prior level — or a new failing trap lands first. The installer ships with its own 171-assertion harness (`src\tools\run-selftest.ps1`), run on every rebuild; its totals are logged in [CHANGELOG.md](CHANGELOG.md) and [build-receipts.jsonl](build-receipts.jsonl), while the trap-suite rounds are logged in [eval/RESULTS.md](eval/RESULTS.md) — nulls and failures included.

## Build the exe yourself

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src\tools\make-manifest.ps1 -KitRoot src -KitVersion rN
pwsh -File src\tools\run-selftest.ps1 -Kit src     # TOTAL: 171 passed, 0 failed
pwsh -File src\tools\build-exe.ps1                  # -> FableSetup.exe (repo root; -OutFile ..\EXE\FableSetup.exe under the three-folder layout)
```

The exe is a small C# stub (compiled with the .NET Framework `csc.exe` that ships with Windows — no toolchain to install) with the kit embedded as a resource. It is unsigned: Windows SmartScreen may warn on first run; building it yourself from this source sidesteps that concern. The binary is not tracked in git (`.gitignore`): on the development machine it lives in the sibling `EXE\` folder per the three-folder container rule (sharable working repo / `private\` / `EXE\`); when publishing, attach it to GitHub Releases.

## Publishing (when you finalize)

1. **History**: already re-rooted (r28; re-dated to UTC-only timestamps in r29, trees and messages byte-identical) — `master` carries a single scrubbed root commit under a neutral identity with no timezone signal. The pre-scrub development history survives only in the local `archive/pre-publish-history` branch: never push that branch, and never add it to any remote — a local `pre-push` hook refuses every destination except `master`, and refuses any push whose source is not the local master tip, as a backstop. Git hooks never travel with clones: re-create the guard in any secondary clone of this repo, or rely on push-only-master discipline there.
2. **License**: MIT, already in the tree ([LICENSE](LICENSE)) under a neutral "Fable System authors" holder — put your public name on the copyright line if you want attribution.
3. **Publish by `git push`, not by copying the folder.** The tracked tree and every commit on `master` are scrubbed and identity-neutral, but `.git\logs\` (the reflogs) still records the pre-scrub author name, email, and local-timezone offsets — a re-root does not rewrite reflogs. Reflogs never travel over `push`, so the push route is clean; a raw folder or zip copy is not. Copying instead? Exclude `.git\`, or expire the reflogs first (`git reflog expire --expire=now --all && git gc --prune=now`) — that permanently deletes recovery metadata, so take a backup copy of the repo first.
4. **Attach `FableSetup.exe` to a GitHub Release** — the binary is untracked by design.
5. Push under the identity you intend to be public (`git config user.name` / `user.email` for the new history).

## Credits & license

The eval fixtures are adopted unchanged from [Sahir619/fable-method](https://github.com/Sahir619/fable-method) (MIT — see [eval/LICENSE-upstream](eval/LICENSE-upstream)), an independent distillation of the same working method whose eval program validated several of this system's rules.

License for this repository: **MIT** ([LICENSE](LICENSE)); the bundled eval fixtures remain under their upstream MIT terms ([eval/LICENSE-upstream](eval/LICENSE-upstream)).
