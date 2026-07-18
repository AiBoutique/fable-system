# Expertise System — manifest & verification status

Fast-orientation index for the 24 domain-mastery skills + `expertise-atlas` router. Built and hardened 2026-07-14. **Read this before scanning the skill files** — it records what has already been verified (so a review pass need not re-check it) and what remains open.

## At a glance
- **24 domain skills + 1 router** covering **63 source topics**, **4,996 verbatim subskill terms** total.
- Every domain skill: `SKILL.md` (operating core, fixed 9-section order, 150–280 lines) + `references/coverage.md` (verbatim term registry); the `expertise-atlas` router is exempt from both bounds by design (66 lines, router sections). `expertise-atlas` adds `references/topic-map.md` (63→owner) + `references/authoring-template.md`.
- Publishable-clean (0 personal identifiers / machine paths — swept).

## Skill index
| Skill | Topics | Coverage terms | SKILL.md lines |
|---|--:|--:|--:|
| ai-agentic-systems | 1 | 132 | 155 |
| biopharma-medtech | 1 | 78 | 165 |
| chemistry-materials | 3 | 309 | 154 |
| commercial-growth | 4 | 235 | 196 |
| consulting-mastery | 12 | 709 | 171 |
| cyber-trust | 1 | 98 | 188 |
| data-decision-science | 2 | 168 | 196 |
| deals-ma-restructuring | 2 | 117 | 181 |
| delivery-product-innovation | 2 | 135 | 157 |
| dentistry-oral-health | 2 | 184 | 158 |
| digital-enterprise-tech | 3 | 398 | 162 |
| economics-policy-geo | 3 | 169 | 170 |
| finance-value | 2 | 125 | 190 |
| industry-sector-mastery | 1 | 89 | 198 |
| medicine-clinical-health | 3 | 299 | 151 |
| operations-supply-chain | 2 | 140 | 160 |
| people-org-change | 4 | 213 | 165 |
| physics-mastery | 2 | 191 | 157 |
| research-intelligence | 3 | 197 | 167 |
| risk-governance-compliance | 3 | 182 | 156 |
| science-research-ops | 4 | 327 | 151 |
| software-engineering-mastery | 1 | 394 | 207 |
| strategy-foresight | 1 | 49 | 152 |
| sustainability-climate-esg | 1 | 58 | 176 |
| **expertise-atlas** (router) | — | — | 66 |

## Verified — do not re-check (2026-07-14, all executed)
- **Coverage** (`build/audit-coverage.ps1`): all 63 topics' verbatim subskill terms present in their owning `coverage.md` — 24/24 PASS, 0 missing.
- **Structure** (`build/lint-structure.ps1`): frontmatter (name=dir, description present), fixed 9-section order, 150–280-line bound, cleanliness — 25/25 PASS.
- **Cross-reference integrity**: every backticked skill reference across the 25 `SKILL.md` files resolves — to one of the 24 domain skills, the atlas, a fable-kit skill (`fable-mode`, `invest-research`), or a Claude Code built-in; 0 dangling or typo'd references (re-verified 2026-07-18; the earlier "410 refs / 30 distinct" figures are dropped — their extraction rule was never recorded, so they are not reproducible).
- **Router consistency**: atlas directory names all 24; `topic-map.md` = 63 rows → 24 valid owners; 24 unique descriptions.
- **Independent adversarial review**: 6 reviewers (one per themed cluster) over all 24 skills — **no high-severity domain errors, no boundary holes, no infallibility claims**. cyber-trust and delivery-product-innovation returned fully clean; all others drew low/med precision refinements, **all applied and re-audited** (the reviewers' raw trail was retained privately, never shipped; the fixes it produced are listed here and in the repo `CHANGELOG.md`). Correctness fixes landed: dentistry split-mouth statistics, biopharma 505(b)(2) + Topic-51 citation, OEE/TEEP denominator, physics weapons-boundary framing-resistance parity, FinOps 3-phase, IV weak-instrument floor, Galbraith Star.
- **Safety boundaries verified present & correct**: licensed-clinician (medicine) / licensed-dentist (dentistry) gates; clinical-numbers-never-from-memory; graded-cited-evidence; absolute CBRN clause (chemistry) with framing-resistance; weapons-physics refusal (physics) with framing-resistance parity; science boundary charter hosted in science-research-ops; dual-use/authorized-only (cyber, software, ai); not-investment-advice (strategy, finance, economics); awareness-not-legal-advice → qualified counsel (risk-governance, consulting).

## Re-audit (after any edit)
```
pwsh -File build/audit-coverage.ps1     # every subskill term still present verbatim
pwsh -File build/lint-structure.ps1     # frontmatter, section order, length, cleanliness
```
Both default to `~/.claude/skills`; the coverage audit reads `build/briefs/`. No personal data is hardcoded (the lint derives its hunt-list at runtime). The lint acknowledges the four fable-kit skills that coexist in the live root (`fable-mode`, `invest-research`, `organize`, `refresh-kit`) and flags any other unlisted skill directory.

## Open (a review pass should focus here, not on the above)
1. **Kit membership / distribution — RESOLVED (2026-07-17): plugin, coexist.** Packaged as the `fable-expertise` Claude Code plugin (`.claude-plugin/plugin.json` v0.1.0 at resolution, now 0.2.0; `claude plugin validate` → passes with one intentional warning, the omitted `author` field), installed *alongside* the bare-named live skills — not baked into `FableSetup.exe`. The plugin is the platform-native distribution; COEXIST keeps auto-triggering intact (live A/B, 2026-07-17). See the repo `CHANGELOG.md`.
2. **Currency** — named standards/regulations/thresholds (IFRS/ISSB, EU AI Act, NIST, FIPS, ICH, GHG Protocol, etc.) are deliberately retrieval-gated in-text ("retrieve current … as-of date"), not asserted as current. A pass wanting live values should retrieve them; the skills already mandate this at use time.
3. **Publishing** — RESOLVED at the repo level: the git history was re-rooted at r28 to a single scrubbed root under a neutral identity (repo root README → Publishing); the pre-scrub dev history survives only in the local `archive/pre-publish-history` branch, which must never be pushed.
