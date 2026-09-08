@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ============================================================
rem HA Phone Dialer - upgrade.cmd
rem Version 1.04
rem Remove curl self-bootstrap and update directly with Git.
rem Fix execution from mapped network drives using safe.directory.
rem Private/untracked files are preserved.
rem ============================================================

set "REPO_URL=https://github.com/Suenee/chrome-extension-ha-phone-dialer.git"
set "FOLDER_NAME=chrome-extension-ha-phone-dialer"
set "TARGET_ROOT="
set "TARGET_DIR="
set "CURRENT_BRANCH=main"
set "OLD_SHA="
set "REMOTE_SHA="
set "EXT_VERSION="
set "SAFE_PATH="

rem ------------------------------------------------------------
rem Detect workspace. Prefer the current directory when the script
rem is launched directly from the repository on D: or N:.
rem ------------------------------------------------------------
for %%D in (D N) do (
    if /I "%CD%"=="%%D:\WORK\GitHub\%FOLDER_NAME%" set "TARGET_ROOT=%%D:\WORK\GitHub"
)
if not defined TARGET_ROOT if exist "D:\WORK\GitHub\%FOLDER_NAME%\.git" set "TARGET_ROOT=D:\WORK\GitHub"
if not defined TARGET_ROOT if exist "N:\WORK\GitHub\%FOLDER_NAME%\.git" set "TARGET_ROOT=N:\WORK\GitHub"
if not defined TARGET_ROOT if exist "D:\WORK\GitHub" set "TARGET_ROOT=D:\WORK\GitHub"
if not defined TARGET_ROOT if exist "N:\WORK\GitHub" set "TARGET_ROOT=N:\WORK\GitHub"

if not defined TARGET_ROOT (
    echo ERROR: Cannot locate D:\WORK\GitHub or N:\WORK\GitHub.
    exit /b 1
)

set "TARGET_DIR=%TARGET_ROOT%\%FOLDER_NAME%"

echo.
echo HA Phone Dialer updater 1.04
echo Target: %TARGET_DIR%
echo.

where git >nul 2>&1
if errorlevel 1 (
    echo ERROR: Git is not installed or not available in PATH.
    exit /b 1
)

rem ------------------------------------------------------------
rem Mark the actual repository path as safe before any repository
rem command. This is required when N: points to a NAS/UNC share.
rem Git itself resolves the mapped drive to its UNC path.
rem ------------------------------------------------------------
if exist "%TARGET_DIR%\.git" (
    for /f "delims=" %%P in ('git -C "%TARGET_DIR%" rev-parse --show-toplevel 2^>nul') do set "SAFE_PATH=%%P"
)

if not defined SAFE_PATH (
    for /f "tokens=2,*" %%A in ('net use %TARGET_ROOT:~0,2% 2^>nul ^| findstr /I "Remote name"') do set "SAFE_PATH=%%B\%FOLDER_NAME%"
)

if defined SAFE_PATH git config --global --add safe.directory "%SAFE_PATH%" >nul 2>&1

rem ------------------------------------------------------------
rem Repository must already be cloned. First installation is done
rem with: git clone <repo> .
rem ------------------------------------------------------------
if not exist "%TARGET_DIR%\.git" (
    echo ERROR: Repository is not cloned yet.
    echo.
    echo Open the target folder and run:
    echo   git clone %REPO_URL% .
    echo.
    exit /b 1
)

pushd "%TARGET_DIR%"
if errorlevel 1 (
    echo ERROR: Cannot enter %TARGET_DIR%
    exit /b 1
)

rem ------------------------------------------------------------
rem Local upgrade.cmd may differ because it is updater bootstrap.
rem Any other tracked local source modification aborts safely.
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
    if /I not "%%F"=="upgrade.cmd" (
        echo ERROR: Staged local changes detected: %%F
        echo Commit, unstage, or revert source changes before upgrading.
        popd
        exit /b 1
    )
)

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

rem Restore only the updater itself if it was locally modified.
git diff --quiet -- upgrade.cmd
if errorlevel 1 git restore --worktree -- upgrade.cmd >nul 2>&1

git diff --cached --quiet -- upgrade.cmd
if errorlevel 1 git restore --staged -- upgrade.cmd >nul 2>&1

if /I "%OLD_SHA%"=="%REMOTE_SHA%" (
    echo Already up to date.
    echo Local private/untracked files were preserved.
    popd
    exit /b 0
)

echo Updating...
git merge --ff-only "origin/%CURRENT_BRANCH%"
if errorlevel 1 (
    echo ERROR: Fast-forward update failed.
    echo No forced reset was performed.
    popd
    exit /b 1
)

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

echo.
echo Update completed successfully.
if defined EXT_VERSION echo Extension version: %EXT_VERSION%
echo Local private/untracked files were preserved.
echo.
echo Reload HA Phone Dialer in chrome://extensions
start "" chrome "chrome://extensions/"
popd
exit /b 0
