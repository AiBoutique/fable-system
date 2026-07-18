# Expertise System — 24 domain-mastery skills + router

A composable layer of **master-practitioner domain skills** for Claude Code, built to operate at PhD-plus / senior-partner grade across 63 professional and scientific domains. Each skill installs into `~/.claude/skills/` and is invoked by name or auto-triggered by its description. They sit **on top of** the fable operating discipline (`CLAUDE.md` + the `fable-mode` skill): fable-mode governs *process* (falsifiable done, evidence labels, attempt caps, verification, escalation); each domain skill adds its domain's *judgment* — evidence sets, non-negotiables, method playbooks, verification ladder, deliverable standards, and boundaries. Where rules overlap, the stricter wins.

Built 2026-07-14. All content is publishable-clean (no personal data — verified by the cleanliness lint).

## What's here
- `skills/` — 24 domain skills + `expertise-atlas` (the router/index). Each is a directory with `SKILL.md` (the operating core) + `references/coverage.md` (the full verbatim subskill registry). `expertise-atlas` additionally carries `references/topic-map.md` (63 topics → owner) and `references/authoring-template.md`.
- `build/` — the authoring toolchain: `briefs/` (per-skill authoring inputs = the verbatim subskill lists), `authoring-template.md` (the structure contract), and two audit scripts (`audit-coverage.ps1`, `lint-structure.ps1`).

## The 24 skills
`strategy-foresight` · `finance-value` · `economics-policy-geo` · `research-intelligence` · `data-decision-science` · `operations-supply-chain` · `commercial-growth` · `people-org-change` · `digital-enterprise-tech` · `ai-agentic-systems` · `cyber-trust` · `risk-governance-compliance` · `sustainability-climate-esg` · `deals-ma-restructuring` · `delivery-product-innovation` · `industry-sector-mastery` · `consulting-mastery` · `medicine-clinical-health` · `dentistry-oral-health` · `biopharma-medtech` · `science-research-ops` · `physics-mastery` · `chemistry-materials` · `software-engineering-mastery` — plus `expertise-atlas` (router).

## Design (63 → 24)
The 63 source topics were consolidated into 24 skills to keep the skill-listing economical, make trigger descriptions precise, and share one method spine instead of duplicating it 63×. The full mapping is `skills/expertise-atlas/references/topic-map.md`. Consolidation examples: all four consulting-craft topics (communication, problem-solving, client management, negotiation) + methodology/BD/PS-economics/QA/ethics/effectiveness/tools/firm-ops fold into `consulting-mastery`; the three IT/architecture/emerging-tech topics into `digital-enterprise-tech`; the clinical + health-research + clinical-AI-safeguards topics into `medicine-clinical-health` (which hosts the health-safeguard charter that dentistry and biopharma cite); the science-method + lab-ops + lab-quality + boundaries topics into `science-research-ops` (which hosts the science-boundary charter).

## Shared contract (every domain skill guarantees it)
- Fixed section order: stance → Compose with the system → Scope of mastery → Evidence set → Non-negotiables → Method → Verification ladder → Deliverables → Boundaries & escalation → References.
- `references/coverage.md` preserves **every** source subskill term verbatim (auditable).
- Three universal non-negotiables: cutoff-sensitive facts retrieved with as-of dates (never recalled); decision-steering arithmetic through code/tool (the command is the citation); claims labeled verified / inferred / assumed, recommendations carry falsifiers, forecasts carry calibrated ranges.
- Binding professional boundaries: licensed-clinician / licensed-dentist / qualified-counsel / not-investment-advice lines; dual-use and CBRN limits; authorized-context-only security work.
- Mastery is enforced by protocol (the verification ladder runs before delivery), never asserted — no infallibility claims.

## Verification at build (2026-07-14)
- **Coverage audit** (`build/audit-coverage.ps1`): every verbatim subskill term from all 63 topics is present in its owning skill's `coverage.md` — **24/24 skills PASS, 0 missing terms** (largest registries: consulting-mastery 709, digital-enterprise-tech 398, software-engineering-mastery 394, science-research-ops 327).
- **Structure lint** (`build/lint-structure.ps1`): frontmatter, section order, 150–280-line bounds, and cleanliness — **25/25 PASS**.
- **Cross-reference & router integrity**: every backticked skill reference resolves — 0 dangling (re-verified 2026-07-18); atlas names all 24; topic-map = 63 rows → 24 valid owners; 24 unique descriptions, each within the platform's 1024-character cap. Routing lines that mention `fable-mode` or `invest-research` assume the fable kit is installed alongside the plugin, and ones naming `claude-api`, `code-review`, or `deep-research` assume the host environment provides them; all of these degrade to plain advice when absent. Likewise, the skills name **KnowledgePrime** as the market-data/desk MCP because that is what this system runs — every such line is hedged "where connected", so any equivalent market-data MCP (or plain web retrieval) satisfies the same instruction.
- **Independent adversarial review — done**: 6 reviewers over all 24 skills found no high-severity domain errors, boundary holes, or infallibility claims; the low/med precision refinements were all applied and re-audited. Full status and the per-skill index are in [`MANIFEST.md`](MANIFEST.md).

## Re-auditing after edits
From PowerShell 7 (`pwsh`):
```
pwsh -File build/audit-coverage.ps1        # every subskill term still present verbatim
pwsh -File build/lint-structure.ps1        # frontmatter, section order, length, cleanliness
```
Both resolve skills from `~/.claude/skills` by default. `audit-coverage.ps1` reads the briefs in `build/briefs/`. The lint derives its PII hunt-list at runtime (no personal data is hardcoded).

## Decisions
1. **Kit membership / distribution — RESOLVED (2026-07-17): ship as a plugin, coexist.** The 24 skills + `expertise-atlas` are packaged as the `fable-expertise` Claude Code plugin (`.claude-plugin/plugin.json`, v0.1.0; `claude plugin validate` → passes, with one intentional warning for the omitted `author` field, kept empty to hold the tree identifier-free) and install *alongside* the bare-named live skills — **not** baked into `FableSetup.exe`. Rationale: the plugin is the platform-native distribution and open-sourcing vehicle, and it avoids growing the exe/manifest/selftest (which the plugin path would ultimately retire). Posture **COEXIST**: keeping the bare-named originals means namespacing (`fable-expertise:<name>`) cannot break description-keyed auto-triggering — confirmed by a live A/B (2026-07-17). See the repo `CHANGELOG.md` and [`MANIFEST.md`](MANIFEST.md).
2. **Publishing.** The repo history was re-rooted at r28 (single scrubbed root commit) — see the repo root README → Publishing; what remains before a first push is only the remote, the Release (exe attach), and your choice of public identity on the license line.

An independent adversarial review across all 24 skills has already run (2026-07-14) and its findings were applied — see [`MANIFEST.md`](MANIFEST.md) → "Verified" and "Open". A further pass need only re-focus on the open items above, not re-verify coverage/structure/cleanliness/boundaries.
