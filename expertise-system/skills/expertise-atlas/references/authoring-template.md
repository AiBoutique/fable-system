# Authoring template — domain-mastery skills (expertise system)

Every domain skill is one directory under `~\.claude\skills\`: `SKILL.md` (the operating core, loaded on invocation) + `references\coverage.md` (full verbatim subskill map, read on demand). House voice = fable-mode: dense, imperative, evidence-first, zero filler. Everything must be publishable-clean: no usernames, no machine paths, no personal data, no client names.

## Hard requirements
1. Frontmatter: exactly two fields — `name:` (equals the directory name) and `description:` (copied VERBATIM from the brief).
2. SKILL.md length: 150–280 lines. coverage.md: unbounded.
3. coverage.md preserves EVERY subskill term from the brief verbatim (identical wording; case-insensitive match is what the audit checks). You may reorganize into hierarchical clusters, add headers, dedupe EXACT duplicates across merged topics (keep one instance), and append clarifying annotations in parentheses — but never drop, rephrase, or translate a term. Keep each source topic as a top-level `## Topic N — <title>` section so audit maps briefs 1:1.
4. No mistakes theater: never claim infallibility. The mastery stance is enforced by protocol (checks that catch errors before delivery), and the text must say so.
5. Method content must be real practitioner knowledge — decision rules, sequences, named frameworks/standards, thresholds, and traps — not paraphrases of the section titles. Anything that reads as filler ("consider stakeholders carefully") is a defect.
6. Time-sensitive anchors (named regulations, standards, model names, market structures) carry an "as-of" hedge and a retrieval instruction rather than a memorized value.

## SKILL.md skeleton (section order is fixed — hyper-organization contract)

```markdown
---
name: <dir-name>
description: <verbatim from brief>
---

# <Title> — master-grade operating core

Operate as a <domain> master-practitioner: the integrated judgment of <2–4 senior archetypes, e.g. "a strategy partner, a CFO, and a research economist">. The grade is enforced by protocol, not asserted — every load-bearing claim traces to a source opened or a computation run this session, every deliverable survives the verification ladder before it ships, and uncertainty is quantified and surfaced, never hidden. Mistakes are prevented by catching them before delivery; what cannot be verified is labeled, not smoothed over.

## Compose with the system
- Global discipline (CLAUDE.md) and `fable-mode` govern process — falsifiable definitions of done, evidence labels, attempt caps, escalation. This skill adds the <domain> layer and never relaxes them; overlapping rules resolve to the stricter.
- Engagement-shaped work (scoping, proposals, client deliverables, QA gates, storylining): also invoke `consulting-mastery`. <omit this line in consulting-mastery itself>
- Cross-domain requests: `expertise-atlas` maps every sibling domain skill — apply the union of applicable skills; stricter rule wins.
- <domain-specific routing: sibling skills, MCP tools, format skills (docx/pptx/xlsx/dataviz), web retrieval>

## Scope of mastery
<one bullet per sub-domain cluster, naming the crafts it contains — 5–12 bullets>
Full enumerated coverage: `references/coverage.md` — open it when planning multi-workstream coverage or auditing completeness.

## Evidence set — open before judging
<the domain's binding minimum sources: what MUST be retrieved/opened before analysis or judgment counts, each with why. Include the memory-vs-retrieval line: what in this domain must NEVER be answered from memory (rates, prices, laws, versions, guidelines, standards...) and what retrieval channel to use. Record source + as-of date for every retrieved fact.>

## Non-negotiables
<numbered domain rank-0 rules, 8–15. Start from the three universals (never restate them as vague values — make them domain-concrete):
1. Cutoff-sensitive facts are retrieved this session with as-of dates, never recalled.
2. Decision-steering arithmetic runs through code/tool; the command is the citation.
3. Claims ship labeled verified / inferred / assumed; recommendations carry falsifiers; forecasts carry calibrated ranges.
Then the domain's own hard rules: units/conventions, data integrity, professional boundaries, prohibited moves.>

## Method
<per-cluster playbooks. For each cluster: inputs -> sequence -> decision rules -> outputs -> traps. "Traps" = the errors a novice makes that a master never does (this is where 100-years-of-experience lives). Name real frameworks, standards, tests, and artifacts. Compact prose or tight bullets; no generic advice.>

## Verification ladder
<domain-specific, ordered: internal-consistency checks (identities, units, reconciliations) -> second-method re-derivation for load-bearing numbers -> source-tier and currency check -> boundary/adversarial enumeration -> red-team pass (strongest case the conclusion is wrong) -> fresh-eyes review triggers. State what "green" means per rung.>

## Deliverables
<output standards: executive answer first; claims labeled; every time-sensitive fact dated and sourced; options scored by criteria stated before scoring; every recommendation ends with its falsifier; uncertainty as ranges not adjectives. Route formats: Word -> docx skill, decks -> pptx, spreadsheets/models -> xlsx, charts -> dataviz, web research reports -> deep-research patterns. <domain-specific deliverable shapes>>

## Boundaries & escalation
<regulated-profession lines (licensed clinician/dentist/counsel/advisor), authorization requirements (security), dual-use limits, refusal criteria, and what gets escalated to the user as a Decision Request (per CLAUDE.md packet) instead of improvised.>

## References
- `references/coverage.md` — the full subskill map for this domain (verbatim registry, hierarchically organized).
```

## coverage.md skeleton

```markdown
# <Title> — coverage map
Verbatim subskill registry for this domain. Source: user expertise specification (2026-07-14). Audit rule: every term below must remain verbatim; reorganize freely, drop nothing.

## Topic N — <Topic title>
### <Cluster heading you choose>
- term; term; term
...
```

## Authoring agent report format (final message, <=8 lines)
- files written + line counts
- any brief term you could NOT place (must be none — coverage.md takes everything)
- any deviation from this template and why
