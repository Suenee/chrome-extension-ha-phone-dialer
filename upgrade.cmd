@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ============================================================
rem HA Phone Dialer - upgrade.cmd
rem Version 1.03
rem Fix first install when upgrade.cmd already exists in target folder.
rem Self-refreshing bootstrap; private/untracked files are preserved.
rem ============================================================

set "REPO_URL=https://github.com/Suenee/chrome-extension-ha-phone-dialer.git"
set "RAW_UPGRADE=https://raw.githubusercontent.com/Suenee/chrome-extension-ha-phone-dialer/main/upgrade.cmd"
set "FOLDER_NAME=chrome-extension-ha-phone-dialer"

rem ------------------------------------------------------------
rem Bootstrap mode.
rem Always download the authoritative updater to TEMP first.
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

    curl.exe -fsSL --retry 3 --connect-timeout 15 -o "%BOOTSTRAP%" "%RAW_UPGRADE%"
    if errorlevel 1 (
        echo ERROR: Cannot download the latest upgrade.cmd.
        del /q "%BOOTSTRAP%" >nul 2>&1
        exit /b 1
    )

    call "%BOOTSTRAP%" --worker
    set "RC=%ERRORLEVEL%"
    del /q "%BOOTSTRAP%" >nul 2>&1
    exit /b %RC%
)

set "TARGET_ROOT="
set "TARGET_DIR="
set "CURRENT_BRANCH=main"
set "OLD_SHA="
set "REMOTE_SHA="
set "EXT_VERSION="

rem ------------------------------------------------------------
rem Detect workspace. Prefer the directory from which upgrade.cmd
rem was launched when it is already under D:/N:/WORK/GitHub.
rem ------------------------------------------------------------
for %%D in (D N) do (
    if /I "%CD%"=="%%D:\WORK\GitHub\%FOLDER_NAME%" set "TARGET_ROOT=%%D:\WORK\GitHub"
)
if not defined TARGET_ROOT if exist "D:\WORK\GitHub\%FOLDER_NAME%\.git" set "TARGET_ROOT=D:\WORK\GitHub"
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
echo HA Phone Dialer updater 1.03
echo Target: %TARGET_DIR%
echo.

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
rem First installation into an empty or bootstrap-only directory.
rem The common case is exactly this: the user downloads upgrade.cmd
rem into the final folder and runs it there. Git clone cannot clone
rem into that non-empty folder, so initialize Git in place instead.
rem ------------------------------------------------------------
if not exist "%TARGET_DIR%\.git" (
    if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"

    rem Refuse to overwrite an arbitrary non-empty directory.
    for /f "delims=" %%F in ('dir /b /a "%TARGET_DIR%" 2^>nul') do (
        if /I not "%%F"=="upgrade.cmd" (
            echo ERROR: Target directory is not a Git repository and contains:
            echo   %%F
            echo Only bootstrap upgrade.cmd may exist before first installation.
            echo Nothing was overwritten.
            exit /b 1
        )
    )

    echo First installation into existing bootstrap folder...
    pushd "%TARGET_DIR%"
    if errorlevel 1 exit /b 1

    git init
    if errorlevel 1 goto :install_failed

    git remote add origin "%REPO_URL%"
    if errorlevel 1 goto :install_failed

    git fetch --prune origin main
    if errorlevel 1 goto :install_failed

    rem The running updater is in TEMP. Remove the downloaded bootstrap
    rem copy so Git can populate the tracked repository version cleanly.
    if exist "upgrade.cmd" del /q "upgrade.cmd"

    git checkout -B main --track origin/main
    if errorlevel 1 goto :install_failed

    popd

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
rem Local upgrade.cmd may differ because it is only a bootstrap.
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
    echo ERROR: Staged local changes detected: %%F
    echo Commit or unstage them before upgrading.
    popd
    exit /b 1
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

git diff --quiet -- upgrade.cmd
if errorlevel 1 git restore --worktree -- upgrade.cmd >nul 2>&1

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

:install_failed
set "RC=%ERRORLEVEL%"
echo.
echo ERROR: Initial Git installation failed.
echo Existing bootstrap files were not intentionally overwritten.
popd
exit /b %RC%
