---
name: organize
description: Apply the three-folder organization rule - public working folder (git repo, publishable), private (sensitive, never uploaded), EXE (built artifacts) - to any folder — classify every item, move it where it belongs, tidy the subfolders. Use when the user says organize this folder, apply the three-folder rule, clean this directory up, or file these strays; audit-only when asked to check or verify a folder's organization.
---

# /organize — the three-folder rule, executed like a written order

The standing rule this skill enforces: a project container holds exactly three top-level folders (plus, where present, the container's own CLAUDE.md rule file — never file that away as a stray) —

1. **The public working folder** (in this system's container: `sharable\`) — everything under active development, including the git repo. The ONLY folder that may be uploaded or published, so it stays publishable at all times: no secrets, no credentials, no personal identifiers, no memory or config exports.
2. **`private\`** — everything sensitive: personal data, project-memory snapshots, populated MCP/config exports, client data, unredacted anything, scratch worth keeping. NEVER uploaded, NEVER committed to the public working repo, NEVER copied into the other two folders. It sits physically outside that repo; it may keep its OWN local-only, never-pushed git repo for version history — leak-safety comes from an enforced no-remote + pre-push block, not from the absence of git.
3. **`EXE\`** — built artifacts only (in the fable system: exactly one file, `FableSetup.exe`). Rebuilt by the build pipeline; never tracked in git; published via releases, not commits.

Subfolder discipline (folders 1 and 2, at all times): purpose-named directories; no loose files at a folder's root except entry docs (README/CHANGELOG class) and that folder's own dotfile config; kebab-case names for new directories; scratch and debris either deleted (only when reproducible) or filed under `private\scratch\`.

## Procedure

Target = the folder named in the order; none named → the current project container. Safety polarity: **misfiling something sensitive into the public folder is the unrecoverable direction — in doubt, file it `private\`.**

1. **Inventory** the target: full recursive listing (names, sizes, dates). Read file contents only as far as classification requires.
2. **Classify every item** with a destination and a one-line reason: public / private / EXE / delete-candidate (empty temps and build debris ONLY when the exact regeneration command can be named). Sensitivity screen for anything ambiguous: secret-shaped strings (key, token, password, connection-string patterns), personal identifiers (the machine's `$env:USERNAME`, `git config user.name` / `user.email`, email addresses), memory or config exports, `.env` files, browser or app data.
3. **Show the classification table before moving anything** when a user is present in the session; an unattended run moves only the unambiguous items, deletes nothing, and leaves the rest listed in `private\scratch\organize-report.md` (creating the folder if needed).
4. **Move with git-awareness**: files tracked by a repo move with `git mv` inside it — never plain-move tracked files out of a repo; the resulting change is left staged-or-noted for the user's commit (committing itself follows the session's commit rules — never uninvited); a `.git` directory always moves together with its whole tree, never split from it; nothing classified private ever crosses into a repo.
5. **Tidy the subfolders** per the discipline above — group strays into a few purpose-named directories rather than inventing one directory per file; never reorganize inside a repo's `src`-class trees beyond what the order asked.
6. **Verify and report**: the public folder sweeps clean for the step-2 identifier list (paste the decisive line — patterns, files scanned, hits); every moved item exists at its destination; the classification table, the sweeps run, and anything left unmoved go in the report. Where the target contains a git repository destined for publishing, the sweep covers HISTORY too — commit author metadata and historical trees/blobs — or the report states plainly that history was not swept: a clean working tree over a dirty history is not publishable. Deleting anything non-reproducible needs explicit approval first — quarantine to `private\scratch\` beats deletion.

**Audit mode** (the order says check / verify / audit organization): steps 1, 2, and 6 — report-only, no moves, no deletions.
