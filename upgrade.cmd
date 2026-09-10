@echo off
cls
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem HA Phone Dialer - upgrade.cmd
rem Version 1.07
rem Aktualizace assetu, ikon a validace kontextove nabidky.
rem Launcher + docasny aktualni upgrade.ps1 podle FolderHeatMap standardu.
rem ============================================================

set "UPGRADE_REV=1.07-bootstrap-runner"
set "REPO_URL=https://github.com/Suenee/chrome-extension-ha-phone-dialer.git"
set "TARGET_BRANCH=main"

if /I "%~1"=="--bootstrap-internal" goto :bootstrap_internal

set "REPO_DIR=%~dp0"
if "!REPO_DIR:~-1!"=="\" set "REPO_DIR=!REPO_DIR:~0,-1!"

powershell.exe -NoProfile -Command "Write-Host 'HA Phone Dialer upgrade %UPGRADE_REV%' -ForegroundColor Cyan"
powershell.exe -NoProfile -Command "Write-Host 'Repository: %REPO_DIR%' -ForegroundColor DarkGray"
echo.

where git.exe >nul 2>nul
if errorlevel 1 (
    powershell.exe -NoProfile -Command "Write-Host 'ERROR: Git was not found in PATH.' -ForegroundColor Red"
    exit /b 1
)

pushd "!REPO_DIR!"
if errorlevel 1 (
    powershell.exe -NoProfile -Command "Write-Host 'ERROR: Cannot enter repository directory.' -ForegroundColor Red"
    exit /b 1
)

call :detect_git_repository
if "!GIT_REPO_STATE!"=="1" goto :repository_ready
if "!GIT_REPO_STATE!"=="2" (
    popd
    exit /b 1
)
goto :bootstrap

:repository_ready
if not exist "!REPO_DIR!\logs" mkdir "!REPO_DIR!\logs" >nul 2>nul

powershell.exe -NoProfile -Command "Write-Host '[SELF-UPDATE] Fetching authoritative updater from origin/%TARGET_BRANCH%...' -ForegroundColor Cyan"
git fetch --prune origin %TARGET_BRANCH% >nul 2> "!REPO_DIR!\logs\upgrade-bootstrap-error.log"
if errorlevel 1 (
    powershell.exe -NoProfile -Command "Write-Host 'ERROR: git fetch failed before updater bootstrap.' -ForegroundColor Red"
    > "!REPO_DIR!\logs\upgrade.log" echo STATUS: FAILED - phase=SELF-UPDATE/BOOTSTRAP
    popd
    exit /b 1
)

set "RUNNER_TEMP=%TEMP%\HA-Phone-Dialer-upgrade-%RANDOM%-%RANDOM%.ps1"
git show origin/%TARGET_BRANCH%:upgrade.ps1 > "!RUNNER_TEMP!" 2>nul
if errorlevel 1 (
    powershell.exe -NoProfile -Command "Write-Host 'ERROR: Could not extract origin/%TARGET_BRANCH%:upgrade.ps1.' -ForegroundColor Red"
    > "!REPO_DIR!\logs\upgrade.log" echo STATUS: FAILED - phase=SELF-UPDATE/BOOTSTRAP
    popd
    exit /b 1
)

set "HAPD_UPGRADE_REPO=!REPO_DIR!"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!RUNNER_TEMP!"
set "UPGRADE_RC=!ERRORLEVEL!"
del /q "!RUNNER_TEMP!" >nul 2>nul
set "HAPD_UPGRADE_REPO="
popd
exit /b !UPGRADE_RC!

:detect_git_repository
set "GIT_REPO_STATE=0"
set "GIT_DETECT_ERR=%TEMP%\HA-Phone-Dialer-git-detect-%RANDOM%-%RANDOM%.log"
git rev-parse --is-inside-work-tree >nul 2> "!GIT_DETECT_ERR!"
if not errorlevel 1 (
    del /q "!GIT_DETECT_ERR!" >nul 2>nul
    set "GIT_REPO_STATE=1"
    exit /b 0
)

findstr /I /C:"detected dubious ownership" "!GIT_DETECT_ERR!" >nul 2>nul
if errorlevel 1 (
    del /q "!GIT_DETECT_ERR!" >nul 2>nul
    set "GIT_REPO_STATE=0"
    exit /b 0
)

powershell.exe -NoProfile -Command "Write-Host 'Git marked this repository as dubious ownership. Registering this exact repository as safe.directory...' -ForegroundColor Yellow"
set "HAPD_GIT_DETECT_ERR=!GIT_DETECT_ERR!"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$text=[IO.File]::ReadAllText($env:HAPD_GIT_DETECT_ERR); $m=[regex]::Match($text, \"safe\.directory\s+'([^']+)'\"); if(-not $m.Success){ Write-Host 'ERROR: Git reported dubious ownership, but its safe.directory path could not be parsed.' -ForegroundColor Red; exit 3 }; $safe=$m.Groups[1].Value; & git.exe config --global --add safe.directory $safe; if($LASTEXITCODE -ne 0){ Write-Host ('ERROR: Could not register Git safe.directory: ' + $safe) -ForegroundColor Red; exit $LASTEXITCODE }; Write-Host ('Git safe.directory registered: ' + $safe) -ForegroundColor Green"
set "SAFE_RC=!ERRORLEVEL!"
del /q "!GIT_DETECT_ERR!" >nul 2>nul
set "HAPD_GIT_DETECT_ERR="
if not "!SAFE_RC!"=="0" (
    set "GIT_REPO_STATE=2"
    exit /b 0
)

git rev-parse --is-inside-work-tree >nul 2>nul
if errorlevel 1 (
    powershell.exe -NoProfile -Command "Write-Host 'ERROR: Repository is still rejected by Git after safe.directory registration.' -ForegroundColor Red"
    set "GIT_REPO_STATE=2"
    exit /b 0
)

set "GIT_REPO_STATE=1"
exit /b 0

:bootstrap
powershell.exe -NoProfile -Command "Write-Host 'Repository not found. Starting fresh bootstrap in the current directory...' -ForegroundColor Cyan"

set "BOOTSTRAP_EXTRA=0"
for /f "delims=" %%F in ('dir /b /a "!REPO_DIR!" 2^>nul') do (
    if /I not "%%F"=="upgrade.cmd" set "BOOTSTRAP_EXTRA=1"
)
if "!BOOTSTRAP_EXTRA!"=="1" (
    powershell.exe -NoProfile -Command "Write-Host 'ERROR: Bootstrap directory must contain only upgrade.cmd.' -ForegroundColor Red"
    popd
    exit /b 1
)

set "BOOTSTRAP_TEMP=%TEMP%\HA-Phone-Dialer-bootstrap-%RANDOM%-%RANDOM%.cmd"
copy /y "%~f0" "!BOOTSTRAP_TEMP!" >nul
if errorlevel 1 (
    powershell.exe -NoProfile -Command "Write-Host 'ERROR: Could not create temporary bootstrap runner.' -ForegroundColor Red"
    popd
    exit /b 1
)

popd
call "!BOOTSTRAP_TEMP!" --bootstrap-internal "!REPO_DIR!"
set "BOOTSTRAP_RC=!ERRORLEVEL!"
del /q "!BOOTSTRAP_TEMP!" >nul 2>nul
exit /b !BOOTSTRAP_RC!

:bootstrap_internal
set "BOOTSTRAP_TARGET=%~2"
if "!BOOTSTRAP_TARGET:~-1!"=="\" set "BOOTSTRAP_TARGET=!BOOTSTRAP_TARGET:~0,-1!"

powershell.exe -NoProfile -Command "Write-Host 'Cloning HA Phone Dialer into: !BOOTSTRAP_TARGET!' -ForegroundColor Cyan"

if not exist "!BOOTSTRAP_TARGET!" mkdir "!BOOTSTRAP_TARGET!" >nul 2>nul
if not exist "!BOOTSTRAP_TARGET!" (
    powershell.exe -NoProfile -Command "Write-Host 'ERROR: Could not create bootstrap target.' -ForegroundColor Red"
    exit /b 1
)

set "BOOTSTRAP_EXTRA=0"
for /f "delims=" %%F in ('dir /b /a "!BOOTSTRAP_TARGET!" 2^>nul') do (
    if /I not "%%F"=="upgrade.cmd" set "BOOTSTRAP_EXTRA=1"
)
if "!BOOTSTRAP_EXTRA!"=="1" (
    powershell.exe -NoProfile -Command "Write-Host 'ERROR: Bootstrap target must contain only upgrade.cmd.' -ForegroundColor Red"
    exit /b 1
)

del /q "!BOOTSTRAP_TARGET!\upgrade.cmd" >nul 2>nul
git clone --branch %TARGET_BRANCH% --single-branch "%REPO_URL%" "!BOOTSTRAP_TARGET!"
if errorlevel 1 (
    powershell.exe -NoProfile -Command "Write-Host 'ERROR: Git clone failed.' -ForegroundColor Red"
    exit /b 1
)

if not exist "!BOOTSTRAP_TARGET!\.git" (
    powershell.exe -NoProfile -Command "Write-Host 'ERROR: Clone completed, but .git is missing.' -ForegroundColor Red"
    exit /b 1
)
if not exist "!BOOTSTRAP_TARGET!\upgrade.cmd" (
    powershell.exe -NoProfile -Command "Write-Host 'ERROR: Clone completed, but upgrade.cmd is missing.' -ForegroundColor Red"
    exit /b 1
)

powershell.exe -NoProfile -Command "Write-Host 'Repository cloned successfully. Handing off to current upgrade.cmd...' -ForegroundColor Green"
call "!BOOTSTRAP_TARGET!\upgrade.cmd"
exit /b !ERRORLEVEL!
