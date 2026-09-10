$ErrorActionPreference = 'Stop'

$Version = '1.07'
$Revision = '1.07-assets-icons-context-menu'
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
    param([Parameter(Mandatory=$true)][string]$Phase,[Parameter(Mandatory=$true)][string]$Exe,[Parameter(Mandatory=$true)][string[]]$ArgumentList)
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Exe @ArgumentList 2>&1 | ForEach-Object {
            $line = [string]$_
            if ($line -match '(?i)\b(error|failed|fatal)\b') { Write-Line $line Red }
            elseif ($line -match '(?i)\bwarning\b') { Write-Line $line Yellow }
            else { Write-Line $line Gray }
        }
        $rc = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    if ($rc -ne 0) { Fail $Phase ("$Exe failed with exit code $rc") }
}
function Test-Png([string]$Path,[int]$Width,[int]$Height) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $b = [IO.File]::ReadAllBytes($Path)
    if ($b.Length -lt 24) { return $false }
    $sig = @(137,80,78,71,13,10,26,10)
    for ($i=0; $i -lt 8; $i++) { if ($b[$i] -ne $sig[$i]) { return $false } }
    $w = ([int]$b[16] -shl 24) -bor ([int]$b[17] -shl 16) -bor ([int]$b[18] -shl 8) -bor [int]$b[19]
    $h = ([int]$b[20] -shl 24) -bor ([int]$b[21] -shl 16) -bor ([int]$b[22] -shl 8) -bor [int]$b[23]
    return ($w -eq $Width -and $h -eq $Height)
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
    if ($plainDirty -and -not $substantiveDirty -and -not $stagedDirty) { Info '[GIT] Tracked differences are line-ending-only; continuing safely.' }
    if ($substantiveDirty -or $stagedDirty) {
        & git status --porcelain=v1 --untracked-files=no 2>$null | ForEach-Object { Info ("[GIT] Dirty: $_") }
        Fail 'REPOSITORY' 'Tracked local changes outside upgrade.cmd/upgrade.ps1 detected. Commit or revert them before upgrade.'
    }

    Info '[REPOSITORY] Synchronizing tracked tree to origin/main...'
    Run-Native -Phase 'REPOSITORY' -Exe 'git.exe' -ArgumentList @('reset','--hard','origin/main')
    $head = (& git rev-parse HEAD).Trim()
    $remoteHead = (& git rev-parse origin/main).Trim()
    if (-not $head -or -not $remoteHead -or $head -ne $remoteHead) { Fail 'REPOSITORY' 'Local HEAD is not identical to origin/main after synchronization.' }
    Info ("[GIT] Synchronized commit: $head")

    $FailPhase = 'ASSETS'
    $soundSource = Join-Path $Repo 'success.wav.b64'
    $soundTarget = Join-Path $Repo 'success.wav'
    if (-not (Test-Path -LiteralPath $soundSource)) { Fail $FailPhase 'success.wav.b64 is missing.' }
    try {
        $encoded = [IO.File]::ReadAllText($soundSource).Trim()
        [IO.File]::WriteAllBytes($soundTarget, [Convert]::FromBase64String($encoded))
    } catch { Fail $FailPhase ("Could not restore success.wav: $($_.Exception.Message)") }
    $wav = [IO.File]::ReadAllBytes($soundTarget)
    if ($wav.Length -lt 12 -or [Text.Encoding]::ASCII.GetString($wav,0,4) -ne 'RIFF' -or [Text.Encoding]::ASCII.GetString($wav,8,4) -ne 'WAVE') { Fail $FailPhase 'Generated success.wav is invalid.' }
    Info ("[ASSETS] Restored success.wav ($($wav.Length) bytes).")

    $FailPhase = 'VERIFY'
    Info '[VERIFY] Validating manifest.json and extension assets...'
    $manifestPath = Join-Path $Repo 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { Fail $FailPhase 'manifest.json is missing.' }
    try { $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json } catch { Fail $FailPhase ("manifest.json is invalid JSON: $($_.Exception.Message)") }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.version)) { Fail $FailPhase 'manifest.json does not contain a valid version.' }

    foreach ($name in @('background.js','content.js','offscreen.html','offscreen.js','success.wav')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Repo $name))) { Fail $FailPhase ("Required file is missing: $name") }
    }
    foreach ($spec in @(@('icon16.png',16),@('icon32.png',32),@('icon48.png',48),@('icon128.png',128))) {
        $p = Join-Path $Repo $spec[0]
        if (-not (Test-Png $p $spec[1] $spec[1])) { Fail $FailPhase ("Invalid PNG icon or dimensions: $($spec[0]) (expected $($spec[1])x$($spec[1]))") }
    }
    Info ("[VERIFY] Extension version: $($manifest.version)")
    Info '[VERIFY] Icons, sound and required extension files are valid.'

    Info ''
    Info '============================================================'
    if ($HadWarning) { Write-Line 'STATUS: WARNING - phase=COMPLETE' Yellow } else { Write-Line 'STATUS: SUCCESS - phase=COMPLETE' Green }
    Write-Line ("Extension version: $($manifest.version)") Green
    Write-Line ("Repository: $Repo") Green
    Write-Line 'ACTION REQUIRED: Reload HA Phone Dialer in chrome://extensions' Yellow
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
