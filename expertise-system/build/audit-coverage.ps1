param(
  [string]$BriefDir = "$PSScriptRoot\briefs",
  [string]$SkillsRoot = "$env:USERPROFILE\.claude\skills",
  [string[]]$Only
)
# Audits: every verbatim term in each brief's "## Topic N" lists must appear (case-insensitive,
# whitespace-collapsed substring) in the owning skill's references\coverage.md.
$fail = 0
foreach ($bf in Get-ChildItem $BriefDir -File | Sort-Object Name) {
  $nameMatch = Select-String -Path $bf.FullName -Pattern '^- name: (.+)$'
  $name = $nameMatch.Matches[0].Groups[1].Value.Trim()
  if ($Only -and $name -notin $Only) { continue }
  $covPath = Join-Path $SkillsRoot "$name\references\coverage.md"
  if (-not (Test-Path $covPath)) { Write-Output "[$name] FAIL missing coverage.md"; $fail++; continue }
  $cov = ((Get-Content $covPath -Raw) -replace '\s+', ' ').ToLowerInvariant()
  $lines = Get-Content $bf.FullName
  $sections = @(); $buf = ''; $inSection = $false
  foreach ($ln in $lines) {
    if ($ln -match '^## Topic \d+') { if ($buf) { $sections += $buf }; $buf = ''; $inSection = $true; continue }
    if ($ln -match '^## ' -and $inSection) { if ($buf) { $sections += $buf }; $buf = ''; $inSection = $false; continue }
    if ($inSection) { $buf += ' ' + $ln }
  }
  if ($buf) { $sections += $buf }
  $allTerms = @()
  foreach ($s in $sections) { $allTerms += ($s -split ';') }
  $allTerms = $allTerms | ForEach-Object { ($_ -replace '\s+', ' ').Trim().TrimEnd('.').Trim().ToLowerInvariant() } | Where-Object { $_ -ne '' }
  $missing = @($allTerms | Where-Object { -not $cov.Contains($_) })
  if ($missing.Count -eq 0) {
    Write-Output ("[{0}] OK terms={1} missing=0" -f $name, $allTerms.Count)
  } else {
    $fail++
    Write-Output ("[{0}] FAIL terms={1} missing={2}" -f $name, $allTerms.Count, $missing.Count)
    $missing | ForEach-Object { Write-Output "  - $_" }
  }
}
Write-Output $(if ($fail -eq 0) { 'RESULT: ALL PASS' } else { "RESULT: $fail skill(s) failing" })
