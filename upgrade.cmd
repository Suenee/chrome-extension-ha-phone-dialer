@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem HA Phone Dialer - upgrade.cmd
rem Version 1.01
rem Use repository-matching local folder name on D:\ or N:\ WORK\GitHub.
rem Downloads or updates the repository and preserves local secrets.
rem ============================================================

set "REPO_URL=https://github.com/Suenee/chrome-extension-ha-phone-dialer.git"
set "FOLDER_NAME=chrome-extension-ha-phone-dialer"
set "TARGET_ROOT="
set "TARGET_DIR="
set "SCRIPT_DIR=%~dp0"

rem ------------------------------------------------------------
rem Detect preferred local workspace drive.
rem Priority: current D:/N: repository location, then existing root,
rem then D:, then N:.
rem ------------------------------------------------------------
for %%D in (D N) do (
    if /I "%CD%"=="%%D:\WORK\GitHub\%FOLDER_NAME%" set "TARGET_ROOT=%%D:\WORK\GitHub"
)

if not defined TARGET_ROOT (
    if exist "D:\WORK\GitHub" set "TARGET_ROOT=D:\WORK\GitHub"
)

if not defined TARGET_ROOT (
    if exist "N:\WORK\GitHub" set "TARGET_ROOT=N:\WORK\GitHub"
)

if not defined TARGET_ROOT (
    if exist "D:\" set "TARGET_ROOT=D:\WORK\GitHub"
)

if not defined TARGET_ROOT (
    if exist "N:\" set "TARGET_ROOT=N:\WORK\GitHub"
)

if not defined TARGET_ROOT (
    echo ERROR: Neither D: nor N: is available.
    exit /b 1
)

set "TARGET_DIR=%TARGET_ROOT%\%FOLDER_NAME%"

echo.
echo HA Phone Dialer updater
echo Target: %TARGET_DIR%
echo.

rem ------------------------------------------------------------
rem Check Git availability.
rem ------------------------------------------------------------
where git >nul 2>&1
if errorlevel 1 (
    echo ERROR: Git is not installed or not available in PATH.
    echo Install Git for Windows and run this script again.
    exit /b 1
)

rem ------------------------------------------------------------
rem Ensure workspace exists.
rem ------------------------------------------------------------
if not exist "%TARGET_ROOT%" (
    mkdir "%TARGET_ROOT%" >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Cannot create %TARGET_ROOT%
        exit /b 1
    )
)

rem ------------------------------------------------------------
rem First installation: clone repository.
rem ------------------------------------------------------------
if not exist "%TARGET_DIR%\.git" (
    echo Repository not found locally. Cloning...
    git clone "%REPO_URL%" "%TARGET_DIR%"
    if errorlevel 1 (
        echo ERROR: Clone failed.
        exit /b 1
    )

    echo.
    echo Installation completed.
    echo Open chrome://extensions
    echo Enable Developer mode and choose Load unpacked.
    echo Select: %TARGET_DIR%
    echo.
    start "" chrome "chrome://extensions/"
    exit /b 0
)

rem ------------------------------------------------------------
rem Existing installation: verify repository state.
rem Local uncommitted files are preserved. Tracked local changes
rem stop the upgrade so nothing is overwritten silently.
rem ------------------------------------------------------------
pushd "%TARGET_DIR%"
if errorlevel 1 (
    echo ERROR: Cannot enter %TARGET_DIR%
    exit /b 1
)

for /f "delims=" %%B in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set "CURRENT_BRANCH=%%B"
if not defined CURRENT_BRANCH set "CURRENT_BRANCH=main"

git update-index -q --refresh >nul 2>&1
git diff --quiet
if errorlevel 1 (
    echo ERROR: Tracked files contain local changes.
    echo Commit, stash, or revert them before running upgrade.cmd.
    popd
    exit /b 1
)

git diff --cached --quiet
if errorlevel 1 (
    echo ERROR: Staged changes are present.
    echo Commit or unstage them before running upgrade.cmd.
    popd
    exit /b 1
)

rem ------------------------------------------------------------
rem Remember current commit for rollback.
rem ------------------------------------------------------------
for /f "delims=" %%S in ('git rev-parse HEAD') do set "OLD_SHA=%%S"

echo Current branch: %CURRENT_BRANCH%
echo Fetching latest version...

git fetch origin
if errorlevel 1 (
    echo ERROR: git fetch failed.
    popd
    exit /b 1
)

rem ------------------------------------------------------------
rem Ensure remote branch exists.
rem ------------------------------------------------------------
git show-ref --verify --quiet "refs/remotes/origin/%CURRENT_BRANCH%"
if errorlevel 1 (
    echo ERROR: Remote branch origin/%CURRENT_BRANCH% does not exist.
    popd
    exit /b 1
)

for /f "delims=" %%S in ('git rev-parse "origin/%CURRENT_BRANCH%"') do set "REMOTE_SHA=%%S"

if /I "%OLD_SHA%"=="%REMOTE_SHA%" (
    echo Already up to date.
    popd
    exit /b 0
)

rem ------------------------------------------------------------
rem Fast-forward only. If history diverged, abort safely.
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
rem Basic integrity check.
rem ------------------------------------------------------------
if not exist "manifest.json" (
    echo ERROR: manifest.json is missing after update.
    echo Rolling back to %OLD_SHA% ...
    git reset --hard "%OLD_SHA%" >nul 2>&1
    popd
    exit /b 1
)

for /f "delims=" %%V in ('powershell -NoProfile -Command "try {(Get-Content -Raw 'manifest.json' ^| ConvertFrom-Json).version} catch {exit 1}"') do set "EXT_VERSION=%%V"
if not defined EXT_VERSION (
    echo ERROR: Invalid manifest.json after update.
    echo Rolling back to %OLD_SHA% ...
    git reset --hard "%OLD_SHA%" >nul 2>&1
    popd
    exit /b 1
)

echo.
echo Update completed successfully.
echo Extension version: %EXT_VERSION%
echo Local untracked/private files were preserved.
echo.
echo Reload HA Phone Dialer in chrome://extensions
start "" chrome "chrome://extensions/"

popd
exit /b 0
