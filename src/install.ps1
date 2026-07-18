# ============================================================================
#  Fable System - one-click installer
#  Restores the complete fable-system environment - frontier-grade process
#  from any executor model: CLAUDE.md, skills, hooks, the scheduled health
#  check, and user-scope MCP registrations - onto a fresh (or existing)
#  Windows machine. The kit's claude-home\ tree maps to ~\.claude (the dotless
#  name keeps a cloned repo from registering duplicate scoped skills).
#
#  Compatible with Windows PowerShell 5.1 (stock Windows) and PowerShell 7+.
#  Run via INSTALL.bat (double-click) or:
#    powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
#
#  Safety contract:
#   - NEVER touches .credentials.json (log in with `claude` afterwards).
#   - Backs up every file it would overwrite to .claude\fable-install-backup-<stamp>\.
#   - Merges into an existing settings.json / .claude.json - never clobbers
#     foreign keys or foreign hooks; validation-gated with automatic rollback.
#   - Memory files fill gaps only (existing memory is never overwritten
#     unless -ForceMemory is passed).
#   - Idempotent: safe to re-run; already-correct files are skipped.
#   - Upgrade hygiene: writes .claude\fable-install-ledger.json (what this kit
#     installed, with hashes). On the next install, files a PREVIOUS kit put
#     there that the new kit no longer ships are removed - only while still
#     byte-identical to what that install wrote (backed up first); anything
#     you modified or created yourself is kept.
# ============================================================================
[CmdletBinding()]
param(
    [string]$TargetHome = $env:USERPROFILE,
    [string]$ProjectPath = "",
    [switch]$Unattended,
    [switch]$ForceMemory
)

$ErrorActionPreference = 'Stop'
$KitRoot = $PSScriptRoot
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$DestClaude = Join-Path $TargetHome '.claude'
$BackupRoot = Join-Path $DestClaude "fable-install-backup-$Stamp"
if ($ProjectPath -eq "") {
    # honor OneDrive Desktop redirection on real installs; sandbox targets get a plain Desktop
    $desk = ''
    if ($TargetHome -eq $env:USERPROFILE) { $desk = [Environment]::GetFolderPath('Desktop') }
    if ([string]::IsNullOrEmpty($desk)) { $desk = Join-Path $TargetHome 'Desktop' }
    $ProjectPath = Join-Path $desk 'Projects\Claude Code'
}
$script:BackupCount = 0
$script:Results = @()
$ScriptArgs = $PSBoundParameters   # captured for the self-service relaunch (a function's own $PSBoundParameters shadows the script's)

function Write-Step([string]$msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "   $msg" -ForegroundColor Green }
function Write-Note([string]$msg) { Write-Host "   $msg" -ForegroundColor Yellow }
function Add-Result([string]$check, [string]$result, [string]$detail) {
    $script:Results += New-Object PSObject -Property @{ Check = $check; Result = $result; Detail = $detail }
}
function Get-Slug([string]$p) { return ($p -replace '[^A-Za-z0-9]', '-') }
function Get-Sha([string]$p) {
    # .NET, not Get-FileHash: survives poisoned PSModulePath from exotic parent shells
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $fs = [System.IO.File]::OpenRead($p)
        try { return ([System.BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '') }
        finally { $fs.Dispose() }
    } finally { $sha.Dispose() }
}
function Write-Utf8NoBom([string]$path, [string]$text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $text, $enc)
}
function Backup-IfExists([string]$destFile, [string]$relPath) {
    # -LiteralPath throughout: a path containing PowerShell wildcard metacharacters
    # ([ ] ? *) must never be glob-expanded - non-literal Test-Path/Copy-Item would
    # silently no-op the backup, and a caller that then deletes would lose the file
    if (Test-Path -LiteralPath $destFile) {
        $bak = Join-Path $BackupRoot $relPath
        $bakDir = Split-Path $bak -Parent
        if (-not (Test-Path -LiteralPath $bakDir)) { New-Item -ItemType Directory -Force -Path $bakDir | Out-Null }
        Copy-Item -LiteralPath $destFile $bak -Force
        $script:BackupCount++
        return $bak
    }
    return $null
}
function Test-Cmd([string]$name) {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if ($c) { return $true } else { return $false }
}
function Invoke-KitZipSelfService([object[]]$zipMatches, [string[]]$why) {
    # Gate rescue: a kit archive sits in this (failed) folder, so the install can
    # continue from the archive itself. The relaunched child re-runs the full
    # integrity gate on the clean extraction - nothing from this folder installs.
    # Interactive: offer [Y/n default Y]; decline = exit 2 with the manual commands.
    # -Unattended or a failed extraction: print the manual route and return; the
    # caller aborts with its own throw.
    $zipBeside = $zipMatches | Select-Object -First 1
    Write-Host ""
    foreach ($line in $why) { Write-Host "  $line" -ForegroundColor Yellow }
    if ($zipMatches.Count -gt 1) { Write-Note "kit zips found: $(($zipMatches | ForEach-Object Name) -join ', ') - using newest by modified time: '$($zipBeside.Name)'" }
    Write-Host ("  Archive: {0}  ({1:N0} bytes, modified {2:yyyy-MM-dd HH:mm})" -f $zipBeside.Name, $zipBeside.Length, $zipBeside.LastWriteTime) -ForegroundColor Yellow
    $extractDir = Join-Path $env:TEMP 'fable-kit'
    # never pre-clean the very folder this script (and the zip) live in (canonical compare)
    if ([IO.Path]::GetFullPath($extractDir).TrimEnd('\') -ieq [IO.Path]::GetFullPath($KitRoot).TrimEnd('\')) { $extractDir = Join-Path $env:TEMP "fable-kit-$Stamp" }
    if (-not $Unattended) {
        $ansX = Read-Host "`n  Extract '$($zipBeside.Name)' to $extractDir and install from there? [Y/n]"
        if ($ansX -notmatch '^[Nn]') {
            $extractOk = $true
            try {
                # never recurse-delete through a reparse point (same guard as every other delete path)
                if (Test-Path -LiteralPath $extractDir) {
                    $exItem = Get-Item -LiteralPath $extractDir -Force
                    if ($exItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "extraction dir '$extractDir' is a reparse point - refusing to delete through it" }
                    Remove-Item -LiteralPath $extractDir -Recurse -Force
                }
                Expand-Archive -LiteralPath $zipBeside.FullName -DestinationPath $extractDir -Force
            } catch { Write-Note "extraction failed: $($_.Exception.Message)"; $extractOk = $false }
            if ($extractOk -and -not ((Test-Path -LiteralPath (Join-Path $extractDir 'install.ps1')) -and (Test-Path -LiteralPath (Join-Path $extractDir 'kit-manifest.json')))) {
                Write-Note "the extracted zip does not contain install.ps1 and kit-manifest.json at its root - not a valid kit archive"
                $extractOk = $false
            }
            if ($extractOk) {
                Write-Ok "extracted '$($zipBeside.Name)' to $extractDir - continuing from the extracted kit"
                & (Join-Path $extractDir 'install.ps1') @ScriptArgs
                $childCode = $LASTEXITCODE
                if ($childCode -eq 0) { Invoke-LaunchFolderCleanup $extractDir }
                exit $childCode
            }
        } else {
            Write-Host ""
            Write-Host "  To do it manually later, in PowerShell:" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "    Expand-Archive `"$($zipBeside.FullName)`" `"`$env:TEMP\fable-kit`" -Force" -ForegroundColor Cyan
            Write-Host "    & `"`$env:TEMP\fable-kit\INSTALL.bat`"" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Aborted by user."
            exit 2
        }
    }
    Write-Host "  Extract the kit zip and run INSTALL.bat from the extracted folder. In PowerShell:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    Expand-Archive `"$($zipBeside.FullName)`" `"`$env:TEMP\fable-kit`" -Force" -ForegroundColor Cyan
    Write-Host "    & `"`$env:TEMP\fable-kit\INSTALL.bat`"" -ForegroundColor Cyan
    Write-Host ""
}
function Invoke-LaunchFolderCleanup([string]$verifiedKit) {
    # The install just succeeded from the extracted archive; the folder the user
    # launched from still holds the copies that failed the gate. Any file there
    # that is byte-identical to the verified kit is a redundant duplicate (an
    # unpacked kit tree inside a project folder also registers duplicate scoped
    # skills). Offer to remove exactly those - never the archive, never non-kit
    # files, never anything under the install destination (launch folder == target
    # home is survivable), never through a junction/symlink, and only the emptied
    # directories are pruned. Recovery: the archive sitting right beside them.
    # Best-effort: a cleanup failure never fails the (already successful) install.
    try {
        $destFull = [IO.Path]::GetFullPath($DestClaude).TrimEnd('\') + '\'
        $rootFull = [IO.Path]::GetFullPath($KitRoot).TrimEnd('\')
        $mf = Get-Content (Join-Path $verifiedKit 'kit-manifest.json') -Raw | ConvertFrom-Json
        $cand = @()
        foreach ($f in $mf.files) { $cand += $f }
        $cand += New-Object PSObject -Property @{ path = 'kit-manifest.json'; sha256 = (Get-Sha (Join-Path $verifiedKit 'kit-manifest.json')) }
        $dupes = @()
        foreach ($f in $cand) {
            if ($f.path -match '^[A-Za-z]:|^[\\/]|\.\.') { continue }   # relative, inside-the-folder paths only
            $localFull = [IO.Path]::GetFullPath((Join-Path $KitRoot $f.path))
            if (-not $localFull.StartsWith($rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($localFull.StartsWith($destFull, [System.StringComparison]::OrdinalIgnoreCase)) { continue }   # never reach into the install destination
            if (-not (Test-Path -LiteralPath $localFull)) { continue }
            $viaLink = $false
            $walk = Split-Path $localFull -Parent
            while ($walk -and ($walk.TrimEnd('\').Length -gt $rootFull.Length)) {
                $wi = Get-Item -LiteralPath $walk -Force -ErrorAction SilentlyContinue
                if ($wi -and (($wi.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { $viaLink = $true; break }
                $walk = Split-Path $walk -Parent
            }
            if ($viaLink) { continue }
            if ((Get-Sha $localFull) -eq $f.sha256) { $dupes += New-Object PSObject -Property @{ path = $f.path; sha256 = $f.sha256; full = $localFull } }
        }
        if ($dupes.Count -eq 0) { return }
        $buckets = @{}
        foreach ($d in $dupes) { $top = ($d.path -split '\\')[0]; if (-not $buckets.ContainsKey($top)) { $buckets[$top] = 0 }; $buckets[$top]++ }
        $summary = (($buckets.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key) ($($_.Value))" }) -join ', ')
        Write-Host ""
        Write-Host "  The folder you launched from still holds $($dupes.Count) file(s) byte-identical to the" -ForegroundColor Yellow
        Write-Host "  installed kit (an unpacked kit tree also registers duplicate scoped skills):" -ForegroundColor Yellow
        Write-Host "  $summary" -ForegroundColor Yellow
        if (Test-Path -LiteralPath (Join-Path $KitRoot '.git')) {
            # a source repository's byte-identical files are CANONICAL copies, not debris
            Write-Host "  This folder looks like a source repository (.git present) - these are likely canonical copies." -ForegroundColor Yellow
            $ansC = Read-Host "  Remove them anyway (the archive and any non-kit files stay)? [y/N]"
            if (-not ($ansC -match '^[Yy]')) { Write-Note "kept - delete manually later; the kit zip beside them is the recovery copy"; return }
        } else {
            $ansC = Read-Host "  Remove those duplicates (the archive and any non-kit files stay)? [Y/n]"
            # closed stdin (AutomationNull) must fail SAFE for a destructive prompt: keep
            if ($null -eq $ansC -or $ansC -match '^[Nn]') { Write-Note "kept - delete manually later; the kit zip beside them is the recovery copy"; return }
        }
        $removed = 0
        $parents = @{}
        foreach ($d in $dupes) {
            try {
                if ((Get-Sha $d.full) -ne $d.sha256) { Write-Note "changed since the check, kept: $($d.path)"; continue }   # no deletes on a stale hash
                Remove-Item -LiteralPath $d.full -Force
                $removed++
                $parents[(Split-Path $d.full -Parent)] = $true
            } catch { Write-Note "could not remove: $($d.path) ($($_.Exception.Message))" }
        }
        # prune ONLY directories our removals emptied, walking up toward the launch folder
        foreach ($p in @($parents.Keys)) {
            $walk = $p
            while ($walk -and ($walk.TrimEnd('\').Length -gt $rootFull.Length)) {
                $wi = Get-Item -LiteralPath $walk -Force -ErrorAction SilentlyContinue
                if (-not $wi) { break }
                if (($wi.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { break }
                if (@(Get-ChildItem -LiteralPath $walk -Force).Count -gt 0) { break }
                try { Remove-Item -LiteralPath $walk -Force } catch { break }
                $walk = Split-Path $walk -Parent
            }
        }
        Write-Ok "$removed duplicate kit file(s) removed from the launch folder"
        $others = @(Get-ChildItem $KitRoot -Filter 'fable-restore-kit-*.zip' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -Skip 1)
        if ($others.Count -gt 0) { Write-Note "older kit zip(s) also here: $(($others | ForEach-Object Name) -join ', ') - superseded; delete them yourself once this install is verified (they are not touched automatically: they may be your only backups)" }
    } catch { Write-Note "launch-folder cleanup skipped: $($_.Exception.Message)" }
}

$log = $null
try { Start-Transcript -Path (Join-Path $env:TEMP "fable-install-$Stamp.log") -ErrorAction Stop | Out-Null; $log = Join-Path $env:TEMP "fable-install-$Stamp.log" } catch { }

try {
    # ------------------------------------------------------------------ banner
    Write-Host ""
    Write-Host "  FABLE SYSTEM INSTALLER" -ForegroundColor Cyan
    Write-Host "  Kit root : $KitRoot"
    Write-Host "  Target   : $DestClaude"
    Write-Host "  Project  : $ProjectPath"
    Write-Host "  Backups  : $BackupRoot (created only if a file is overwritten or cleaned up)"
    Write-Host ""
    Write-Host "  If Claude Code is currently RUNNING on this machine, close it first" -ForegroundColor Yellow
    Write-Host "  (it can rewrite .claude.json concurrently)." -ForegroundColor Yellow
    if (-not $Unattended) {
        $ans = Read-Host "`n  Proceed? [Y/n]"
        if ($ans -match '^[Nn]') { Write-Host "Aborted by user."; exit 2 }
    }

    # housekeeping (after the proceed prompt, so an abort really changes nothing):
    # this installer's OWN %TEMP% residue from prior runs - stamp-shaped transcript
    # logs beyond the newest 10, and stale stamp-shaped extraction dirs. Never the
    # current run's log, the shared fable-kit dir (pre-cleaned at use), or the
    # folder this script runs from. Best-effort: cleanup never blocks an install.
    try {
        $oldLogs = @(Get-ChildItem $env:TEMP -Filter 'fable-install-*.log' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^fable-install-\d{8}-\d{6}-\d{3}\.log$' } | Sort-Object LastWriteTime -Descending | Select-Object -Skip 10)
        foreach ($ol in $oldLogs) { Remove-Item -LiteralPath $ol.FullName -Force -ErrorAction SilentlyContinue }
        $kitRootFull = [IO.Path]::GetFullPath($KitRoot).TrimEnd('\')
        $staleKits = @(Get-ChildItem $env:TEMP -Filter 'fable-kit-*' -Directory -ErrorAction SilentlyContinue | Where-Object { ($_.Name -match '^fable-kit-\d{8}-\d{6}-\d{3}$') -and ($_.Name -ine "fable-kit-$Stamp") -and ([IO.Path]::GetFullPath($_.FullName).TrimEnd('\') -ine $kitRootFull) -and ($_.CreationTime -lt (Get-Date).AddHours(-1)) })
        foreach ($sk in $staleKits) { Remove-Item -LiteralPath $sk.FullName -Recurse -Force -ErrorAction SilentlyContinue }
        if ($oldLogs.Count -gt 0 -or $staleKits.Count -gt 0) { Write-Note "housekeeping: removed $($oldLogs.Count) old install log(s) and $($staleKits.Count) stale extraction dir(s) from %TEMP%" }
    } catch { }

    # ---------------------------------------------------- 1. kit integrity gate
    Write-Step "1/9 Kit integrity (kit-manifest.json)"
    $manifestPath = Join-Path $KitRoot 'kit-manifest.json'
    if (-not (Test-Path $manifestPath)) {
        $zipMatches = @(Get-ChildItem $KitRoot -Filter 'fable-restore-kit-*.zip' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        if ($zipMatches.Count -gt 0) {
            Invoke-KitZipSelfService $zipMatches @(
                "This looks like the SOURCE copy of the installer (or an incomplete extraction),",
                "not an extracted kit: '$($zipMatches[0].Name)' sits next to this script",
                "but kit-manifest.json does not.")
            throw "kit-manifest.json missing - running from the source copy, not an extracted kit. Nothing was installed."
        }
        throw "kit-manifest.json missing - kit is incomplete; re-copy or re-download the kit zip. Nothing was installed."
    }
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $badCount = 0
    foreach ($f in $manifest.files) {
        $full = Join-Path $KitRoot $f.path
        if (-not (Test-Path $full)) { Write-Note "MISSING: $($f.path)"; $badCount++; continue }
        $h = Get-Sha $full
        if ($h -ne $f.sha256) { Write-Note "HASH MISMATCH: $($f.path)"; $badCount++ }
    }
    # set-equality, not allowlist: a file in the kit that the manifest doesn't
    # list must never install silently
    $listed = @{}
    foreach ($f in $manifest.files) { $listed[$f.path.ToLower()] = $true }
    # -Force: a hidden stray must fail the gate loudly, not slip past it unenumerated
    foreach ($kitFile in (Get-ChildItem -LiteralPath $KitRoot -Recurse -File -Force)) {
        $rp = $kitFile.FullName.Substring($KitRoot.Length + 1)
        if ($rp -ieq 'kit-manifest.json') { continue }
        if (-not $listed.ContainsKey($rp.ToLower())) {
            Write-Note "UNLISTED FILE: $rp"; $badCount++
        }
    }
    if ($badCount -gt 0) {
        Add-Result 'kit integrity' 'FAIL' "$badCount file(s) missing or altered"
        $zipMatches = @(Get-ChildItem $KitRoot -Filter 'fable-restore-kit-*.zip' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        $hint = ""
        if ($zipMatches.Count -gt 0) {
            Invoke-KitZipSelfService $zipMatches @(
                "This folder failed the integrity check ($badCount problem file(s) above) - it looks like",
                "the kit's source folder, or an extraction mixed into other files.")
            $hint = " Note: a kit archive sits in this folder - run the printed Expand-Archive commands (or re-run interactively and accept the extract offer) to install from the verified archive."
        }
        throw "Kit failed integrity check ($badCount problem file(s)). Nothing was installed. Use a clean copy of the kit.$hint"
    }
    Write-Ok "all $($manifest.files.Count) kit files match manifest (kit $($manifest.kitVersion), built $($manifest.builtAt))"
    Add-Result 'kit integrity' 'PASS' "$($manifest.files.Count) files verified"

    # ------------------------------------------------------- 2. prerequisites
    Write-Step "2/9 Prerequisites"
    $hasClaude = Test-Cmd 'claude'
    $gitBash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
    $hasGitBash = (Test-Path $gitBash) -or (Test-Cmd 'git')
    $hasNode = Test-Cmd 'node'
    $hasWinget = Test-Cmd 'winget'
    $prereqLines = @(
        @{ Name = 'Claude Code'; Ok = $hasClaude; Winget = 'Anthropic.ClaudeCode'; Alt = 'irm https://claude.ai/install.ps1 | iex' },
        @{ Name = 'Git for Windows (Git Bash runs the hooks)'; Ok = $hasGitBash; Winget = 'Git.Git'; Alt = 'https://git-scm.com/download/win' },
        @{ Name = 'Node.js (prompt classifier + JSON merges)'; Ok = $hasNode; Winget = 'OpenJS.NodeJS.LTS'; Alt = 'https://nodejs.org' }
    )
    foreach ($p in $prereqLines) {
        if ($p.Ok) { Write-Ok "$($p.Name): found" }
        else {
            Write-Note "$($p.Name): NOT FOUND"
            if ($hasWinget -and -not $Unattended) {
                $a = Read-Host "     Install now via 'winget install $($p.Winget)'? [Y/n]"
                if ($a -notmatch '^[Nn]') {
                    & winget install --id $p.Winget -e
                    if ($LASTEXITCODE -eq 0) { Write-Ok "installed $($p.Winget) (open a NEW terminal for PATH changes)" }
                    else { Write-Note "winget exited $LASTEXITCODE - install manually: $($p.Alt)" }
                }
            } else {
                Write-Note "     install later: winget install $($p.Winget)   (or: $($p.Alt))"
            }
        }
    }
    # re-probe node (may have just been installed; PATH may still need a new shell)
    $hasNode = Test-Cmd 'node'
    # counted from the PRE-winget probe: a tool installed a moment ago is usually not on this
    # process's PATH yet, so the count reports the state this run started with, not a stale bug
    $missing = @($prereqLines | Where-Object { -not $_.Ok }).Count
    if ($missing -eq 0) { Add-Result 'prerequisites' 'PASS' 'claude, git bash, node all present' }
    else { Add-Result 'prerequisites' 'WARN' "$missing missing at start of run - files install anyway; hooks/classifier need Git Bash + Node (if you installed them just now, open a NEW terminal)" }

    # ------------------------------------- 3. copy .claude tree (not settings)
    Write-Step "3/9 Files: CLAUDE.md, skills, scheduled task"
    $kitClaude = Join-Path $KitRoot 'claude-home'
    if (-not (Test-Path $DestClaude)) { New-Item -ItemType Directory -Force -Path $DestClaude | Out-Null }
    $copied = 0; $skipped = 0; $copyErrors = @()
    # -LiteralPath throughout: a TargetHome containing [ or ] otherwise breaks the hash-skip
    # (re-copying and re-backing-up every run) and the step-8 verify, per the note at the top
    Get-ChildItem -LiteralPath $kitClaude -Recurse -File -Force | ForEach-Object {
        $rel = $_.FullName.Substring($kitClaude.Length + 1)
        if ($rel -ieq 'settings.json') { return }        # merged in step 4
        if ($rel -ieq '.credentials.json') { return }    # never ships, never installed
        try {
            $dest = Join-Path $DestClaude $rel
            if ((Test-Path -LiteralPath $dest) -and ((Get-Sha $dest) -eq (Get-Sha $_.FullName))) { $skipped++; return }
            Backup-IfExists $dest (Join-Path '.claude' $rel) | Out-Null
            $destDir = Split-Path $dest -Parent
            if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
            $copied++
        } catch {
            $copyErrors += "$rel -> $($_.Exception.Message)"
            Write-Note "copy failed: $rel ($($_.Exception.Message))"
        }
    }
    Write-Ok "$copied file(s) installed, $skipped already correct"
    if ($copyErrors.Count -eq 0) { Add-Result 'core files' 'PASS' "$copied installed, $skipped identical" }
    else { Add-Result 'core files' 'FAIL' "$($copyErrors.Count) copy error(s); first: $($copyErrors[0])" }

    # ------------------------------------ 4. upgrade hygiene: stale-file cleanup
    Write-Step "4/9 Upgrade hygiene: previous-version cleanup + install ledger"
    # The ledger records what THIS kit install put under .claude (path + sha256).
    # Next install: a path a PREVIOUS kit installed that the new kit no longer
    # ships is stale debris - removed (backed up first) only while byte-identical
    # to what that install wrote; user-modified or user-created files are kept.
    # Managed set = every claude-home\ payload file except settings.json (merged,
    # never owned) and .credentials.json (never ships, never touched).
    $ledgerPath = Join-Path $DestClaude 'fable-install-ledger.json'
    $managedNow = @{}
    foreach ($f in $manifest.files) {
        if ($f.path -notlike 'claude-home\*') { continue }
        $relM = $f.path.Substring(12)
        if (($relM -ieq 'settings.json') -or ($relM -ieq '.credentials.json')) { continue }
        $managedNow[$relM.ToLower()] = $f
    }
    $oldLedger = $null
    $removedCnt = 0; $keptModified = 0; $ledgerReadable = $true
    if (Test-Path -LiteralPath $ledgerPath) {
        try { $oldLedger = Get-Content $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { $ledgerReadable = $false; Write-Note "previous install ledger unreadable - cleanup skipped this run, a fresh ledger will be written ($($_.Exception.Message))" }
        # an empty file (Get-Content -Raw -> $null) or a well-formed JSON without a
        # files[] array parses without throwing but is not a usable ledger: treat it
        # as unreadable (honest WARN + skip cleanup) rather than a clean baseline
        if ($ledgerReadable -and -not ($oldLedger -and $oldLedger.PSObject.Properties['files'])) {
            $ledgerReadable = $false
            Write-Note "previous install ledger malformed (no file list) - cleanup skipped this run, a fresh ledger will be written"
        }
    }
    if ($oldLedger -and $oldLedger.PSObject.Properties['files']) {
        $destFull = [IO.Path]::GetFullPath($DestClaude).TrimEnd('\')
        foreach ($e in @($oldLedger.files)) {
            try {
                if (-not ($e -and $e.PSObject.Properties['path'] -and $e.PSObject.Properties['sha256'])) { continue }
                $rel = ([string]$e.path) -replace '/', '\'
                if ($rel -match '^[A-Za-z]:|^[\\/]|\.\.') { continue }                     # relative, no traversal
                $target = [IO.Path]::GetFullPath((Join-Path $DestClaude $rel))
                if (-not $target.StartsWith($destFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                if (-not (Test-Path -LiteralPath $target)) { continue }
                # Canonicalize against the real on-disk name BEFORE any guard decides.
                # [IO.Path]::GetFullPath strips trailing dots/spaces from every segment,
                # so 'settings.json.' or 'projects.\x' would resolve to a protected file
                # while a raw-string guard on $rel sees a different name. Deriving the
                # guard key from Get-Item's actual FullName (and refusing any entry whose
                # spelling isn't already canonical) closes that bypass and 8.3 aliasing.
                $canonItem = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
                if (-not $canonItem) { continue }
                $canon = $canonItem.FullName
                if (-not $canon.StartsWith($destFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                $canonRel = $canon.Substring($destFull.Length + 1)
                if ($canonRel -ine $rel) { Write-Note "ledger path not canonical - skipped: $rel"; continue }
                if ($managedNow.ContainsKey($canonRel.ToLower())) { continue }             # still shipped by this kit
                # defense in depth: cleanup never touches config, credentials, memory, backups
                if (($canonRel -ieq 'settings.json') -or ($canonRel -like '.credentials*') -or ($canonRel -like 'projects\*') -or ($canonRel -like 'fable-install-backup-*')) { continue }
                $viaLink = $false
                $walk = Split-Path $target -Parent
                while ($walk -and ($walk.TrimEnd('\').Length -gt $destFull.Length)) {
                    $wi = Get-Item -LiteralPath $walk -Force -ErrorAction SilentlyContinue
                    if ($wi -and (($wi.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { $viaLink = $true; break }
                    $walk = Split-Path $walk -Parent
                }
                if ($viaLink) { continue }
                if ((Get-Sha $target) -eq [string]$e.sha256) {
                    Backup-IfExists $target (Join-Path '.claude' $canonRel) | Out-Null
                    Remove-Item -LiteralPath $target -Force
                    $removedCnt++
                    Write-Ok "stale kit file removed (backed up): $canonRel"
                    # prune only directories this removal emptied - never .claude itself
                    $walk = Split-Path $target -Parent
                    while ($walk -and ($walk.TrimEnd('\').Length -gt $destFull.Length)) {
                        $wi = Get-Item -LiteralPath $walk -Force -ErrorAction SilentlyContinue
                        if (-not $wi) { break }
                        if (($wi.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { break }
                        if (@(Get-ChildItem -LiteralPath $walk -Force).Count -gt 0) { break }
                        try { Remove-Item -LiteralPath $walk -Force } catch { break }
                        $walk = Split-Path $walk -Parent
                    }
                } else {
                    $keptModified++
                    Write-Note "modified since its kit install - kept: $canonRel"
                }
            } catch { Write-Note "cleanup skipped for '$($e.path)': $($_.Exception.Message)" }
        }
    }
    # write the fresh ledger: exactly the paths THIS kit manages. Provenance rule:
    # record the kit hash when the destination now matches it; otherwise carry the
    # previous entry forward (a failed copy must not launder provenance).
    try {
        $oldByPath = @{}
        if ($oldLedger -and $oldLedger.PSObject.Properties['files']) {
            foreach ($e in @($oldLedger.files)) { if ($e -and $e.PSObject.Properties['path']) { $oldByPath[((([string]$e.path) -replace '/', '\')).ToLower()] = $e } }
        }
        $newEntries = @()
        foreach ($k in $managedNow.Keys) {
            $f = $managedNow[$k]
            $relN = $f.path.Substring(12)
            $destN = Join-Path $DestClaude $relN
            # per-entry: one unreadable/locked managed file must not abort the whole
            # ledger write (leaving the next install unable to clean this one's files)
            try {
                if ((Test-Path -LiteralPath $destN) -and ((Get-Sha $destN) -eq $f.sha256)) {
                    $newEntries += New-Object PSObject -Property @{ path = $relN; sha256 = $f.sha256 }
                } elseif ($oldByPath.ContainsKey($relN.ToLower())) {
                    $o = $oldByPath[$relN.ToLower()]
                    $newEntries += New-Object PSObject -Property @{ path = $relN; sha256 = [string]$o.sha256 }
                }
            } catch {
                if ($oldByPath.ContainsKey($relN.ToLower())) {
                    $newEntries += New-Object PSObject -Property @{ path = $relN; sha256 = [string]$oldByPath[$relN.ToLower()].sha256 }
                    Write-Note "ledger: could not hash '$relN' ($($_.Exception.Message)) - carried prior provenance forward"
                } else {
                    Write-Note "ledger: could not hash '$relN' ($($_.Exception.Message)) - no prior entry, omitted (next install cannot clean this file until it re-installs cleanly)"
                }
            }
        }
        $ledgerDoc = New-Object PSObject -Property @{
            kitVersion  = $manifest.kitVersion
            installedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz')
            files       = @($newEntries | Sort-Object path | Select-Object path, sha256)
        }
        Write-Utf8NoBom $ledgerPath (ConvertTo-Json -InputObject $ledgerDoc -Depth 8)
        if (-not $ledgerReadable) { Add-Result 'upgrade hygiene' 'WARN' "previous ledger unreadable - cleanup skipped; fresh ledger written ($($newEntries.Count) file(s))" }
        elseif ($null -eq $oldLedger) { Write-Ok "baseline install ledger written ($($newEntries.Count) file(s))"; Add-Result 'upgrade hygiene' 'PASS' "no previous ledger - baseline written ($($newEntries.Count) file(s))" }
        else {
            $sum = "$removedCnt stale removed (backed up), $keptModified modified kept; ledger $($manifest.kitVersion), $($newEntries.Count) file(s)"
            Write-Ok $sum
            Add-Result 'upgrade hygiene' 'PASS' $sum
        }
    } catch {
        Write-Note "install ledger not written: $($_.Exception.Message)"
        Add-Result 'upgrade hygiene' 'WARN' "ledger write failed - next install cannot clean this one's files ($($_.Exception.Message))"
    }

    # --------------------------------------------------- 5. settings.json merge
    Write-Step "5/9 settings.json (hooks)"
    $kitSettingsPath = Join-Path $kitClaude 'settings.json'
    $destSettings = Join-Path $DestClaude 'settings.json'
    $mergeTool = Join-Path $KitRoot 'tools\fable-merge.js'
    if (-not (Test-Path -LiteralPath $destSettings)) {
        Copy-Item -LiteralPath $kitSettingsPath -Destination $destSettings
        Write-Ok "no existing settings.json - kit copy installed whole"
    } else {
        $bak = Backup-IfExists $destSettings '.claude\settings.json'
        Write-Ok "existing settings.json backed up"
        $mergedVia = ''
        if ($hasNode -and (Test-Path $mergeTool)) {
            & node $mergeTool hooks $destSettings $kitSettingsPath
            if ($LASTEXITCODE -eq 0) { $mergedVia = 'node' } else { Write-Note "node merge failed (exit $LASTEXITCODE), trying PowerShell merge" }
        }
        if ($mergedVia -eq '') {
            try {
                $cur = Get-Content -LiteralPath $destSettings -Raw -Encoding UTF8 | ConvertFrom-Json
                $kit = Get-Content -LiteralPath $kitSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
                # change detection: serialize the parsed state now, compare before writing -
                # a no-op re-run must leave the file untouched (parity with fable-merge.js)
                $origSerialized = ConvertTo-Json -InputObject $cur -Depth 64
                if (-not $cur.PSObject.Properties['hooks']) { $cur | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object PSObject) }
                # replaceable fable variant = marker AND action-signature phrase; foreign hooks that merely mention the marker never match
                $fableMarkers = @{ SessionStart = @('Standing order (user settings hook)', 'invoke the fable-mode skill'); UserPromptSubmit = @('Prompt classifier (user hook)', 'invoke the fable-mode skill'); SubagentStart = @('Standing order (user hook)', 'verify claims by execution') }
                foreach ($evProp in $kit.hooks.PSObject.Properties) {
                    $ev = $evProp.Name
                    $kitGroups = @($evProp.Value)
                    if (-not $cur.hooks.PSObject.Properties[$ev]) {
                        $cur.hooks | Add-Member -NotePropertyName $ev -NotePropertyValue @($kitGroups)
                        continue
                    }
                    $kitCmds = @(); foreach ($g in $kitGroups) { foreach ($h in @($g.hooks)) { if ($h.command) { $kitCmds += $h.command } } }
                    $marker = $fableMarkers[$ev]
                    if ($marker) {
                        # superseded fable variants (marker + signature, different command) are replaced, not accumulated
                        $newGroups = @()
                        foreach ($g in @($cur.hooks.$ev)) {
                            if ($null -eq $g) { continue }   # a literal null in the event array is dropped, not re-serialized
                            if (-not ($g.PSObject.Properties['hooks'] -and ($g.hooks -is [array]))) { $newGroups += $g; continue }
                            $kept = @()
                            foreach ($h in @($g.hooks)) {
                                if ($h -and $h.command -and $h.command.Contains($marker[0]) -and $h.command.Contains($marker[1]) -and ($kitCmds -notcontains $h.command)) { continue }
                                $kept += $h
                            }
                            if ($kept.Count -gt 0) { $g.hooks = $kept; $newGroups += $g }
                        }
                        $cur.hooks.$ev = $newGroups
                    }
                    $have = @()
                    foreach ($g in @($cur.hooks.$ev)) { foreach ($h in @($g.hooks)) { if ($h.command) { $have += $h.command } } }
                    foreach ($g in $kitGroups) {
                        $cmds = @(); foreach ($h in @($g.hooks)) { if ($h.command) { $cmds += $h.command } }
                        $isNew = $false
                        foreach ($c in $cmds) { if ($have -notcontains $c) { $isNew = $true } }
                        if ($isNew) { $cur.hooks.$ev = @($cur.hooks.$ev) + $g }
                    }
                }
                foreach ($k in @('autoUpdatesChannel', 'theme', 'skipWorkflowUsageWarning')) {
                    if ($kit.PSObject.Properties[$k] -and -not $cur.PSObject.Properties[$k]) {
                        $cur | Add-Member -NotePropertyName $k -NotePropertyValue $kit.$k
                    }
                }
                $newSerialized = ConvertTo-Json -InputObject $cur -Depth 64
                if ($newSerialized -ne $origSerialized) {
                    Write-Utf8NoBom $destSettings $newSerialized
                    $mergedVia = 'powershell'
                } else {
                    $mergedVia = 'powershell (no changes, no write)'
                }
            } catch {
                if ($bak) { Copy-Item $bak $destSettings -Force }
                Write-Note "PowerShell merge failed and was rolled back: $($_.Exception.Message)"
            }
        }
        if ($mergedVia -ne '') { Write-Ok "hooks merged via $mergedVia (foreign keys and hooks preserved)" }
    }
    # validate (applies to both copy and merge paths)
    $settingsOk = $false
    try {
        $chk = Get-Content -LiteralPath $destSettings -Raw -Encoding UTF8 | ConvertFrom-Json
        $kitChk = Get-Content -LiteralPath $kitSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $settingsOk = $true
        foreach ($evProp in $kitChk.hooks.PSObject.Properties) {
            $ev = $evProp.Name
            if (-not $chk.hooks.PSObject.Properties[$ev]) { $settingsOk = $false; continue }
            if (-not ($chk.hooks.$ev -is [array])) { $settingsOk = $false; continue }
            $have = @()
            foreach ($g in @($chk.hooks.$ev)) { foreach ($h in @($g.hooks)) { if ($h.command) { $have += $h.command } } }
            foreach ($g in @($evProp.Value)) { foreach ($h in @($g.hooks)) {
                if ($h.command -and ($have -notcontains $h.command)) { $settingsOk = $false }
            } }
        }
    } catch { $settingsOk = $false }
    if ($settingsOk) { Add-Result 'settings.json hooks' 'PASS' 'valid JSON; all 3 fable hook commands present as arrays' }
    else {
        # automatic rollback (as the header promises): a failed merge must not leave
        # the user with broken settings. Restore the pre-install backup when there is
        # one; a fresh install has no prior file, so the kit copy (already gate-valid)
        # stays in place.
        if ($bak -and (Test-Path -LiteralPath $bak)) {
            Copy-Item -LiteralPath $bak $destSettings -Force
            Add-Result 'settings.json hooks' 'FAIL' 'validation failed - automatically rolled back to your pre-install settings.json'
            Write-Note "settings.json validation FAILED - automatically restored your original from the backup; re-run with Node.js installed, or merge the hooks manually"
        } else {
            Add-Result 'settings.json hooks' 'FAIL' 'validation failed - no prior settings.json to restore; review the file'
            Write-Note "settings.json validation FAILED and there was no prior file to restore - review $destSettings"
        }
    }

    # -------------------------------------------------------- 6. project memory
    Write-Step "6/9 Project memory"
    $slug = Get-Slug $ProjectPath
    $memDest = Join-Path $DestClaude "projects\$slug\memory"
    $memSkipped = $false
    $memSrc = Join-Path $KitRoot 'memory'
    if (-not (Test-Path $memSrc)) {
        # public kits never carry personal data; memory ships only in a private build
        Write-Ok "this kit ships no project memory - skipping"
        Add-Result 'project memory' 'PASS' 'kit ships none'
        $memSkipped = $true
    } else {
    try {
        if (-not (Test-Path $ProjectPath)) { New-Item -ItemType Directory -Force -Path $ProjectPath | Out-Null; Write-Ok "created project folder $ProjectPath" }
        # measure the ACTUAL longest kit memory filename - a hardcoded name went
        # stale once already (r14 pinned the second-longest and under-measured by 2)
        $longestName = (Get-ChildItem $memSrc -File | Sort-Object { $_.Name.Length } -Descending | Select-Object -First 1).Name
        if (-not $longestName) { throw "kit memory folder is empty - kit invalid (integrity gate should have caught this)" }
        $longestDest = Join-Path $memDest $longestName
        if ($longestDest.Length -gt 250) {
            Write-Note "memory destination path is $($longestDest.Length) chars - beyond classic Windows MAX_PATH."
            Write-Note "Skipping memory restore. Fix: use a shallower project path, or enable Windows long paths, then re-run."
            Add-Result 'project memory' 'WARN' "path too long ($($longestDest.Length) chars) - skipped"
            $memSkipped = $true
        } else {
            if (-not (Test-Path -LiteralPath $memDest)) { New-Item -ItemType Directory -Force -Path $memDest | Out-Null }
            $mInstalled = 0; $mKept = 0
            Get-ChildItem -LiteralPath $memSrc -File | ForEach-Object {
                $dest = Join-Path $memDest $_.Name
                if ((Test-Path -LiteralPath $dest) -and -not $ForceMemory) { $mKept++; return }
                Backup-IfExists $dest (Join-Path "projects\$slug\memory" $_.Name) | Out-Null
                Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
                $mInstalled++
            }
            Write-Ok "$mInstalled memory file(s) installed, $mKept existing kept (use -ForceMemory to overwrite)"
            Add-Result 'project memory' 'PASS' "slug $slug; $mInstalled installed, $mKept kept"
        }
    } catch {
        Write-Note "memory restore failed: $($_.Exception.Message)"
        Add-Result 'project memory' 'FAIL' $_.Exception.Message
        $memSkipped = $true
    }
    }

    # ------------------------------------------------- 7. MCP registrations
    Write-Step "7/9 MCP servers (user scope)"
    $tplPath = Join-Path $KitRoot 'mcp-servers.template.json'
    if (-not (Test-Path $tplPath)) {
        Write-Note "no mcp-servers.template.json in kit - skipping"
        Add-Result 'mcp servers' 'WARN' 'template absent from kit'
    } else {
      try {
        $claudeJson = Join-Path $TargetHome '.claude.json'
        $mcpResult = ''
        if (Test-Path $claudeJson) { Backup-IfExists $claudeJson '.claude.json' | Out-Null }
        if ($hasNode -and (Test-Path $mergeTool)) {
            $out = & node $mergeTool mcp $claudeJson $tplPath $TargetHome
            if ($LASTEXITCODE -eq 0) { $mcpResult = "$out (via node)" } else { Write-Note "node mcp merge failed (exit $LASTEXITCODE)" }
        }
        if ($mcpResult -eq '') {
            try {
                $tplRawTxt = (Get-Content $tplPath -Raw -Encoding UTF8).Replace('<<HOME>>', $TargetHome.Replace('\', '\\'))
                $tpl = $tplRawTxt | ConvertFrom-Json
                if (Test-Path $claudeJson) { $cj = Get-Content $claudeJson -Raw -Encoding UTF8 | ConvertFrom-Json }
                else { $cj = New-Object PSObject }
                if (-not $cj.PSObject.Properties['mcpServers']) { $cj | Add-Member -NotePropertyName mcpServers -NotePropertyValue (New-Object PSObject) }
                $added = @()
                foreach ($sProp in $tpl.mcpServers.PSObject.Properties) {
                    if (-not $cj.mcpServers.PSObject.Properties[$sProp.Name]) {
                        $cj.mcpServers | Add-Member -NotePropertyName $sProp.Name -NotePropertyValue $sProp.Value
                        $added += $sProp.Name
                    }
                }
                # Only write when something was actually added. The public kit ships an EMPTY
                # template, so this path is normally a no-op - and an unconditional write would
                # round-trip the user's whole .claude.json through PS 5.1's JSON serializer
                # (escaping non-ASCII, reformatting) for no gain. Matches fable-merge.js, which
                # leaves a no-change target byte-untouched.
                if ($added.Count -gt 0) {
                    Write-Utf8NoBom $claudeJson (ConvertTo-Json -InputObject $cj -Depth 64)
                    $mcpResult = "ADDED:$($added -join ',') (via powershell)"
                } elseif (-not (Test-Path -LiteralPath $claudeJson)) {
                    Write-Utf8NoBom $claudeJson (ConvertTo-Json -InputObject $cj -Depth 64)
                    $mcpResult = 'NOCHANGE (created empty) (via powershell)'
                } else {
                    $mcpResult = 'NOCHANGE (no write) (via powershell)'
                }
            } catch {
                Write-Note "PowerShell mcp merge failed: $($_.Exception.Message)"
                Write-Note "register manually later, e.g.:  claude mcp add --scope user <name> <command>"
            }
        }
        if ($mcpResult -ne '') {
            Write-Ok $mcpResult
            Add-Result 'mcp servers' 'PASS' $mcpResult
            $tplRaw = Get-Content $tplPath -Raw -Encoding UTF8
            if ($tplRaw -match '<<SET-ME>>') { Write-Note "template contains <<SET-ME>> placeholders - edit $claudeJson and fill real values" }
            try {
                $tplObj = ($tplRaw.Replace('<<HOME>>', $TargetHome.Replace('\', '\\'))) | ConvertFrom-Json
                foreach ($sProp in $tplObj.mcpServers.PSObject.Properties) {
                    $cmd = $sProp.Value.command
                    if ($cmd -and -not (Test-Path $cmd)) {
                        Write-Note "'$($sProp.Name)' points at $cmd which is NOT installed yet - reinstall that app, then the server connects"
                    }
                }
            } catch { }
        } else {
            Add-Result 'mcp servers' 'WARN' 'merge failed - manual claude mcp add needed (see log)'
        }
      } catch {
        Write-Note "mcp step failed: $($_.Exception.Message)"
        Add-Result 'mcp servers' 'WARN' "unexpected error - register manually with claude mcp add ($($_.Exception.Message))"
      }
    }

    # ------------------------------------------------------------- 8. verify
    Write-Step "8/9 Post-install verification"
    $failCount = 0
    foreach ($f in $manifest.files) {
        try {
            $p = $f.path
            $isClaude = $p -like 'claude-home\*'
            $isMemory = $p -like 'memory\*'
            if (-not ($isClaude -or $isMemory)) { continue }           # kit-only files (installer, docs, tools)
            if ($p -ieq 'claude-home\settings.json') { continue }      # semantic check already recorded
            if ($isMemory -and $memSkipped) { continue }               # memory step already reported WARN/FAIL
            if ($isClaude) { $dest = Join-Path $DestClaude ($p.Substring(12)) }
            else { $dest = Join-Path $memDest ($p.Substring(7)) }
            if (-not (Test-Path -LiteralPath $dest)) { Add-Result "file $p" 'FAIL' 'missing at destination'; $failCount++; continue }
            if ($isMemory -and -not $ForceMemory) { continue }         # kept-existing memory may legitimately differ
            if ((Get-Sha $dest) -ne $f.sha256) { Add-Result "file $p" 'FAIL' 'destination hash differs'; $failCount++ }
        } catch { Add-Result "file $($f.path)" 'FAIL' $_.Exception.Message; $failCount++ }
    }
    if ($failCount -eq 0) { Write-Ok "all installed files verified against manifest" }
    # organization: files inside kit-owned folders (each skills\<x> and
    # scheduled-tasks\<x> this kit ships - derived from the manifest, never
    # hardcoded) that this kit does not ship are reported and KEPT - they may be
    # the user's local additions; files a PREVIOUS kit install left behind were
    # already removed by the upgrade-hygiene step
    try {
        $kitFileSet = @{}
        foreach ($f in $manifest.files) { $kitFileSet[$f.path.ToLower()] = $true }
        $ownedRoots = @{}
        foreach ($f in $manifest.files) {
            if ($f.path -match '^claude-home\\(skills|scheduled-tasks)\\([^\\]+)\\') { $ownedRoots[($Matches[1] + '\' + $Matches[2])] = $true }
        }
        foreach ($sd in ($ownedRoots.Keys | Sort-Object)) {
            $sroot = Join-Path $DestClaude $sd
            if (-not (Test-Path -LiteralPath $sroot)) { continue }
            foreach ($sf in (Get-ChildItem -LiteralPath $sroot -Recurse -File)) {
                $rel = 'claude-home\' + $sd + '\' + $sf.FullName.Substring($sroot.Length + 1)
                if (-not $kitFileSet.ContainsKey($rel.ToLower())) { Write-Note "not part of this kit (kept): $rel" }
            }
        }
    } catch { }
    $anyFail = @($script:Results | Where-Object { $_.Result -eq 'FAIL' }).Count

    # -------------------------------------------------------------- 9. report
    Write-Step "9/9 Result"
    $script:Results | Select-Object Check, Result, Detail | Format-Table -AutoSize | Out-String | Write-Host
    if ($script:BackupCount -gt 0) { Write-Note "$script:BackupCount file(s) backed up under $BackupRoot" }
    # backups housekeeping: always report; interactively (and only after a FAIL-free
    # install) offer to prune backups older than 30 days, keeping the newest 3.
    # Default is No - backups are recovery copies; closed stdin keeps everything.
    try {
        $baks = @(Get-ChildItem $DestClaude -Filter 'fable-install-backup-*' -Directory -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending)
        if ($baks.Count -gt 0) {
            $bakBytes = 0
            foreach ($b in $baks) { foreach ($bf in (Get-ChildItem -LiteralPath $b.FullName -Recurse -File)) { $bakBytes += $bf.Length } }
            Write-Note "$($baks.Count) install-backup folder(s) under .claude ($([math]::Round($bakBytes/1KB)) KB) - recovery copies from previous installs"
            $oldBaks = @($baks | Select-Object -Skip 3 | Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-30) })
            if (-not $Unattended -and $oldBaks.Count -gt 0 -and $anyFail -eq 0) {
                $ansB = Read-Host "  Delete $($oldBaks.Count) backup folder(s) older than 30 days (the 3 newest are always kept)? [y/N]"
                if ($ansB -match '^[Yy]') {
                    $prunedB = 0
                    foreach ($ob in $oldBaks) { try { Remove-Item -LiteralPath $ob.FullName -Recurse -Force; $prunedB++ } catch { Write-Note "could not remove: $($ob.Name)" } }
                    Write-Ok "$prunedB old backup folder(s) removed"
                }
            }
        }
    } catch { }

    Write-Host ""
    Write-Host "  NEXT STEPS (in order)" -ForegroundColor Cyan
    Write-Host "   1. If Claude Code was just installed: open a NEW terminal, run 'claude', log in."
    Write-Host "      (Credentials are never in this kit - .credentials.json is recreated at login.)"
    Write-Host "   2. Open a Claude Code session anywhere and run the 2-minute check:"
    Write-Host "        /fable-mode loads - 'any standing orders?' cites the SessionStart order -"
    Write-Host "        'refactor the auth module' shows the classifier line -"
    Write-Host "        a spawned subagent reports the verify-before-reporting order."
    Write-Host "   3. Plugins: the official marketplace usually auto-installs on first run;"
    Write-Host "      plugins-snapshot.json in this kit lists the marketplaces + plugins recorded"
    Write-Host "      at kit-build time (marketplace plugins: /plugin install <name>@<marketplace>)."
    Write-Host "   4. Scheduled task: the health-check PROMPT file is installed, but the schedule"
    Write-Host "      itself lives in the app and must be re-created once. Tell Claude:"
    Write-Host "        'Create a monthly scheduled task named fable-health-check, 1st of the"
    Write-Host "         month at 09:00, using the prompt file at"
    Write-Host "         .claude\scheduled-tasks\fable-health-check\SKILL.md'"
    Write-Host "      then click 'Run now' once so its tool permissions get pre-approved."
    Write-Host "   5. If an MCP server from your template shows disconnected: reinstall the app"
    Write-Host "      its command points at, then restart Claude Code."
    Write-Host "   6. Keep a copy of FableSetup.exe (or this repo) OFF this machine - a backup"
    Write-Host "      on C:\ dies with C:\."
    Write-Host ""

    if ($anyFail -gt 0) { Write-Host "  COMPLETED WITH FAILURES - see table above." -ForegroundColor Red; exit 1 }
    $warnCount = @($script:Results | Where-Object { $_.Result -eq 'WARN' }).Count
    if ($warnCount -gt 0) { Write-Host "  INSTALL PASSED with $warnCount warning(s) - review the table above." -ForegroundColor Yellow }
    else { Write-Host "  INSTALL PASSED." -ForegroundColor Green }
    exit 0
}
finally {
    if ($log) {
        try { Stop-Transcript | Out-Null } catch { }
        Write-Host "  Log: $log"
    }
}
