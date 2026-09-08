@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ============================================================
rem HA Phone Dialer - upgrade.cmd
rem Version 1.02
rem Self-refreshing bootstrap: always runs the newest updater from GitHub.
rem Local private/untracked files are preserved; tracked source changes abort safely.
rem ============================================================

set "REPO_URL=https://github.com/Suenee/chrome-extension-ha-phone-dialer.git"
set "RAW_UPGRADE=https://raw.githubusercontent.com/Suenee/chrome-extension-ha-phone-dialer/main/upgrade.cmd"
set "FOLDER_NAME=chrome-extension-ha-phone-dialer"

rem ------------------------------------------------------------
rem Bootstrap mode.
rem Download the authoritative updater to TEMP and execute it.
rem This allows upgrade.cmd to update itself without running a stale copy.
rem ------------------------------------------------------------
if /I not "%~1"=="--worker" (
    set "BOOTSTRAP=%TEMP%\ha-phone-dialer-upgrade-%RANDOM%-%RANDOM%.cmd"

    echo.
    echo HA Phone Dialer updater bootstrap
    echo Downloading latest upgrade.cmd...

    where curl >nul 2>&1
    if errorlevel 1 (
        echo ERROR: curl is not available.
        exit /b 1
    )

    curl.exe -fL --retry 3 --connect-timeout 15 -o "%BOOTSTRAP%" "%RAW_UPGRADE%"
    if errorlevel 1 (
        echo ERROR: Cannot download the latest upgrade.cmd.
        del /q "%BOOTSTRAP%" >nul 2>&1
        exit /b 1
    )

    if not exist "%BOOTSTRAP%" (
        echo ERROR: Downloaded updater is missing.
        exit /b 1
    )

    call "%BOOTSTRAP%" --worker
    set "RC=%ERRORLEVEL%"
    del /q "%BOOTSTRAP%" >nul 2>&1
    exit /b %RC%
)

rem ------------------------------------------------------------
rem Worker mode starts here. This code is always the newest copy
rem downloaded from the main branch.
rem ------------------------------------------------------------
set "TARGET_ROOT="
set "TARGET_DIR="
set "CURRENT_BRANCH=main"
set "OLD_SHA="
set "REMOTE_SHA="
set "EXT_VERSION="

rem ------------------------------------------------------------
rem Detect workspace.
rem Prefer an already existing repository on D: or N:.
rem Otherwise prefer an existing WORK\GitHub root, then D:, then N:.
rem ------------------------------------------------------------
if exist "D:\WORK\GitHub\%FOLDER_NAME%\.git" set "TARGET_ROOT=D:\WORK\GitHub"
if not defined TARGET_ROOT if exist "N:\WORK\GitHub\%FOLDER_NAME%\.git" set "TARGET_ROOT=N:\WORK\GitHub"
if not defined TARGET_ROOT if exist "D:\WORK\GitHub" set "TARGET_ROOT=D:\WORK\GitHub"
if not defined TARGET_ROOT if exist "N:\WORK\GitHub" set "TARGET_ROOT=N:\WORK\GitHub"
if not defined TARGET_ROOT if exist "D:\" set "TARGET_ROOT=D:\WORK\GitHub"
if not defined TARGET_ROOT if exist "N:\" set "TARGET_ROOT=N:\WORK\GitHub"

if not defined TARGET_ROOT (
    echo ERROR: Neither D: nor N: is available.
    exit /b 1
)

set "TARGET_DIR=%TARGET_ROOT%\%FOLDER_NAME%"

echo.
echo HA Phone Dialer updater 1.02
echo Target: %TARGET_DIR%
echo.

rem ------------------------------------------------------------
rem Required tools.
rem ------------------------------------------------------------
where git >nul 2>&1
if errorlevel 1 (
    echo ERROR: Git is not installed or not available in PATH.
    exit /b 1
)

if not exist "%TARGET_ROOT%" (
    mkdir "%TARGET_ROOT%" >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Cannot create %TARGET_ROOT%
        exit /b 1
    )
)

rem ------------------------------------------------------------
rem First installation.
rem ------------------------------------------------------------
if not exist "%TARGET_DIR%\.git" (
    if exist "%TARGET_DIR%" (
        echo ERROR: Target directory exists but is not a Git repository:
        echo %TARGET_DIR%
        echo Move or remove it first. Nothing was overwritten.
        exit /b 1
    )

    echo Repository not found locally. Cloning...
    git clone "%REPO_URL%" "%TARGET_DIR%"
    if errorlevel 1 (
        echo ERROR: Clone failed.
        exit /b 1
    )

    echo.
    echo Installation completed.
    echo Repository: %TARGET_DIR%
    echo.
    echo For the first Chrome installation:
    echo   1. Open chrome://extensions
    echo   2. Enable Developer mode
    echo   3. Choose Load unpacked
    echo   4. Select %TARGET_DIR%
    echo.
    start "" chrome "chrome://extensions/"
    exit /b 0
)

pushd "%TARGET_DIR%"
if errorlevel 1 (
    echo ERROR: Cannot enter %TARGET_DIR%
    exit /b 1
)

rem ------------------------------------------------------------
rem Verify repository identity.
rem ------------------------------------------------------------
for /f "delims=" %%U in ('git remote get-url origin 2^>nul') do set "ORIGIN_URL=%%U"
if not defined ORIGIN_URL (
    echo ERROR: Git origin is missing.
    popd
    exit /b 1
)

rem ------------------------------------------------------------
rem The local upgrade.cmd is allowed to differ because it is only
rem a bootstrap. All other tracked local modifications abort update.
rem ------------------------------------------------------------
git update-index -q --refresh >nul 2>&1
for /f "delims=" %%F in ('git diff --name-only') do (
    if /I not "%%F"=="upgrade.cmd" (
        echo ERROR: Tracked local changes detected: %%F
        echo Commit, stash, or revert source changes before upgrading.
        popd
        exit /b 1
    )
)

for /f "delims=" %%F in ('git diff --cached --name-only') do (
    echo ERROR: Staged local changes detected: %%F
    echo Commit or unstage them before upgrading.
    popd
    exit /b 1
)

rem ------------------------------------------------------------
rem Save current revision for rollback and fetch remote state.
rem ------------------------------------------------------------
for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set "OLD_SHA=%%S"
if not defined OLD_SHA (
    echo ERROR: Cannot determine current Git revision.
    popd
    exit /b 1
)

for /f "delims=" %%B in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set "CURRENT_BRANCH=%%B"
if /I "%CURRENT_BRANCH%"=="HEAD" set "CURRENT_BRANCH=main"

echo Current branch: %CURRENT_BRANCH%
echo Fetching latest version...
git fetch --prune origin
if errorlevel 1 (
    echo ERROR: git fetch failed. Local files were not changed.
    popd
    exit /b 1
)

git show-ref --verify --quiet "refs/remotes/origin/%CURRENT_BRANCH%"
if errorlevel 1 (
    echo ERROR: Remote branch origin/%CURRENT_BRANCH% does not exist.
    popd
    exit /b 1
)

for /f "delims=" %%S in ('git rev-parse "origin/%CURRENT_BRANCH%"') do set "REMOTE_SHA=%%S"

rem ------------------------------------------------------------
rem If only upgrade.cmd differs locally, restore its tracked copy.
rem The running worker is in TEMP, so this is safe.
rem ------------------------------------------------------------
git diff --quiet -- upgrade.cmd
if errorlevel 1 git restore --worktree -- upgrade.cmd >nul 2>&1

if /I "%OLD_SHA%"=="%REMOTE_SHA%" (
    echo Already up to date.
    echo Local private/untracked files were preserved.
    popd
    exit /b 0
)

rem ------------------------------------------------------------
rem Fast-forward only. Never rewrite divergent history silently.
rem ------------------------------------------------------------
echo Updating...
git merge --ff-only "origin/%CURRENT_BRANCH%"
if errorlevel 1 (
    echo ERROR: Fast-forward update failed.
    echo No forced reset was performed.
    popd
    exit /b 1
)

rem ------------------------------------------------------------
rem Basic repository integrity check. During documentation-only
rem bootstrap phase manifest.json may not exist yet. Once present,
rem validate its version without touching local secrets.
rem ------------------------------------------------------------
if exist "manifest.json" (
    for /f "delims=" %%V in ('powershell -NoProfile -Command "try {(Get-Content -Raw 'manifest.json' ^| ConvertFrom-Json).version} catch {exit 1}"') do set "EXT_VERSION=%%V"
    if not defined EXT_VERSION (
        echo ERROR: Invalid manifest.json after update.
        echo Rolling back tracked repository files to %OLD_SHA% ...
        git reset --hard "%OLD_SHA%" >nul 2>&1
        popd
        exit /b 1
    )
)

rem ------------------------------------------------------------
rem Success.
rem Untracked/private configuration is intentionally untouched.
rem ------------------------------------------------------------
echo.
echo Update completed successfully.
if defined EXT_VERSION echo Extension version: %EXT_VERSION%
echo Local private/untracked files were preserved.
echo.
echo Reload HA Phone Dialer in chrome://extensions
start "" chrome "chrome://extensions/"

popd
exit /b 0
