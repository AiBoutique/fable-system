param(
  [string]$SkillsRoot = "$env:USERPROFILE\.claude\skills",
  # PII hunt list is derived at runtime from the current machine/repo identity — no personal
  # identifiers are hardcoded, so this script is safe to publish. Pass -Extra to add project handles.
  [string[]]$Extra = @()
)
# Structure lint for the expertise system: frontmatter, section order, files present,
# line bounds (150-280 for domain skills), and publishable-cleanliness.
$domainSkills = @(
  'strategy-foresight','finance-value','economics-policy-geo','research-intelligence',
  'data-decision-science','operations-supply-chain','commercial-growth','people-org-change',
  'digital-enterprise-tech','ai-agentic-systems','cyber-trust','risk-governance-compliance',
  'sustainability-climate-esg','deals-ma-restructuring','delivery-product-innovation',
  'industry-sector-mastery','consulting-mastery','medicine-clinical-health','dentistry-oral-health',
  'biopharma-medtech','science-research-ops','physics-mastery','chemistry-materials',
  'software-engineering-mastery'
)
$sections = @('## Compose with the system','## Scope of mastery','## Evidence set','## Non-negotiables','## Method','## Verification ladder','## Deliverables','## Boundaries & escalation','## References')
# Runtime-derived identifiers to hunt for (never hardcode personal data in a publishable file):
$dirty = @()
$dirty += $env:USERNAME
try { $gn = (git config user.name)  2>$null; if ($gn) { $dirty += $gn } } catch {}
try { $ge = (git config user.email) 2>$null; if ($ge) { $dirty += $ge; $dirty += ($ge -split '@')[0] } } catch {}
$dirty += $Extra
$dirty = $dirty | Where-Object { $_ } | Select-Object -Unique
$fail = 0
foreach ($s in $domainSkills + @('expertise-atlas')) {
  $dir = Join-Path $SkillsRoot $s
  $skillMd = Join-Path $dir 'SKILL.md'
  $issues = @()
  if (-not (Test-Path $skillMd)) { Write-Output "[$s] FAIL SKILL.md missing"; $fail++; continue }
  $raw = Get-Content $skillMd -Raw
  $lines = Get-Content $skillMd
  if ($lines[0] -ne '---') { $issues += 'frontmatter: missing opening ---' }
  if ($lines[1] -ne "name: $s") { $issues += "frontmatter: name line is '$($lines[1])' (expected 'name: $s')" }
  if (-not ($lines[2] -like 'description: *')) { $issues += 'frontmatter: description line missing/misplaced' }
  else {
    # the platform caps description at 1024 chars: over it is a hard validation failure on
    # API / claude.ai upload, even though Claude Code loads the skill anyway (so nothing
    # else in this repo would notice). Measure the PARSED value, not the raw YAML line.
    $desc = $lines[2].Substring(12).Trim()
    if ($desc.StartsWith('"') -and $desc.EndsWith('"') -and $desc.Length -ge 2) {
      $desc = $desc.Substring(1, $desc.Length - 2).Replace('\"', '"')
    }
    if ($desc.Length -gt 1024) { $issues += "frontmatter: description is $($desc.Length) chars, over the platform's 1024 cap" }
  }
  if ($lines[3] -ne '---') { $issues += 'frontmatter: not closed at line 4' }
  if ($s -in $domainSkills) {
    $cov = Join-Path $dir 'references\coverage.md'
    if (-not (Test-Path $cov)) { $issues += 'references\coverage.md missing' }
    $pos = -1
    foreach ($sec in $sections) {
      $idx = $raw.IndexOf("`n$sec")
      if ($idx -lt 0) { $issues += "section missing: $sec" }
      elseif ($idx -lt $pos) { $issues += "section out of order: $sec" }
      else { $pos = $idx }
      # IndexOf finds only the FIRST occurrence, so a heading repeated later in the file
      # would otherwise pass the order check unseen
      if (([regex]::Matches($raw, [regex]::Escape("`n$sec"))).Count -gt 1) { $issues += "section duplicated: $sec" }
    }
    $n = $lines.Count
    if ($n -lt 150 -or $n -gt 280) { $issues += "SKILL.md length $n outside 150-280" }
  }
  foreach ($f in Get-ChildItem $dir -Recurse -File) {
    $c = (Get-Content $f.FullName -Raw)
    foreach ($d in $dirty) {
      if ($d -and $c -match [regex]::Escape($d)) { $issues += "CLEANLINESS: '$d' found in $($f.Name)" }
    }
  }
  if ($issues.Count -eq 0) { Write-Output "[$s] OK ($($lines.Count) lines)" }
  else { $fail++; Write-Output "[$s] FAIL"; $issues | ForEach-Object { Write-Output "  - $_" } }
}
# The skill list above is hardcoded; a skill added to disk but not to it would be linted by
# nobody. Flag any unknown directory rather than silently skipping it.
$known = $domainSkills + @('expertise-atlas')
if (Test-Path $SkillsRoot) {
  foreach ($d in (Get-ChildItem -LiteralPath $SkillsRoot -Directory)) {
    if ($d.Name -notin $known -and (Test-Path (Join-Path $d.FullName 'SKILL.md'))) {
      $fail++; Write-Output "[$($d.Name)] FAIL skill directory not in this script's list - add it so it gets linted"
    }
  }
}
Write-Output $(if ($fail -eq 0) { 'RESULT: ALL PASS' } else { "RESULT: $fail skill(s) failing" })
