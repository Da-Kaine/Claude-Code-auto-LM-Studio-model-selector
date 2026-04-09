@echo off
setlocal enabledelayedexpansion
title Claude Code + LM Studio Launcher

:: ============================================================
::  Claude Code  <->  LM Studio  Auto-Launcher
::  - Installs Node.js + Claude Code if missing
::  - Scans localhost AND full local subnet for LM Studio
::  - Lists loaded models and lets you pick one
:: ============================================================

echo.
echo  ================================================
echo   Claude Code ^<-^> LM Studio  Auto-Launcher
echo  ================================================
echo.

:: ─────────────────────────────────────────────────────────────
:: STEP 1 – Ensure winget is available
:: ─────────────────────────────────────────────────────────────
where winget >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] winget not found. Please update Windows or install
    echo     App Installer from the Microsoft Store, then re-run.
    pause
    exit /b 1
)

:: ─────────────────────────────────────────────────────────────
:: STEP 2 – Ensure Node.js (npm) is installed
:: ─────────────────────────────────────────────────────────────
where npm >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Node.js not found. Installing via winget...
    winget install OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements
    if !errorlevel! neq 0 (
        echo [ERROR] Node.js installation failed.
        echo         Install manually from https://nodejs.org/ then re-run.
        pause
        exit /b 1
    )

    :: Refresh PATH so npm is available in this session
    for /f "usebackq tokens=2*" %%A in (
        `reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul`
    ) do set "SYS_PATH=%%B"
    for /f "usebackq tokens=2*" %%A in (
        `reg query "HKCU\Environment" /v Path 2^>nul`
    ) do set "USR_PATH=%%B"
    set "PATH=!SYS_PATH!;!USR_PATH!"

    where npm >nul 2>&1
    if !errorlevel! neq 0 (
        echo [!] PATH not yet updated. Please close and re-open this
        echo     script after Node.js finishes installing.
        pause
        exit /b 1
    )
    echo [+] Node.js installed successfully.
) else (
    for /f "tokens=*" %%v in ('node --version 2^>nul') do echo [+] Node.js %%v already installed.
)

:: ─────────────────────────────────────────────────────────────
:: STEP 3 – Ensure Claude Code CLI is installed
:: ─────────────────────────────────────────────────────────────
where claude >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Claude Code CLI not found. Installing globally via npm...
    call npm install -g @anthropic-ai/claude-code
    if !errorlevel! neq 0 (
        echo [ERROR] Claude Code installation failed. Check npm permissions.
        pause
        exit /b 1
    )
    echo [+] Claude Code installed.
) else (
    for /f "tokens=*" %%v in ('claude --version 2^>nul') do echo [+] Claude Code %%v already installed.
)

:: ─────────────────────────────────────────────────────────────
:: STEP 4 – Set credentials for local LM Studio use
:: ─────────────────────────────────────────────────────────────
set "ANTHROPIC_AUTH_TOKEN="
set "ANTHROPIC_API_KEY=lm-studio"

:: ─────────────────────────────────────────────────────────────
:: STEP 5 – Discover LM Studio  (localhost -> subnet scan)
:: ─────────────────────────────────────────────────────────────
set "LMS_PORT=1234"
set "BASE_URL="

echo.
echo [*] Checking localhost:%LMS_PORT%...

powershell -NoProfile -Command ^
    "try{$null=Invoke-WebRequest -Uri 'http://localhost:%LMS_PORT%/v1/models' -TimeoutSec 2 -UseBasicParsing; exit 0}catch{exit 1}" >nul 2>&1

if %errorlevel% equ 0 (
    set "BASE_URL=http://localhost:%LMS_PORT%"
    echo [+] LM Studio found on localhost.
    goto :MODELS
)

echo [-] Not on localhost. Scanning local subnet(s)...
echo     (This may take up to 30 seconds)
echo.

:: Collect every non-loopback IPv4 address assigned to this machine
set "IP_COUNT=0"
for /f "tokens=2 delims=:" %%A in ('ipconfig ^| findstr /i "IPv4"') do (
    set "RAW=%%A"
    set "RAW=!RAW: =!"
    if not "!RAW:~0,3!"=="127" (
        set /a IP_COUNT+=1
        set "MY_IP_!IP_COUNT!=!RAW!"
    )
)

if %IP_COUNT% equ 0 (
    echo [!] No non-loopback IPv4 found. Skipping subnet scan.
    goto :MANUAL_INPUT
)

:: For each local IP derive /24 subnet and scan all 254 hosts in parallel via PowerShell runspaces
set "FOUND_IP="
for /l %%N in (1,1,%IP_COUNT%) do (
    set "LOCAL_IP=!MY_IP_%%N!"

    for /f "tokens=1-3 delims=." %%a in ("!LOCAL_IP!") do (
        set "SUBNET=%%a.%%b.%%c"
    )

    echo [*] Scanning subnet !SUBNET!.0/24 ^(interface !LOCAL_IP!^)...

    powershell -NoProfile -Command "$port=%LMS_PORT%; $subnet='!SUBNET!'; $pool=[runspacefactory]::CreateRunspacePool(1,50); $pool.Open(); $ps=1..254 | ForEach-Object { $ip=\"$subnet.$_\"; $p=[powershell]::Create(); $p.RunspacePool=$pool; [void]$p.AddScript({param($h,$port) try{$r=Invoke-WebRequest -Uri \"http://$h`:$port/v1/models\" -TimeoutSec 1 -UseBasicParsing; if($r.StatusCode -eq 200){$h}}catch{} }).AddArgument($ip).AddArgument($port); [pscustomobject]@{Pipe=$p;Handle=$p.BeginInvoke()} }; $results=$ps | ForEach-Object { $_.Pipe.EndInvoke($_.Handle) }; $pool.Close(); $hit=$results | Where-Object {$_} | Select-Object -First 1; if($hit){ $hit | Out-File 'lms_found.tmp' -Encoding ascii }" 2>nul

    if exist lms_found.tmp (
        set /p "FOUND_IP=" < lms_found.tmp
        del lms_found.tmp >nul 2>&1
        set "FOUND_IP=!FOUND_IP: =!"
        if not "!FOUND_IP!"=="" (
            set "BASE_URL=http://!FOUND_IP!:%LMS_PORT%"
            echo [+] LM Studio found at !BASE_URL!
            goto :MODELS
        )
    )
    echo [-] Nothing found on !SUBNET!.0/24
)

echo [-] Subnet scan complete — LM Studio not detected automatically.

:MANUAL_INPUT
echo.
set /p "INPUT_URL=Enter LM Studio IP:Port (e.g. 192.168.1.50:1234): "
set "CLEAN=!INPUT_URL!"
set "CLEAN=!CLEAN:http://=!"
set "CLEAN=!CLEAN:https://=!"
set "CLEAN=!CLEAN:/v1=!"
if "!CLEAN:~-1!"=="/" set "CLEAN=!CLEAN:~0,-1!"
set "BASE_URL=http://!CLEAN!"

powershell -NoProfile -Command ^
    "try{$null=Invoke-WebRequest -Uri '!BASE_URL!/v1/models' -TimeoutSec 4 -UseBasicParsing; exit 0}catch{exit 1}" >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Cannot reach LM Studio at !BASE_URL!
    echo         Make sure LM Studio's server is running and the address is correct, then re-run.
    pause
    exit /b 1
)
echo [+] Connected to LM Studio at !BASE_URL!

:: ─────────────────────────────────────────────────────────────
:: STEP 6 – Fetch model list
:: ─────────────────────────────────────────────────────────────
:MODELS
set "QUERY_URL=%BASE_URL%/v1"
set "ANTHROPIC_BASE_URL=%BASE_URL%"

echo.
echo [*] Fetching loaded models from %QUERY_URL%/models ...

powershell -NoProfile -Command "try{$r=Invoke-RestMethod -Uri '%QUERY_URL%/models' -TimeoutSec 5; $r.data.id | Out-File 'models.tmp' -Encoding ascii}catch{exit 1}" 2>nul

if %errorlevel% neq 0 (
    echo [ERROR] Could not retrieve model list. Is a model loaded in LM Studio?
    pause
    exit /b 1
)

set "MODEL_COUNT=0"
for /f "usebackq delims=" %%I in ("models.tmp") do (
    set /a MODEL_COUNT+=1
    set "MODEL_!MODEL_COUNT!=%%I"
)
del models.tmp >nul 2>&1

if %MODEL_COUNT% equ 0 (
    echo [!] LM Studio responded but NO models are loaded.
    echo     Load a model in LM Studio and try again.
    pause
    exit /b 1
)

echo.
echo  Available models:
echo  ─────────────────
for /l %%N in (1,1,%MODEL_COUNT%) do (
    echo  [%%N] !MODEL_%%N!
)
echo.

:: ─────────────────────────────────────────────────────────────
:: STEP 7 – 10-second auto-select timer, then prompt
:: ─────────────────────────────────────────────────────────────
set "CHOICE="
set "BYPASS_FLAG=--dangerously-skip-permissions"
set "TARGET_PATH=."

powershell -NoProfile -Command "$t=10; $s=Get-Date; while($t -gt 0){ if($Host.UI.RawUI.KeyAvailable){exit 1}; Write-Host -NoNewline (\"`r  Auto-selecting model [1] in $t s — press any key to choose manually...\"); Start-Sleep -Milliseconds 500; $t=10-[math]::Floor(((Get-Date)-$s).TotalSeconds) }; exit 0"

if %errorlevel% equ 0 (
    echo.
    echo [+] Timer expired — using defaults: Model 1, Bypass mode, current directory.
    set "CHOICE=1"
    goto :LAUNCH
)

echo.
set /p "CHOICE=Enter model number [1-%MODEL_COUNT%]: "
if "!CHOICE!"=="" set "CHOICE=1"

echo.
echo  Launch modes:
echo  [1] Bypass  ^(--dangerously-skip-permissions^)  -- recommended for local use
echo  [2] Standard  ^(interactive permission prompts^)
set /p "MODE_IN=Select mode [Default 1]: "
if "!MODE_IN!"=="2" (set "BYPASS_FLAG=") else (set "BYPASS_FLAG=--dangerously-skip-permissions")

echo.
set /p "TARGET_PATH=Project path to open (press Enter for current directory): "
if "!TARGET_PATH!"=="" set "TARGET_PATH=."

:: ─────────────────────────────────────────────────────────────
:: STEP 8 – Launch Claude Code
:: ─────────────────────────────────────────────────────────────
:LAUNCH
set "SELECTED_MODEL=!MODEL_%CHOICE%!"

if "!SELECTED_MODEL!"=="" (
    echo [ERROR] Invalid selection "!CHOICE!". Exiting.
    pause
    exit /b 1
)

echo.
echo  ================================================
echo   Launching Claude Code
echo   Model  : !SELECTED_MODEL!
echo   Server : %BASE_URL%
echo   Path   : !TARGET_PATH!
echo  ================================================
echo.

cd /d "!TARGET_PATH!" 2>nul || (
    echo [ERROR] Cannot open path: !TARGET_PATH!
    pause
    exit /b 1
)

set "ANTHROPIC_BASE_URL=%BASE_URL%"
claude %BYPASS_FLAG% --model !SELECTED_MODEL!

echo.
echo [*] Claude Code session ended.
pause
endlocal