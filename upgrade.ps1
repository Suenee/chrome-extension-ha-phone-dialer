$ErrorActionPreference = 'Stop'

$Version = '1.05'
$Revision = '1.05-folderheatmap-protocol'
$Repo = $env:HAPD_UPGRADE_REPO
if ([string]::IsNullOrWhiteSpace($Repo)) { $Repo = (Get-Location).ProviderPath }
$Repo = [IO.Path]::GetFullPath($Repo).TrimEnd('\')
$LogsDir = Join-Path $Repo 'logs'
New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
$Log = Join-Path $LogsDir 'upgrade.log'
$HadWarning = $false
$FailPhase = 'UNKNOWN'

$Utf8 = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $Utf8
$OutputEncoding = $Utf8
try { & chcp.com 65001 *> $null } catch { }
[IO.File]::WriteAllText($Log, '', $Utf8)

function Write-Line([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::Gray) {
    [IO.File]::AppendAllText($Log, $Text + [Environment]::NewLine, $Utf8)
    Write-Host $Text -ForegroundColor $Color
}
function Info([string]$Text) { Write-Line $Text Gray }
function Warn([string]$Text) { $script:HadWarning = $true; Write-Line ('WARNING: ' + $Text) Yellow }
function Fail([string]$Phase, [string]$Text) {
    $script:FailPhase = $Phase
    Write-Line ('ERROR: ' + $Text) Red
    throw [InvalidOperationException]::new($Text)
}
function Run-Native {
    param(
        [Parameter(Mandatory=$true)][string]$Phase,
        [Parameter(Mandatory=$true)][string]$Exe,
        [Parameter(Mandatory=$true)][string[]]$ArgumentList,
        [switch]$SuppressOutput
    )
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Exe @ArgumentList 2>&1 | ForEach-Object {
            if ($SuppressOutput) { return }
            $line = [string]$_
            if ($line -match '(?i)\b(error|failed|fatal)\b') { Write-Line $line Red }
            elseif ($line -match '(?i)\bwarning\b') { Write-Line $line Yellow }
            else { Write-Line $line Gray }
        }
        $rc = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedPreference
    }
    if ($rc -ne 0) { Fail $Phase ("$Exe failed with exit code $rc") }
}

try {
    Set-Location $Repo

    Info '============================================================'
    Info 'HA Phone Dialer upgrade diagnostic log'
    Info ("Updater:    $Revision")
    Info ('Started:    ' + [DateTime]::Now.ToString('dd.MM.yyyy HH:mm:ss.fff'))
    Info ("Repository: $Repo")
    $startBranch = (& git branch --show-current 2>$null).Trim()
    $startCommit = (& git rev-parse HEAD 2>$null).Trim()
    Info ("Branch:     $startBranch")
    Info ("Commit:     $startCommit")
    Info 'Runner:     temporary origin/main upgrade.ps1; upgrade.cmd is launcher only'
    Info '============================================================'

    $FailPhase = 'SELF-UPDATE'
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { Fail $FailPhase 'Git was not found in PATH.' }

    Info '[SELF-UPDATE] Fetching origin/main...'
    Run-Native -Phase $FailPhase -Exe 'git.exe' -ArgumentList @('fetch','--prune','origin','main')

    $currentBranch = (& git branch --show-current).Trim()
    if ($currentBranch -ne 'main') {
        Info '[REPOSITORY] Switching to main...'
        Run-Native -Phase 'REPOSITORY' -Exe 'git.exe' -ArgumentList @('switch','main')
    }

    & git diff --quiet --ignore-submodules -- . ':(exclude)upgrade.cmd' ':(exclude)upgrade.ps1'
    $plainDirty = ($LASTEXITCODE -ne 0)
    & git diff --quiet --ignore-space-at-eol --ignore-submodules -- . ':(exclude)upgrade.cmd' ':(exclude)upgrade.ps1'
    $substantiveDirty = ($LASTEXITCODE -ne 0)
    & git diff --cached --quiet --ignore-submodules -- . ':(exclude)upgrade.cmd' ':(exclude)upgrade.ps1'
    $stagedDirty = ($LASTEXITCODE -ne 0)

    if ($plainDirty -and -not $substantiveDirty -and -not $stagedDirty) {
        Info '[GIT] Tracked differences are line-ending-only; continuing safely.'
    }
    if ($substantiveDirty -or $stagedDirty) {
        & git status --porcelain=v1 --untracked-files=no 2>$null | ForEach-Object { Info ("[GIT] Dirty: $_") }
        Fail 'REPOSITORY' 'Tracked local changes outside upgrade.cmd/upgrade.ps1 detected. Commit or revert them before upgrade.'
    }

    Info '[REPOSITORY] Synchronizing tracked tree to origin/main...'
    Run-Native -Phase 'REPOSITORY' -Exe 'git.exe' -ArgumentList @('reset','--hard','origin/main')

    $head = (& git rev-parse HEAD).Trim()
    $remoteHead = (& git rev-parse origin/main).Trim()
    if (-not $head -or -not $remoteHead -or $head -ne $remoteHead) {
        Fail 'REPOSITORY' 'Local HEAD is not identical to origin/main after synchronization.'
    }
    Info ("[GIT] Synchronized commit: $head")

    $FailPhase = 'VERIFY'
    Info '[VERIFY] Validating manifest.json...'
    $manifestPath = Join-Path $Repo 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { Fail $FailPhase 'manifest.json is missing.' }
    try {
        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    } catch {
        Fail $FailPhase ("manifest.json is invalid JSON: $($_.Exception.Message)")
    }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.version)) { Fail $FailPhase 'manifest.json does not contain a valid version.' }

    $required = @(
        'background.js',
        'content.js',
        'offscreen.html',
        'offscreen.js',
        'icon16.png',
        'icon32.png',
        'icon48.png',
        'icon128.png',
        'success.wav'
    )
    foreach ($name in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $Repo $name))) { Fail $FailPhase ("Required file is missing: $name") }
    }

    Info ("[VERIFY] Extension version: $($manifest.version)")
    Info '[VERIFY] Required extension files are present.'

    Info ''
    Info '============================================================'
    if ($HadWarning) {
        Write-Line 'STATUS: WARNING - phase=COMPLETE' Yellow
    } else {
        Write-Line 'STATUS: SUCCESS - phase=COMPLETE' Green
    }
    Write-Line ("Extension version: $($manifest.version)") Green
    Write-Line ("Repository: $Repo") Green
    Write-Line 'Reload HA Phone Dialer in chrome://extensions' Green
    Info '============================================================'

    try { Start-Process 'chrome.exe' 'chrome://extensions/' | Out-Null } catch { Warn 'Could not open chrome://extensions automatically.' }
    exit 0
}
catch {
    Write-Line '' Gray
    Write-Line ("STATUS: FAILED - phase=$FailPhase") Red
    Write-Line ("Upgrade log: $Log") Red
    exit 1
}
