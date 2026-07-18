# Fable kit self-test - the full installer harness, shipped in the kit (the
# TOTAL line it prints is the assertion count of record). Run under PowerShell 7 (pwsh); requires Node.js for the merge and
# redactor scenarios, Git Bash for the hook behavior pipe-tests (S9), and
# `claude` on PATH (pinned in S0 - keeps the child's winget offers silent).
# Every installer invocation uses powershell.exe (5.1) = what a fresh Windows
# machine has. Installs ONLY into disposable sandbox homes under %TEMP%\fbt
# (short paths - deep fake-home paths trigger MAX_PATH artifacts real user
# homes never hit); the live machine is never touched beyond the installer's
# own %TEMP% residue (its transcript logs and stale extraction dirs, which the
# installer rotates BY DESIGN and S11 exercises) - the harness deletes its own
# run's logs and extraction dirs on success. Do not run a REAL install
# concurrently with the selftest: the t0-scoped success-cleanup would sweep
# that install's fresh log or extraction dir.
#   pwsh -File tools\run-selftest.ps1            # tests the kit it ships in
#   pwsh -File run-selftest.ps1 -Kit <kitRoot>   # tests another kit tree
param([string]$Kit = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
$KIT = $Kit
if (-not (Test-Path (Join-Path $KIT 'claude-home\settings.json')) -or -not (Test-Path (Join-Path $KIT 'install.ps1'))) {
    throw "not a kit root: '$KIT' has no claude-home\settings.json / install.ps1 - pass -Kit <kitRoot> (e.g. the repo's src\ folder)"
}
$FHROOT = Join-Path $env:TEMP 'fbt'
$t0 = Get-Date   # for success-cleanup of this run's own %TEMP% residue
$script:Pass = 0; $script:Fail = 0; $script:Lines = @()

function Assert([string]$name, [bool]$cond, [string]$detail = '') {
    if ($cond) { $script:Pass++; $script:Lines += "  PASS  $name" }
    else { $script:Fail++; $script:Lines += "  FAIL  $name  $detail" }
}
function New-FakeHome([string]$name) {
    $p = Join-Path $FHROOT $name
    if (Test-Path $p) { Remove-Item $p -Recurse -Force }
    New-Item -ItemType Directory -Force $p | Out-Null
    return $p
}
function Get-RawSafe([string]$p) { if (Test-Path $p) { return (Get-Content $p -Raw) } else { return '' } }
function Invoke-Installer([string]$fh, [string]$proj, [string]$kit = $KIT, [string]$pathOverride = '') {
    $out = Join-Path $fh 'run.out'
    $old = $env:Path
    try {
        if ($pathOverride -ne '') { $env:Path = $pathOverride }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kit 'install.ps1') -Unattended -TargetHome $fh -ProjectPath $proj *> $out
        return $LASTEXITCODE
    } finally { $env:Path = $old }
}
function Invoke-InstallerInteractive([string]$fh, [string]$proj, [string]$kit, [string]$answers) {
    # No -Unattended: every Read-Host consumes one line of piped stdin. At stdin
    # EOF Read-Host yields AutomationNull, which a [Y/n] check DECLINES (probed
    # on PS 5.1) - so answer every expected prompt explicitly and pad with 'n'
    # lines so any unexpected prompt (e.g. a winget offer on a machine missing a
    # prereq) declines instead of relying on EOF semantics.
    $out = Join-Path $fh 'run.out'
    $answers | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kit 'install.ps1') -TargetHome $fh -ProjectPath $proj *> $out
    return $LASTEXITCODE
}
function Get-Sha([string]$p) { (Get-FileHash $p -Algorithm SHA256).Hash }

Write-Host "=== S0: slug formula + kit-shape anchors ==="
$slug = ('C:\Users\example\Desktop\Projects\Claude Code' -replace '[^A-Za-z0-9]', '-')
Assert 'S0 slug formula (every non-alphanumeric -> dash)' ($slug -eq 'C--Users-example-Desktop-Projects-Claude-Code') $slug
Assert 'S0 public kit ships NO memory dir (personal data stays out)' (-not (Test-Path (Join-Path $KIT 'memory')))
$kitSet0 = Get-Content (Join-Path $KIT 'claude-home\settings.json') -Raw | ConvertFrom-Json -AsHashtable
$allowed0 = @('hooks', 'autoUpdatesChannel', 'theme', 'skipWorkflowUsageWarning')
$extraKeys0 = @($kitSet0.Keys | Where-Object { $allowed0 -notcontains $_ })
Assert 'S0 settings.json keys all merge-allowlisted (mirrors fable-merge.js + install.ps1 allowlists)' ($extraKeys0.Count -eq 0) ('unlisted: ' + ($extraKeys0 -join ','))
Assert 'S0 harness env: claude on PATH (child prereq offers stay silent in interactive runs)' ($null -ne (Get-Command claude -ErrorAction SilentlyContinue))

Write-Host "=== S1: fresh machine ==="
$fh = New-FakeHome 'fh1'
$proj = Join-Path $fh 'Desktop\Projects\Claude Code'
$ec = Invoke-Installer $fh $proj
$dc = Join-Path $fh '.claude'
Assert 'S1 exit 0' ($ec -eq 0) "exit=$ec"
Assert 'S1 CLAUDE.md hash == kit' ((Test-Path "$dc\CLAUDE.md") -and ((Get-Sha "$dc\CLAUDE.md") -eq (Get-Sha "$KIT\claude-home\CLAUDE.md")))
Assert 'S1 fable-mode skill + gold-standards' ((Test-Path "$dc\skills\fable-mode\SKILL.md") -and (Test-Path "$dc\skills\fable-mode\references\gold-standards.md"))
Assert 'S1 refresh-kit + invest-research + organize skills' ((Test-Path "$dc\skills\refresh-kit\SKILL.md") -and (Test-Path "$dc\skills\invest-research\SKILL.md") -and (Test-Path "$dc\skills\organize\SKILL.md"))
Assert 'S1 scheduled task installed' (Test-Path "$dc\scheduled-tasks\fable-health-check\SKILL.md")
Assert 'S1 settings.json == kit copy' ((Get-Sha "$dc\settings.json") -eq (Get-Sha "$KIT\claude-home\settings.json"))
Assert 'S1 no projects\memory dir created (kit ships none)' (-not (Test-Path (Join-Path $dc 'projects')))
Assert 'S1 memory step reported kit-ships-none' ((Get-RawSafe (Join-Path $fh 'run.out')) -match 'kit ships no')
Assert 'S1 mcp step PASS with the empty public template' ((Get-RawSafe (Join-Path $fh 'run.out')) -match 'mcp servers\s+PASS')
Assert 'S1 output says INSTALL PASSED' ((Get-RawSafe (Join-Path $fh 'run.out')) -match 'INSTALL PASSED')
Assert 'S1 no credentials file involved' (-not (Test-Path "$dc\.credentials.json"))
$mfKit = Get-Content (Join-Path $KIT 'kit-manifest.json') -Raw | ConvertFrom-Json
$ledg1 = Get-Content (Join-Path $dc 'fable-install-ledger.json') -Raw | ConvertFrom-Json
Assert 'S1 install ledger written: version = kit, settings.json unmanaged' (($ledg1.kitVersion -eq $mfKit.kitVersion) -and (@($ledg1.files | Where-Object { $_.path -ieq 'settings.json' }).Count -eq 0))
$lcl = @($ledg1.files | Where-Object { $_.path -ieq 'CLAUDE.md' })
Assert 'S1 ledger CLAUDE.md entry carries the kit hash' (($lcl.Count -eq 1) -and ($lcl[0].sha256 -eq (Get-Sha (Join-Path $KIT 'claude-home\CLAUDE.md'))))

Write-Host "=== S2: existing configs get merged, not clobbered (node path) ==="
$fh = New-FakeHome 'fh2'
$proj = Join-Path $fh 'Desktop\Projects\Claude Code'
New-Item -ItemType Directory -Force (Join-Path $fh '.claude') | Out-Null
@'
{
  "model": "opusplan",
  "env": { "FOO": "bar" },
  "hooks": {
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "echo custom-foreign-hook" } ] } ],
    "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "echo guard" } ] } ]
  }
}
'@ | Set-Content (Join-Path $fh '.claude\settings.json') -Encoding UTF8
@'
{
  "mcpServers": { "existing-server": { "type": "stdio", "command": "C:\\nope\\x.exe" } },
  "someKey": "keep",
  "": { "weird": "empty-string key like the real file has" }
}
'@ | Set-Content (Join-Path $fh '.claude.json') -Encoding UTF8
$slugDir = Join-Path $fh ('.claude\projects\' + ($proj -replace '[^A-Za-z0-9]', '-') + '\memory')
New-Item -ItemType Directory -Force $slugDir | Out-Null
'MY NEWER LOCAL MEMORY - MUST SURVIVE' | Set-Content (Join-Path $slugDir 'project-global-claude-md.md') -Encoding UTF8
$ec = Invoke-Installer $fh $proj
Assert 'S2 exit 0' ($ec -eq 0) "exit=$ec"
$st = Get-Content (Join-Path $fh '.claude\settings.json') -Raw | ConvertFrom-Json -AsHashtable
Assert 'S2 foreign top-level keys survive' (($st.model -eq 'opusplan') -and ($st.env.FOO -eq 'bar'))
Assert 'S2 foreign PreToolUse hook untouched' (($st.hooks.PreToolUse.Count -eq 1) -and ($st.hooks.PreToolUse[0].hooks[0].command -eq 'echo guard'))
Assert 'S2 SessionStart = foreign + fable (2 groups)' ($st.hooks.SessionStart.Count -eq 2)
$allCmds = @(); foreach ($ev in $st.hooks.Keys) { foreach ($g in $st.hooks[$ev]) { foreach ($h in $g.hooks) { $allCmds += $h.command } } }
Assert 'S2 fable standing order present' (@($allCmds | Where-Object { $_ -like "echo 'Standing order*" }).Count -eq 1)
Assert 'S2 classifier + subagent hooks present' ((@($allCmds | Where-Object { $_ -like '*grep -qiE*' }).Count -eq 1) -and (@($allCmds | Where-Object { $_ -like '*SubagentStart*' }).Count -eq 1))
$cj = Get-Content (Join-Path $fh '.claude.json') -Raw | ConvertFrom-Json -AsHashtable
Assert 'S2 existing mcp server intact, empty template adds nothing' (($cj.mcpServers.ContainsKey('existing-server')) -and (@($cj.mcpServers.Keys).Count -eq 1))
Assert 'S2 foreign .claude.json keys survive (incl empty-string key)' (($cj.someKey -eq 'keep') -and ($cj.ContainsKey('')))
Assert 'S2 pre-existing memory KEPT' ((Get-Content (Join-Path $slugDir 'project-global-claude-md.md') -Raw) -match 'MUST SURVIVE')
Assert 'S2 no kit memory added beside it (kit ships none)' (@(Get-ChildItem $slugDir -File).Count -eq 1)
$bk = @(Get-ChildItem (Join-Path $fh '.claude') -Directory | Where-Object Name -like 'fable-install-backup-*')
Assert 'S2 backups created for overwritten files' ($bk.Count -ge 1)

Write-Host "=== S3: idempotent re-run on S2 home ==="
Start-Sleep -Seconds 1
$ec = Invoke-Installer $fh $proj
Assert 'S3 exit 0' ($ec -eq 0) "exit=$ec"
$st = Get-Content (Join-Path $fh '.claude\settings.json') -Raw | ConvertFrom-Json -AsHashtable
Assert 'S3 no duplicate hook groups' ($st.hooks.SessionStart.Count -eq 2)
$out = Get-RawSafe (Join-Path $fh 'run.out')
Assert 'S3 core files all skipped as identical' ($out -match '0 file\(s\) installed')
Assert 'S3 mcp NOCHANGE' ($out -match 'NOCHANGE')

Write-Host "=== S4: tampered kit refused, nothing installed ==="
$tk = Join-Path $FHROOT 'kit-tampered'
if (Test-Path $tk) { Remove-Item $tk -Recurse -Force }
Copy-Item $KIT $tk -Recurse
Add-Content (Join-Path $tk 'claude-home\CLAUDE.md') 'TAMPERED'
$fh = New-FakeHome 'fh4'
$ec = Invoke-Installer $fh (Join-Path $fh 'Desktop\Projects\Claude Code') $tk
Assert 'S4 nonzero exit' ($ec -ne 0) "exit=$ec"
Assert 'S4 integrity named in output' ((Get-RawSafe (Join-Path $fh 'run.out')) -match '(?i)integrity')
Assert 'S4 nothing installed' (-not (Test-Path (Join-Path $fh '.claude')))

Write-Host "=== S5: no Node.js -> PowerShell 5.1 fallback merge ==="
$fh = New-FakeHome 'fh5'
$proj = Join-Path $fh 'Desktop\Projects\Claude Code'
New-Item -ItemType Directory -Force (Join-Path $fh '.claude') | Out-Null
@'
{
  "model": "opusplan",
  "hooks": {
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "echo custom-foreign-hook" } ] } ]
  }
}
'@ | Set-Content (Join-Path $fh '.claude\settings.json') -Encoding UTF8
@'
{ "mcpServers": { "existing-server": { "type": "stdio", "command": "C:\\nope\\x.exe" } }, "someKey": "keep" }
'@ | Set-Content (Join-Path $fh '.claude.json') -Encoding UTF8
$strippedPath = 'C:\Windows\System32;C:\Windows;C:\Windows\System32\WindowsPowerShell\v1.0'
$ec = Invoke-Installer $fh $proj $KIT $strippedPath
Assert 'S5 exit 0' ($ec -eq 0) "exit=$ec"
$st = Get-Content (Join-Path $fh '.claude\settings.json') -Raw | ConvertFrom-Json -AsHashtable
Assert 'S5 events are arrays (5.1 collapse guard)' (($st.hooks.SessionStart -is [array]) -and ($st.hooks.UserPromptSubmit -is [array]) -and ($st.hooks.SubagentStart -is [array]))
Assert 'S5 SessionStart = 2 groups, foreign kept' (($st.hooks.SessionStart.Count -eq 2) -and ($st.model -eq 'opusplan'))
$allCmds = @(); foreach ($ev in $st.hooks.Keys) { foreach ($g in $st.hooks[$ev]) { foreach ($h in $g.hooks) { $allCmds += $h.command } } }
Assert 'S5 all 3 fable commands present exactly once' ((@($allCmds | Where-Object { $_ -like "echo 'Standing order*" }).Count -eq 1) -and (@($allCmds | Where-Object { $_ -like '*grep -qiE*' }).Count -eq 1) -and (@($allCmds | Where-Object { $_ -like '*SubagentStart*' }).Count -eq 1))
$cj = Get-Content (Join-Path $fh '.claude.json') -Raw | ConvertFrom-Json -AsHashtable
Assert 'S5 mcp untouched via PS fallback (empty template)' (($cj.mcpServers.ContainsKey('existing-server')) -and (@($cj.mcpServers.Keys).Count -eq 1))
$out = Get-RawSafe (Join-Path $fh 'run.out')
Assert 'S5 merge path was powershell' ($out -match 'via powershell')
Assert 'S5 settings row PASS in installer self-check' ($out -match 'settings\.json hooks\s+PASS')

Write-Host "=== S5b: real-shape .claude.json (empty-string key) survives the no-node path ==="
# the REAL .claude.json carries a "" key; Windows PowerShell 5.1's ConvertFrom-Json THROWS
# on it, so the no-node fallback must degrade loudly and leave the file byte-untouched
# (r31; the shape was in S2's node-path fixture but the 5.1 path never saw it)
$fh = New-FakeHome 'fh5b'
$proj = Join-Path $fh 'Desktop\Projects\Claude Code'
New-Item -ItemType Directory -Force (Join-Path $fh '.claude') | Out-Null
@'
{ "": "realfile-artifact", "mcpServers": { "existing-server": { "type": "stdio", "command": "C:\\nope\\x.exe" } } }
'@ | Set-Content (Join-Path $fh '.claude.json') -Encoding UTF8
$cj5bPath = Join-Path $fh '.claude.json'
$cj5bBefore = (Get-FileHash -LiteralPath $cj5bPath -Algorithm SHA256).Hash
$ec = Invoke-Installer $fh $proj $KIT $strippedPath
$out = Get-RawSafe (Join-Path $fh 'run.out')
Assert 'S5b exit 0 (degrades, never dies)' ($ec -eq 0) "exit=$ec"
Assert 'S5b 5.1 parse failure surfaces loudly' ($out -match 'PowerShell mcp merge failed')
Assert 'S5b .claude.json byte-preserved' ((Get-FileHash -LiteralPath $cj5bPath -Algorithm SHA256).Hash -eq $cj5bBefore)

Write-Host "=== S6: kit containing an UNLISTED extra file is refused ==="
$xk = Join-Path $FHROOT 'kit-extra'
if (Test-Path $xk) { Remove-Item $xk -Recurse -Force }
Copy-Item $KIT $xk -Recurse
New-Item -ItemType Directory -Force (Join-Path $xk 'claude-home\skills\evil-extra') | Out-Null
'---{}--- # not in manifest' | Set-Content (Join-Path $xk 'claude-home\skills\evil-extra\SKILL.md') -Encoding UTF8
$fh = New-FakeHome 'fh6'
$ec = Invoke-Installer $fh (Join-Path $fh 'Desktop\Projects\Claude Code') $xk
Assert 'S6 nonzero exit on unlisted file' ($ec -ne 0) "exit=$ec"
Assert 'S6 UNLISTED named in output' ((Get-RawSafe (Join-Path $fh 'run.out')) -match 'UNLISTED FILE')
Assert 'S6 nothing installed' (-not (Test-Path (Join-Path $fh '.claude')))

Write-Host "=== S7: secret-redactor unit tests (adversarial shapes) ==="
$fh = New-FakeHome 'fh7'
$fakeApp = Join-Path $env:USERPROFILE 'FakeApp\bin\kp.exe'
$fakeCfg = @{
    mcpServers = @{
        urltoken  = @{ type = 'http'; url = 'https://mcp.example.com/sse?api_key=SECRETQUERYTOKEN1234567890abcdefghij' }
        connstr   = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('--dsn', 'postgres://admin:Sup3rSecretPW@db.example.com/x') }
        flagged   = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('--token', 'FLAGLEAK_plainword', 'plain-data-dir') }
        jwt       = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('eyJhbGciOiJIUzI1NiJ9.eyJMRUFLIjoxfQ.LEAKabcDEF123') }
        shortkey  = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('sk-shortLEAK4567890AB'); env = @{ API_KEY = 'LEAKwhatever123456' } }
        homebased = @{ type = 'stdio'; command = $fakeApp; args = @('C:\Windows\System32\drivers\etc\hosts', 'task-manager-config') }
        # r15 adversarial additions - each leaked from the r14 redactor (execution-proven 2026-07-11)
        inlineflag = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('--api-key=INLINEFLAGSECRET1234') }
        urlpath    = @{ type = 'http'; url = 'https://api.example.com/mcp/sk-live_LEAK4567890abcdefgh/sse' }
        urlfrag    = @{ type = 'http'; url = 'https://x.example.com/sse#token=FRAGSECRETabcdef123456' }
        dockerenv  = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('-e', 'MY_TOKEN=DOCKENVSECRETabc') }
        boundary   = @{ type = 'stdio'; command = ($env:USERPROFILE + 'XX\evil\kp.exe'); args = @('inert') }
        # r15 second-round additions - from the two-lens fresh-eyes review (each leak/breakage execution-proven pre-fix)
        fragq      = @{ type = 'http'; url = 'https://x.example.com/sse#s=FRAGQSECRET1?k=1' }
        hdr        = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('--header', 'Authorization: Bearer HDRLEAKTOKEN1234567890') }
        userinfo   = @{ type = 'http'; url = 'https://USERINFOLEAK123@example.com/x' }
        pathtok    = @{ type = 'http'; url = 'https://api.example.com/mcp/PATHTOKENLEAK0abcdefghijklmnopqr12/sse' }
        stripe     = @{ type = 'http'; url = 'https://api.example.com/v1/sk_live_STRIPELEAK0000000000/sse' }
        hostkeep   = @{ type = 'http'; url = 'https://sk-production9.example.com/mcp' }
        ejoined    = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('-e=MY_TOKEN=EJOINLEAK12345') }
        tok2       = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('MY_TOKEN2=NUMNAMELEAK12345') }
        authmode   = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('--auth-mode=none') }
        nodescript = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('-e', 'let x=1; console.log(x)') }
        # r26 additions - space-separated compound + short credential flags each leaked pre-fix (2026-07-17 review, execution-proven)
        hshort   = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('-H', 'Authorization: Bearer HSHORTLEAK1234567890') }
        ushort   = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('-u', 'admin:USHORTPWLEAK99') }
        authtok  = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('--auth-token', 'AUTHTOKLEAK13') }
        apitok   = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('--api-token', 'APITOKLEAK13') }
        connsec  = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('ConnectionString=DefaultEndpointsProtocol=https;AccountName=x;AccountKey=CONNSECLEAK00abc==') }
        usermeta = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('--user', 'alice-plain') }
        # r26 fresh-eyes review additions (each leak/regression execution-proven)
        connlead = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('--conn=Password=CONNLEADLEAK;Server=db') }
        passph   = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('--passphrase', 'PASSPHLEAK99horse') }
        userpw2  = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('--user', 'root:USERPW2LEAK88') }
        pyunbuf  = @{ type = 'stdio'; command = 'python'; args = @('-u', 'C:\srv\my-mcp-server.py') }
        benignhdr = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('-H', 'Content-Type: application/json') }
        # r31 additions - residual credential classes + the unknown-field walker (security-review
        # findings, each shape execution-proven leaking pre-fix; all values carry LEAK markers)
        gitlab     = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('--serve', 'glpat-GLPATLEAK1234567890') }
        hugface    = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('hf_HFLEAK1234567890abcd') }
        dotoken    = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('dop_v1_LEAK00000000abcdef') }
        npmtok     = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('npm_NPMLEAK1234567890') }
        ya29arg    = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('ya29.YA29LEAK-1234567890') }
        aizaurl    = @{ type = 'http'; url = 'https://api.example.com/v1/AIzaAIZALEAK123456789/run' }
        pgpass     = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('-pPGLEAKPASSW0RD') }
        pgport     = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('-p5432') }
        unwalked   = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; apiKey = 'AIzaUNWALKLEAK1234567890' }
        nestedauth = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; auth = @{ token = 'ya29.NESTLEAK1234567890' } }
        # r32 review isolation fixtures: values here are NOT independently secret-shaped
        # (no known prefix, under 32 chars), so only the KEY-NAME branch can redact them -
        # the r31 fixtures were prefix-shaped and left that branch untested (review finding)
        cameliso   = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; authToken = 'LEAKCAMELPLAIN99x' }
        plurarr    = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; apiKeys = @('LEAKPLURALARR99x') }
        numcred    = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; token = 43214321 }
        authmode2  = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; auth = @{ mode = 'oauth-device-flow' } }
        portmap    = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('-p9090:90') }
        longflagp  = @{ type = 'stdio'; command = 'C:\Windows\notepad.exe'; args = @('-parallel=4') }
    }
}
$fakeJson = Join-Path $fh 'fake-claude.json'
ConvertTo-Json -InputObject $fakeCfg -Depth 8 | Set-Content $fakeJson -Encoding UTF8
$tplOut = Join-Path $fh 'tpl-out.json'
& node (Join-Path $KIT 'tools\export-mcp-template.js') $fakeJson $tplOut | Out-Null
$tpl = Get-RawSafe $tplOut
Assert 'S7 url query token redacted' (($tpl -notmatch 'SECRETQUERYTOKEN') -and ($tpl -match 'sse\?<<SET-ME>>'))
Assert 'S7 connection-string password redacted' ($tpl -notmatch 'Sup3rSecretPW')
Assert 'S7 flag-passed token redacted' ($tpl -notmatch 'FLAGLEAK_plainword')
Assert 'S7 JWT redacted' ($tpl -notmatch 'eyJhbGciOiJIUzI1NiJ9')
Assert 'S7 short sk- key redacted' ($tpl -notmatch 'sk-shortLEAK4567890AB')
Assert 'S7 env value redacted' ($tpl -notmatch 'LEAKwhatever123456')
Assert 'S7 innocent path + task-manager-config preserved' (($tpl -match 'notepad\.exe') -and ($tpl -match 'task-manager-config') -and ($tpl -match 'plain-data-dir'))
Assert 'S7 home tokenized to <<HOME>>' ($tpl -match '<<HOME>>')
Assert 'S7 inline --flag=value redacted' (($tpl -notmatch 'INLINEFLAGSECRET') -and ($tpl -match '--api-key=<<SET-ME>>'))
Assert 'S7 url path key-prefix redacted' (($tpl -notmatch 'sk-live_LEAK4567890abcdefgh') -and ($tpl -match 'mcp/<<SET-ME>>/sse'))
Assert 'S7 url fragment redacted' (($tpl -notmatch 'FRAGSECRET') -and ($tpl -match 'sse#<<SET-ME>>'))
Assert 'S7 -e NAME=VALUE env arg redacted' (($tpl -notmatch 'DOCKENVSECRET') -and ($tpl -match 'MY_TOKEN=<<SET-ME>>'))
Assert 'S7 home-prefix sibling path not tokenized (boundary)' ($tpl -notmatch '<<HOME>>XX')
Assert 'S7 fragment containing ? redacted' ($tpl -notmatch 'FRAGQSECRET')
Assert 'S7 --header bearer value redacted' ($tpl -notmatch 'HDRLEAKTOKEN')
Assert 'S7 url userinfo token-as-username redacted' ($tpl -notmatch 'USERINFOLEAK')
Assert 'S7 opaque url path token redacted' ($tpl -notmatch 'PATHTOKENLEAK')
Assert 'S7 underscore key variant redacted' ($tpl -notmatch 'STRIPELEAK')
Assert 'S7 key-like hostname preserved (no authority rewrite)' ($tpl -match 'sk-production9.example.com/mcp')
Assert 'S7 joined -e=NAME=VALUE redacted' (($tpl -notmatch 'EJOINLEAK') -and ($tpl -match '-e=MY_TOKEN=<<SET-ME>>'))
Assert 'S7 digit-suffixed cred name redacted' (($tpl -notmatch 'NUMNAMELEAK') -and ($tpl -match 'MY_TOKEN2=<<SET-ME>>'))
Assert 'S7 --auth-mode value preserved (scheme, not secret)' ($tpl -match '--auth-mode=none')
Assert 'S7 node -e inline script preserved' ($tpl -match 'console\.log')
Assert 'S7 -H bearer value redacted (short flag)' ($tpl -notmatch 'HSHORTLEAK')
Assert 'S7 -u user:pass redacted (short flag)' ($tpl -notmatch 'USHORTPWLEAK')
Assert 'S7 --auth-token compound flag redacted' ($tpl -notmatch 'AUTHTOKLEAK')
Assert 'S7 --api-token compound flag redacted' ($tpl -notmatch 'APITOKLEAK')
Assert 'S7 connection-string AccountKey redacted' ($tpl -notmatch 'CONNSECLEAK')
Assert 'S7 --user plain value preserved (not a credential flag)' ($tpl -match 'alice-plain')
Assert 'S7 leading-key connection string redacted' ($tpl -notmatch 'CONNLEADLEAK')
Assert 'S7 --passphrase value redacted' ($tpl -notmatch 'PASSPHLEAK')
Assert 'S7 --user user:pass redacted (curl long form)' ($tpl -notmatch 'USERPW2LEAK')
Assert 'S7 python -u <path> preserved (not curl userinfo)' ($tpl -match 'my-mcp-server\.py')
Assert 'S7 benign -H Content-Type preserved (not an auth header)' ($tpl -match 'application/json')
Assert 'S7 gitlab glpat- redacted (r31)' ($tpl -notmatch 'GLPATLEAK')
Assert 'S7 huggingface hf_ redacted (r31)' ($tpl -notmatch 'HFLEAK')
Assert 'S7 digitalocean dop_v1_ redacted (r31)' ($tpl -notmatch 'LEAK00000000')
Assert 'S7 npm token redacted (r31)' ($tpl -notmatch 'NPMLEAK')
Assert 'S7 ya29 whole-arg redacted (r31)' ($tpl -notmatch 'YA29LEAK')
Assert 'S7 AIza URL-path redacted (r31)' ($tpl -notmatch 'AIZALEAK')
Assert 'S7 attached -p password redacted (r31)' ($tpl -notmatch 'PGLEAKPASSW0RD')
Assert 'S7 attached -p port preserved (r31)' ($tpl -match '-p5432')
Assert 'S7 unknown field (apiKey) redacted by walker (r31)' ($tpl -notmatch 'UNWALKLEAK')
Assert 'S7 nested auth.token redacted by walker (r31)' ($tpl -notmatch 'NESTLEAK')
Assert 'S7 camelCase cred key redacted by key-branch alone (r32)' ($tpl -notmatch 'LEAKCAMELPLAIN')
Assert 'S7 plural cred-key array leaves redacted (r32)' ($tpl -notmatch 'LEAKPLURALARR')
Assert 'S7 numeric leaf under cred key redacted (r32)' ($tpl -notmatch '43214321')
Assert 'S7 auth.mode survives under cred parent (r32)' ($tpl -match 'oauth-device-flow')
Assert 'S7 docker port map survives the -p rule (r32)' ($tpl -match '-p9090:90')
Assert 'S7 single-dash long flag survives the -p rule (r32)' ($tpl -match '-parallel=4')

Write-Host "=== S8: superseded fable hook variants replaced, not accumulated (node path) ==="
$fh = New-FakeHome 'fh8'
$proj = Join-Path $fh 'Desktop\Projects\Claude Code'
New-Item -ItemType Directory -Force (Join-Path $fh '.claude') | Out-Null
@'
{
  "hooks": {
    "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "echo 'Prompt classifier (user hook): STALE v3 variant -> invoke the fable-mode skill at Scope'" }, { "type": "command", "command": "grep -c 'Prompt classifier (user hook)' /dev/null" } ] } ],
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "echo keep-me-foreign" } ] } ]
  }
}
'@ | Set-Content (Join-Path $fh '.claude\settings.json') -Encoding UTF8
$ec = Invoke-Installer $fh $proj
Assert 'S8 exit 0' ($ec -eq 0) "exit=$ec"
$st = Get-Content (Join-Path $fh '.claude\settings.json') -Raw | ConvertFrom-Json -AsHashtable
$allCmds = @(); foreach ($ev in $st.hooks.Keys) { foreach ($g in $st.hooks[$ev]) { foreach ($h in $g.hooks) { $allCmds += $h.command } } }
$kitSetRaw = Get-Content (Join-Path $KIT 'claude-home\settings.json') -Raw | ConvertFrom-Json -AsHashtable
$kitClassifierCmd = $kitSetRaw.hooks.UserPromptSubmit[0].hooks[0].command
Assert 'S8 exactly one FABLE classifier, equal to kit' ((@($allCmds | Where-Object { ($_ -like '*Prompt classifier (user hook)*') -and ($_ -like '*invoke the fable-mode skill*') }).Count -eq 1) -and ($allCmds -contains $kitClassifierCmd))
Assert 'S8 stale variant gone' (@($allCmds | Where-Object { $_ -like '*STALE v3 variant*' }).Count -eq 0)
Assert 'S8 foreign hook intact' (@($allCmds | Where-Object { $_ -eq 'echo keep-me-foreign' }).Count -eq 1)
Assert 'S8 foreign marker-mentioning hook survives (signature gate)' (@($allCmds | Where-Object { $_ -eq "grep -c 'Prompt classifier (user hook)' /dev/null" }).Count -eq 1)

Write-Host "=== S8-PS: same replacement via PowerShell 5.1 fallback (no node) ==="
$fh = New-FakeHome 'fh8b'
$proj = Join-Path $fh 'Desktop\Projects\Claude Code'
New-Item -ItemType Directory -Force (Join-Path $fh '.claude') | Out-Null
@'
{
  "hooks": {
    "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "echo 'Prompt classifier (user hook): STALE v3 variant -> invoke the fable-mode skill at Scope'" }, { "type": "command", "command": "grep -c 'Prompt classifier (user hook)' /dev/null" } ] } ]
  }
}
'@ | Set-Content (Join-Path $fh '.claude\settings.json') -Encoding UTF8
$strippedPath8 = 'C:\Windows\System32;C:\Windows;C:\Windows\System32\WindowsPowerShell\v1.0'
$ec = Invoke-Installer $fh $proj $KIT $strippedPath8
Assert 'S8-PS exit 0' ($ec -eq 0) "exit=$ec"
$st = Get-Content (Join-Path $fh '.claude\settings.json') -Raw | ConvertFrom-Json -AsHashtable
$allCmds = @(); foreach ($ev in $st.hooks.Keys) { foreach ($g in $st.hooks[$ev]) { foreach ($h in $g.hooks) { $allCmds += $h.command } } }
Assert 'S8-PS exactly one FABLE classifier, equal to kit' (@($allCmds | Where-Object { $_ -eq $kitClassifierCmd }).Count -eq 1)
Assert 'S8-PS foreign marker-mentioning hook survives (signature gate)' (@($allCmds | Where-Object { $_ -eq "grep -c 'Prompt classifier (user hook)' /dev/null" }).Count -eq 1)
Assert 'S8-PS stale variant gone' (@($allCmds | Where-Object { $_ -like '*STALE v3 variant*' }).Count -eq 0)

Write-Host "=== S9: kit hook commands behave (pipe-tests via Git Bash) ==="
$bashExe = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path $bashExe)) { $bashExe = (Get-Command bash -ErrorAction SilentlyContinue).Source }
$upsubCmd = $kitSetRaw.hooks.UserPromptSubmit[0].hooks[0].command
$hookSh = Join-Path $FHROOT 'hookcmd.sh'; Set-Content $hookSh $upsubCmd -Encoding UTF8 -NoNewline
function PipeTest([string]$json) { return (($json | & $bashExe $hookSh 2>$null) -join "`n") }
Assert 'S9 refactor fires' ((PipeTest '{"prompt":"refactor the auth module"}') -match 'Prompt classifier')
Assert 'S9 deep-dive fires (v5 stems)' ((PipeTest '{"prompt":"deep dive on ASTS"}') -match 'Prompt classifier')
Assert 'S9 tournament fires (v6 stems)' ((PipeTest '{"prompt":"run a tournament to pick the design"}') -match 'Prompt classifier')
Assert 'S9 improve fires (v7 stems)' ((PipeTest '{"prompt":"improve the error handling in parser.js"}') -match 'Prompt classifier')
Assert 'S9 tls/cert fires (v8 stems)' ((PipeTest '{"prompt":"disable tls certificate verification for the client"}') -match 'Prompt classifier')
Assert 'S9 reset --hard fires (v8 stems)' ((PipeTest '{"prompt":"git reset --hard origin/main"}') -match 'Prompt classifier')
Assert 'S9 sql injection fires (v8 stems)' ((PipeTest '{"prompt":"fix the sql injection in the login form"}') -match 'Prompt classifier')
Assert 'S9 chmod/restore fires (v8 stems)' ((PipeTest '{"prompt":"chmod 777 then restore the prod backup"}') -match 'Prompt classifier')
Assert 'S9 clinical dose fires (v9 stems)' ((PipeTest '{"prompt":"whats the max dose of amoxicillin for a 6 year old"}') -match 'Prompt classifier')
Assert 'S9 typo silent' ((PipeTest '{"prompt":"fix typo in readme"}') -eq '')
Assert 'S9 empty-prompt silent (sentinel)' ((PipeTest '{"cwd":"C:/repos/auth-service","prompt":""}') -eq '')
Assert 'S9 malformed-json silent' ((PipeTest 'not-json{{') -eq '')
$hookShPosix = ($hookSh -replace '^([A-Za-z]):', '/$1' -replace '\\', '/')
$degOut = (('{"cwd":"C:/repos/auth-service","prompt":"hi"}' | & $bashExe -c "export PATH=/usr/bin:/bin; bash '$hookShPosix'" 2>$null) -join "`n")
Assert 'S9 node-absent prints DEGRADED notice' ($degOut -match 'DEGRADED')
$subCmd = $kitSetRaw.hooks.SubagentStart[0].hooks[0].command
$subSh = Join-Path $FHROOT 'subcmd.sh'; Set-Content $subSh $subCmd -Encoding UTF8 -NoNewline
$subOut = (('{}' | & $bashExe $subSh 2>$null) -join "`n")
$subOk = $false; try { $o9 = $subOut | ConvertFrom-Json; $subOk = ($o9.hookSpecificOutput.hookEventName -eq 'SubagentStart') } catch {}
Assert 'S9 SubagentStart stdout strict-parses with correct event' $subOk
Assert 'S9 SubagentStart additionalContext carries the INTENT artifact' ($subOk -and ($o9.hookSpecificOutput.additionalContext -match 'INTENT: code does X'))

Write-Host "=== S10: gate self-service - install from the kit's own zip ==="
# a "source tree": full kit copy + the kit's own zip + non-kit extras beside it
$szip = Join-Path $FHROOT 'fable-restore-kit-2099-01-01-r99.zip'
if (Test-Path $szip) { Remove-Item $szip -Force }
Compress-Archive -Path (Join-Path $KIT '*') -DestinationPath $szip
$srcTree = Join-Path $FHROOT 'kit-srctree'
if (Test-Path $srcTree) { Remove-Item $srcTree -Recurse -Force }
Copy-Item $KIT $srcTree -Recurse
Copy-Item $szip (Join-Path $srcTree 'fable-restore-kit-2099-01-01-r99.zip')
'* text=auto' | Set-Content (Join-Path $srcTree '.gitattributes') -Encoding UTF8
'# sibling readme - not kit content' | Set-Content (Join-Path $srcTree 'fable-restore-kit-README.md') -Encoding UTF8

$fh = New-FakeHome 'fh10a'
$ec = Invoke-Installer $fh (Join-Path $fh 'Desktop\Projects\Claude Code') $srcTree
$out = Get-RawSafe (Join-Path $fh 'run.out')
Assert 'S10 unattended source-tree: nonzero exit' ($ec -ne 0) "exit=$ec"
Assert 'S10 unattended: UNLISTED named' ($out -match 'UNLISTED FILE')
Assert 'S10 unattended: manual Expand-Archive route printed' ($out -match 'Expand-Archive "')
Assert 'S10 unattended: nothing installed' (-not (Test-Path (Join-Path $fh '.claude')))

$fh = New-FakeHome 'fh10b'
$ec = Invoke-InstallerInteractive $fh (Join-Path $fh 'Desktop\Projects\Claude Code') $srcTree "y`ny`ny`nn`nn`nn"
$out = Get-RawSafe (Join-Path $fh 'run.out')
Assert 'S10 interactive-Y: exit 0 via relaunched child' ($ec -eq 0) "exit=$ec"
Assert 'S10 interactive-Y: child kit root is the temp extraction' ($out -match 'Kit root : .*fable-kit')
Assert 'S10 interactive-Y: installed, CLAUDE.md hash == kit' ((Test-Path (Join-Path $fh '.claude\CLAUDE.md')) -and ((Get-Sha (Join-Path $fh '.claude\CLAUDE.md')) -eq (Get-Sha (Join-Path $KIT 'claude-home\CLAUDE.md'))))
Assert 'S10 interactive-Y: continued from the extracted kit' ($out -match 'continuing from the extracted kit')
Assert 'S10 interactive-Y: INSTALL PASSED' ($out -match 'INSTALL PASSED')

$fh = New-FakeHome 'fh10c'
$ec = Invoke-InstallerInteractive $fh (Join-Path $fh 'Desktop\Projects\Claude Code') $srcTree "y`nn`nn`nn`nn"
Assert 'S10 interactive-N: exit 2' ($ec -eq 2) "exit=$ec"
Assert 'S10 interactive-N: aborted-by-user message' ((Get-RawSafe (Join-Path $fh 'run.out')) -match 'Aborted by user')
Assert 'S10 interactive-N: nothing installed' (-not (Test-Path (Join-Path $fh '.claude')))

# the r14 missing-manifest offer, previously untested by the harness
$srcTree2 = Join-Path $FHROOT 'kit-nomanifest'
if (Test-Path $srcTree2) { Remove-Item $srcTree2 -Recurse -Force }
Copy-Item $KIT $srcTree2 -Recurse
Remove-Item (Join-Path $srcTree2 'kit-manifest.json')
Copy-Item $szip (Join-Path $srcTree2 'fable-restore-kit-2099-01-01-r99.zip')
$fh = New-FakeHome 'fh10d'
$ec = Invoke-InstallerInteractive $fh (Join-Path $fh 'Desktop\Projects\Claude Code') $srcTree2 "y`ny`ny`nn`nn`nn"
Assert 'S10 missing-manifest interactive-Y: exit 0 via relaunch' ($ec -eq 0) "exit=$ec"
Assert 'S10 missing-manifest: installed' (Test-Path (Join-Path $fh '.claude\CLAUDE.md'))

# nonzero child verdict must propagate (INSTALL.bat maps 0/2/other)
$fh = New-FakeHome 'fh10e'
$ec = Invoke-InstallerInteractive $fh (Join-Path $fh 'Desktop\Projects\Claude Code') $srcTree "y`ny`nn`nn`nn`nn"
Assert 'S10 child-decline: exit 2 propagated through relaunch' ($ec -eq 2) "exit=$ec"
Assert 'S10 child-decline: nothing installed' (-not (Test-Path (Join-Path $fh '.claude')))
try { Remove-Item (Join-Path $env:TEMP 'fable-kit') -Recurse -Force } catch { }

Write-Host "=== S11: comprehensive cleanup - logs, launch-folder debris, backups, strays ==="
# S11a: installer startup rotation caps its own %TEMP% transcript logs at 10
$seeded = @()
for ($i = 1; $i -le 15; $i++) {
    $fp = Join-Path $env:TEMP ('fable-install-19990101-{0:D6}-000.log' -f $i)
    'seed' | Set-Content $fp -Encoding UTF8
    (Get-Item $fp).LastWriteTime = (Get-Date).AddDays(-365 - $i)
    $seeded += $fp
}
$fh = New-FakeHome 'fh11a'
$ec = Invoke-Installer $fh (Join-Path $fh 'Desktop\Projects\Claude Code')
$logCount = @(Get-ChildItem $env:TEMP -Filter 'fable-install-*.log' -File).Count
Assert 'S11 log rotation caps %TEMP% install logs at 10 (current run kept)' (($ec -eq 0) -and ($logCount -ge 1) -and ($logCount -le 10)) "exit=$ec count=$logCount"
Assert 'S11 rotation removed the oldest seeded logs' (-not (Test-Path $seeded[14]))
foreach ($sp in $seeded) { if (Test-Path $sp) { Remove-Item $sp -Force } }

# S11b: post-success launch-folder debris cleanup - only byte-verified duplicates go
$srcTree3 = Join-Path $FHROOT 'kit-srctree3'
if (Test-Path $srcTree3) { Remove-Item $srcTree3 -Recurse -Force }
Copy-Item $KIT $srcTree3 -Recurse
Copy-Item $szip (Join-Path $srcTree3 'fable-restore-kit-2099-01-01-r99.zip')
'* text=auto' | Set-Content (Join-Path $srcTree3 '.gitattributes') -Encoding UTF8
'# sibling readme - not kit content' | Set-Content (Join-Path $srcTree3 'fable-restore-kit-README.md') -Encoding UTF8
# EOF at the destructive debris prompt must keep everything (fail-safe pin)
$fh = New-FakeHome 'fh11b0'
$ec = Invoke-InstallerInteractive $fh (Join-Path $fh 'Desktop\Projects\Claude Code') $srcTree3 "y`ny`ny"
Assert 'S11 debris EOF: launch files kept (destructive prompt fails safe)' (($ec -eq 0) -and (Test-Path (Join-Path $srcTree3 'claude-home\CLAUDE.md'))) "exit=$ec"
Assert 'S11 debris EOF: kept-message printed' ((Get-RawSafe (Join-Path $fh 'run.out')) -match 'kept - delete manually later')

$fh = New-FakeHome 'fh11b'
$ec = Invoke-InstallerInteractive $fh (Join-Path $fh 'Desktop\Projects\Claude Code') $srcTree3 "y`ny`ny`ny`nn`nn"
Assert 'S11 debris: exit 0' ($ec -eq 0) "exit=$ec"
Assert 'S11 debris: duplicate kit files removed from launch folder' ((-not (Test-Path (Join-Path $srcTree3 'claude-home'))) -and (-not (Test-Path (Join-Path $srcTree3 'kit-manifest.json'))) -and (-not (Test-Path (Join-Path $srcTree3 'install.ps1'))))
$left = @(Get-ChildItem $srcTree3 -Recurse -File)
Assert 'S11 debris: zip + non-kit files kept (exactly 3 remain)' ($left.Count -eq 3) "left=$($left.Count): $(($left | ForEach-Object Name) -join ',')"
Assert 'S11 debris: install landed' (Test-Path (Join-Path $fh '.claude\CLAUDE.md'))

# S11c: backup housekeeping - report always; prune keeps the newest 3
$fh = New-FakeHome 'fh11c'
$dc11 = Join-Path $fh '.claude'
New-Item -ItemType Directory -Force $dc11 | Out-Null
for ($i = 1; $i -le 5; $i++) {
    $bd = Join-Path $dc11 ('fable-install-backup-2025010{0}-000000-00{0}' -f $i)
    New-Item -ItemType Directory -Force $bd | Out-Null
    'old' | Set-Content (Join-Path $bd 'settings.json.bak') -Encoding UTF8
    (Get-Item $bd).CreationTime = (Get-Date).AddDays(-90 - $i)
}
# EOF at the prune prompt must keep everything (fail-safe pin)
$ec = Invoke-InstallerInteractive $fh (Join-Path $fh 'Desktop\Projects\Claude Code') $KIT "y"
$bakLeft = @(Get-ChildItem $dc11 -Filter 'fable-install-backup-*' -Directory).Count
Assert 'S11 backups EOF: nothing pruned (5 remain), exit 0' (($ec -eq 0) -and ($bakLeft -eq 5)) "exit=$ec left=$bakLeft"
Assert 'S11 backups: report line printed' ((Get-RawSafe (Join-Path $fh 'run.out')) -match 'install-backup folder')
$ec = Invoke-InstallerInteractive $fh (Join-Path $fh 'Desktop\Projects\Claude Code') $KIT "y`ny`nn`nn"
$bakNames = @(Get-ChildItem $dc11 -Filter 'fable-install-backup-*' -Directory | ForEach-Object Name | Sort-Object)
# the re-run itself adds one fresh backup (.claude.json is backed up before every
# merge once it exists), so CreationTime-newest-3 = {fresh, seed-01, seed-02}:
# direction is pinned by 01+02 surviving while 03-05 (older) are pruned
Assert 'S11 backups: prune keeps the 3 CreationTime-newest, exit 0' (($ec -eq 0) -and ($bakNames.Count -eq 3) -and ($bakNames -contains 'fable-install-backup-20250101-000000-001') -and ($bakNames -contains 'fable-install-backup-20250102-000000-002') -and (-not ($bakNames -contains 'fable-install-backup-20250103-000000-003'))) "exit=$ec left=$($bakNames -join ',')"

# S11d: stray file inside a kit-owned skill folder is reported and KEPT
$fh = New-FakeHome 'fh11d'
$ec = Invoke-Installer $fh (Join-Path $fh 'Desktop\Projects\Claude Code')
'stray local note' | Set-Content (Join-Path $fh '.claude\skills\fable-mode\NOTES-local.md') -Encoding UTF8
$ec = Invoke-Installer $fh (Join-Path $fh 'Desktop\Projects\Claude Code')
$out11 = Get-RawSafe (Join-Path $fh 'run.out')
Assert 'S11 stray skill file reported exactly once and kept' ((([regex]::Matches($out11, 'not part of this kit \(kept\)')).Count -eq 1) -and (Test-Path (Join-Path $fh '.claude\skills\fable-mode\NOTES-local.md')))
Assert 'S11 stray: re-run still exit 0' ($ec -eq 0) "exit=$ec"

Write-Host "=== S12: FableSetup.exe - build + unattended install from the exe ==="
$csc12 = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc12)) { $csc12 = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
Assert 'S12 csc.exe present (.NET Framework ships with Windows)' (Test-Path $csc12) $csc12
$exe12 = Join-Path $FHROOT 'FableSetup-test.exe'
& pwsh -NoProfile -File (Join-Path $KIT 'tools\build-exe.ps1') -SrcRoot $KIT -OutFile $exe12 *> (Join-Path $FHROOT 'build.out')
Assert 'S12 build-exe.ps1 exit 0 and exe exists' (($LASTEXITCODE -eq 0) -and (Test-Path $exe12)) "exit=$LASTEXITCODE"
$fh = New-FakeHome 'fh12'
& $exe12 -Unattended -TargetHome $fh -ProjectPath (Join-Path $fh 'Desktop\Projects\Claude Code') *> (Join-Path $fh 'run.out')
$ec = $LASTEXITCODE
Assert 'S12 exe unattended install exit 0' ($ec -eq 0) "exit=$ec"
Assert 'S12 CLAUDE.md landed, hash == kit' ((Test-Path (Join-Path $fh '.claude\CLAUDE.md')) -and ((Get-Sha (Join-Path $fh '.claude\CLAUDE.md')) -eq (Get-Sha (Join-Path $KIT 'claude-home\CLAUDE.md'))))
Assert 'S12 INSTALL PASSED via exe' ((Get-RawSafe (Join-Path $fh 'run.out')) -match 'INSTALL PASSED')
Assert 'S12 exe staging dir cleaned from %TEMP%' (@(Get-ChildItem $env:TEMP -Filter 'fable-setup-*' -Directory -ErrorAction SilentlyContinue | Where-Object { $_.CreationTime -ge $t0 }).Count -eq 0)
Assert 'S12 exe install wrote the ledger' (Test-Path (Join-Path $fh '.claude\fable-install-ledger.json'))

Write-Host "=== S13: MCP merge machinery (fixture template; the public kit ships an empty one) ==="
$mk = Join-Path $FHROOT 'kit-mcpfix'
if (Test-Path $mk) { Remove-Item $mk -Recurse -Force }
Copy-Item $KIT $mk -Recurse
@'
{
  "_comment": "selftest fixture",
  "mcpServers": {
    "fixture-server": { "type": "stdio", "command": "<<HOME>>\\FakeApp\\bin\\fx.exe", "args": ["run"] }
  }
}
'@ | Set-Content (Join-Path $mk 'mcp-servers.template.json') -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $mk 'tools\make-manifest.ps1') -KitRoot $mk -KitVersion rTEST | Out-Null
$fh = New-FakeHome 'fh13'
@'
{ "mcpServers": { "existing-server": { "type": "stdio", "command": "C:\\nope\\x.exe" } }, "someKey": "keep" }
'@ | Set-Content (Join-Path $fh '.claude.json') -Encoding UTF8
$ec = Invoke-Installer $fh (Join-Path $fh 'Desktop\Projects\Claude Code') $mk
Assert 'S13 exit 0' ($ec -eq 0) "exit=$ec"
$cj = Get-Content (Join-Path $fh '.claude.json') -Raw | ConvertFrom-Json -AsHashtable
Assert 'S13 fixture server added, existing + foreign keys kept' (($cj.mcpServers.ContainsKey('fixture-server')) -and ($cj.mcpServers.ContainsKey('existing-server')) -and ($cj.someKey -eq 'keep'))
Assert 'S13 <<HOME>> rebased onto target home, no token left' (($cj.mcpServers.'fixture-server'.command -like "$fh*") -and ((Get-RawSafe (Join-Path $fh '.claude.json')) -notmatch '<<HOME>>'))
$fh = New-FakeHome 'fh13b'
$strippedPath13 = 'C:\Windows\System32;C:\Windows;C:\Windows\System32\WindowsPowerShell\v1.0'
$ec = Invoke-Installer $fh (Join-Path $fh 'Desktop\Projects\Claude Code') $mk $strippedPath13
$cj = Get-Content (Join-Path $fh '.claude.json') -Raw | ConvertFrom-Json -AsHashtable
Assert 'S13 PS-fallback (no node): fixture server added + rebased' (($ec -eq 0) -and ($cj.mcpServers.ContainsKey('fixture-server')) -and ($cj.mcpServers.'fixture-server'.command -like "$fh*"))

Write-Host "=== S14: memory machinery on a fixture kit (the public kit ships none) ==="
$mm = Join-Path $FHROOT 'kit-memfix'
if (Test-Path $mm) { Remove-Item $mm -Recurse -Force }
Copy-Item $KIT $mm -Recurse
New-Item -ItemType Directory -Force (Join-Path $mm 'memory') | Out-Null
'fixture memory A' | Set-Content (Join-Path $mm 'memory\alpha.md') -Encoding UTF8
'fixture memory B' | Set-Content (Join-Path $mm 'memory\beta-longer-name.md') -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $mm 'tools\make-manifest.ps1') -KitRoot $mm -KitVersion rTEST | Out-Null
$fh = New-FakeHome 'fh14'
$proj = Join-Path $fh 'Desktop\Projects\Claude Code'
$ec = Invoke-Installer $fh $proj $mm
$slugDir = Join-Path $fh ('.claude\projects\' + ($proj -replace '[^A-Za-z0-9]', '-') + '\memory')
Assert 'S14 fixture memory installed at computed slug' (($ec -eq 0) -and (Test-Path (Join-Path $slugDir 'alpha.md')) -and (@(Get-ChildItem $slugDir -File).Count -eq 2)) "exit=$ec"
'MY EDIT MUST SURVIVE' | Set-Content (Join-Path $slugDir 'alpha.md') -Encoding UTF8
$ec = Invoke-Installer $fh $proj $mm
Assert 'S14 gap-fill: existing memory kept on re-run' (($ec -eq 0) -and ((Get-Content (Join-Path $slugDir 'alpha.md') -Raw) -match 'MUST SURVIVE')) "exit=$ec"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $mm 'install.ps1') -Unattended -TargetHome $fh -ProjectPath $proj -ForceMemory *> (Join-Path $fh 'run.out')
Assert 'S14 -ForceMemory overwrites back to kit content' (($LASTEXITCODE -eq 0) -and ((Get-Content (Join-Path $slugDir 'alpha.md') -Raw) -match 'fixture memory A')) "exit=$LASTEXITCODE"

Write-Host "=== S15: upgrade hygiene - install ledger cleans previous-version files ==="
# rOLD fixture: the real kit plus one extra MANAGED file - models an older kit
# that shipped a reference file the current kit no longer does
$okit = Join-Path $FHROOT 'kit-older'
if (Test-Path $okit) { Remove-Item $okit -Recurse -Force }
Copy-Item $KIT $okit -Recurse
'superseded reference shipped by rOLD only' | Set-Content (Join-Path $okit 'claude-home\skills\fable-mode\references\superseded-note.md') -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $okit 'tools\make-manifest.ps1') -KitRoot $okit -KitVersion rOLD | Out-Null
$fh = New-FakeHome 'fh15'
$proj = Join-Path $fh 'Desktop\Projects\Claude Code'
$ec = Invoke-Installer $fh $proj $okit
$staleDest = Join-Path $fh '.claude\skills\fable-mode\references\superseded-note.md'
$ledgPath = Join-Path $fh '.claude\fable-install-ledger.json'
$ledgOld = Get-Content $ledgPath -Raw | ConvertFrom-Json
Assert 'S15 rOLD install: exit 0, extra file installed and ledgered' (($ec -eq 0) -and (Test-Path $staleDest) -and (@($ledgOld.files | Where-Object { $_.path -ieq 'skills\fable-mode\references\superseded-note.md' }).Count -eq 1)) "exit=$ec"
$ec = Invoke-Installer $fh $proj $KIT
$out15 = Get-RawSafe (Join-Path $fh 'run.out')
$ledgNew = Get-Content $ledgPath -Raw | ConvertFrom-Json
Assert 'S15 upgrade to current kit: exit 0' ($ec -eq 0) "exit=$ec"
Assert 'S15 stale rOLD file removed on upgrade' (-not (Test-Path $staleDest))
Assert 'S15 removal named in output' ($out15 -match 'stale kit file removed \(backed up\): skills\\fable-mode\\references\\superseded-note\.md')
$bkd = @(Get-ChildItem (Join-Path $fh '.claude') -Directory | Where-Object Name -like 'fable-install-backup-*' | ForEach-Object { Join-Path $_.FullName '.claude\skills\fable-mode\references\superseded-note.md' } | Where-Object { Test-Path $_ })
Assert 'S15 removed file backed up first' ($bkd.Count -ge 1)
Assert 'S15 new ledger: rOLD entry gone, version = current kit' ((@($ledgNew.files | Where-Object { $_.path -ieq 'skills\fable-mode\references\superseded-note.md' }).Count -eq 0) -and ($ledgNew.kitVersion -eq $mfKit.kitVersion))
# user-modified variant: edits win over cleanup
$fh = New-FakeHome 'fh15b'
$proj = Join-Path $fh 'Desktop\Projects\Claude Code'
$ec = Invoke-Installer $fh $proj $okit
'USER EDIT - MUST SURVIVE UPGRADES' | Set-Content (Join-Path $fh '.claude\skills\fable-mode\references\superseded-note.md') -Encoding UTF8
$ec = Invoke-Installer $fh $proj $KIT
$out15b = Get-RawSafe (Join-Path $fh 'run.out')
Assert 'S15 modified stale file KEPT (user edits win)' (($ec -eq 0) -and ((Get-Content (Join-Path $fh '.claude\skills\fable-mode\references\superseded-note.md') -Raw) -match 'MUST SURVIVE')) "exit=$ec"
Assert 'S15 kept-modified noted in output' ($out15b -match 'modified since its kit install - kept')
# corrupt ledger: cleanup skipped, install passes, fresh baseline ledger heals it
$fh = New-FakeHome 'fh15c'
$proj = Join-Path $fh 'Desktop\Projects\Claude Code'
$ec = Invoke-Installer $fh $proj $KIT
'{{{{not json' | Set-Content (Join-Path $fh '.claude\fable-install-ledger.json') -Encoding UTF8
'stray local note' | Set-Content (Join-Path $fh '.claude\skills\fable-mode\NOTES-local.md') -Encoding UTF8
$ec = Invoke-Installer $fh $proj $KIT
$out15c = Get-RawSafe (Join-Path $fh 'run.out')
$ledgC = Get-Content (Join-Path $fh '.claude\fable-install-ledger.json') -Raw | ConvertFrom-Json
Assert 'S15 corrupt ledger: exit 0, unreadable noted, stray untouched' (($ec -eq 0) -and ($out15c -match 'unreadable') -and (Test-Path (Join-Path $fh '.claude\skills\fable-mode\NOTES-local.md'))) "exit=$ec"
Assert 'S15 corrupt ledger healed: fresh baseline ledger valid' ($ledgC.kitVersion -eq $mfKit.kitVersion)
# adversarial ledger names: a crafted entry that differs from a protected/managed
# file only by a trailing dot (GetFullPath strips it -> resolves to the real file)
# must be refused as non-canonical, never delete settings.json or a shipped kit file
$fh = New-FakeHome 'fh15d'
$proj = Join-Path $fh 'Desktop\Projects\Claude Code'
$ec = Invoke-Installer $fh $proj $KIT
$setHash = Get-Sha (Join-Path $fh '.claude\settings.json')
$clHash = Get-Sha (Join-Path $fh '.claude\CLAUDE.md')
$evil = @{ kitVersion = 'rEVIL'; installedAt = '2020-01-01T00:00:00+00:00'; files = @(
    @{ path = 'settings.json.'; sha256 = $setHash },
    @{ path = 'CLAUDE.md.'; sha256 = $clHash },
    @{ path = 'projects.\memory\note.md'; sha256 = $clHash }
) }
ConvertTo-Json -InputObject $evil -Depth 8 | Set-Content (Join-Path $fh '.claude\fable-install-ledger.json') -Encoding UTF8
$ec = Invoke-Installer $fh $proj $KIT
$out15d = Get-RawSafe (Join-Path $fh 'run.out')
Assert 'S15 adversarial trailing-dot ledger: entries refused as non-canonical' (($ec -eq 0) -and ($out15d -match 'ledger path not canonical - skipped')) "exit=$ec"
Assert 'S15 adversarial: settings.json + CLAUDE.md NOT deleted' ((Test-Path (Join-Path $fh '.claude\settings.json')) -and (Test-Path (Join-Path $fh '.claude\CLAUDE.md')) -and ($out15d -notmatch 'stale kit file removed \(backed up\): settings\.json') -and ($out15d -notmatch 'stale kit file removed \(backed up\): CLAUDE\.md'))
# adversarial ledger REACH (r32): entries that point outside .claude - by ..\ traversal,
# or THROUGH a junction planted inside .claude - must be refused even with TRUE hashes
# (the worst case: the hash gate alone would approve the deletion). Pins install.ps1's
# traversal reject + resolved containment + reparse-walk guards, execution-proven
# against the shipped exe 2026-07-18 and made durable here.
$fh = New-FakeHome 'fh15e'
$proj = Join-Path $fh 'Desktop\Projects\Claude Code'
$ec = Invoke-Installer $fh $proj $KIT
$victimA = Join-Path $fh 'precious-user-file.txt'
'DO-NOT-DELETE-A' | Set-Content $victimA -Encoding UTF8
$outsideDir = Join-Path $fh 'outside-dir'
New-Item -ItemType Directory -Force $outsideDir | Out-Null
$victimB = Join-Path $outsideDir 'victim-b.txt'
'DO-NOT-DELETE-B' | Set-Content $victimB -Encoding UTF8
cmd /c mklink /J (Join-Path $fh '.claude\linkdir') $outsideDir | Out-Null
$evil2 = @{ kitVersion = 'rEVIL2'; installedAt = '2020-01-01T00:00:00+00:00'; files = @(
    @{ path = '..\precious-user-file.txt'; sha256 = (Get-Sha $victimA) },
    @{ path = 'linkdir\victim-b.txt'; sha256 = (Get-Sha $victimB) }
) }
ConvertTo-Json -InputObject $evil2 -Depth 8 | Set-Content (Join-Path $fh '.claude\fable-install-ledger.json') -Encoding UTF8
$ec = Invoke-Installer $fh $proj $KIT
$out15e = Get-RawSafe (Join-Path $fh 'run.out')
$ledgE = Get-Content (Join-Path $fh '.claude\fable-install-ledger.json') -Raw | ConvertFrom-Json
Assert 'S15 traversal ledger entry refused: outside file survives (true hash)' (($ec -eq 0) -and (Test-Path -LiteralPath $victimA)) "exit=$ec"
Assert 'S15 traversal refusal is LOUD (guard itself pinned, not just the outcome)' ($out15e -match 'ledger path outside install root - skipped')
Assert 'S15 through-junction ledger entry refused: linked file survives (true hash)' (Test-Path -LiteralPath $victimB)
Assert 'S15 junction itself not deleted-through' (Test-Path -LiteralPath (Join-Path $fh '.claude\linkdir'))
Assert 'S15 evil-reach ledger re-baselined, hostile entries gone' (($ledgE.kitVersion -eq $mfKit.kitVersion) -and -not (@($ledgE.files.path) -like '*precious*') -and -not (@($ledgE.files.path) -like '*victim*'))
cmd /c rmdir (Join-Path $fh '.claude\linkdir') 2>$null

Write-Host ""
Write-Host "==================== RESULTS ===================="
$script:Lines | ForEach-Object { Write-Host $_ }
Write-Host "================================================="
Write-Host "TOTAL: $script:Pass passed, $script:Fail failed"
if ($script:Fail -eq 0) {
    try { Remove-Item $FHROOT -Recurse -Force } catch { Write-Host "(cleanup of $FHROOT failed - remove manually)" }
    # this run's own %TEMP% residue: transcript logs + extraction dirs created since t0
    try { Get-ChildItem $env:TEMP -Filter 'fable-install-*.log' -File | Where-Object { $_.LastWriteTime -ge $t0 } | Remove-Item -Force } catch { }
    try { Get-ChildItem $env:TEMP -Filter 'fable-kit-*' -Directory | Where-Object { $_.CreationTime -ge $t0 } | Remove-Item -Recurse -Force } catch { }
    try { Remove-Item (Join-Path $env:TEMP 'fable-kit') -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    exit 0
} else {
    Write-Host "(fake homes kept for inspection under $FHROOT)"
    exit 1
}
