@echo off
setlocal enabledelayedexpansion

:: 1. Check for Claude CLI Installation [cite: 1]
where claude >nul 2>nul
if %errorlevel% neq 0 (
    echo [!] Claude CLI not found. Installing...
    call npm install -g @anthropic-ai/claude-code
)

:: 2. Set Credentials [cite: 2]
set "ANTHROPIC_AUTH_TOKEN="
set "ANTHROPIC_API_KEY=lm-studio"

:: 3. AUTO-DETECTION LOGIC [cite: 2]
echo [!] Detecting LM Studio Server...

set "BASE_URL=http://localhost:1234"
powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri '%BASE_URL%/v1/models' -TimeoutSec 2 -UseBasicParsing; exit 0 } catch { exit 1 }" >nul 2>&1

if %errorlevel% equ 0 (
    echo [+] Found LM Studio on localhost.
) else (
    echo [-] Localhost not responding. Checking Local Network IP... [cite: 2]
    for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr "IPv4"') do (
        set "MY_IP=%%a"
        set "MY_IP=!MY_IP: =!"
        powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://!MY_IP!:1234/v1/models' -TimeoutSec 2 -UseBasicParsing; exit 0 } catch { exit 1 }" >nul 2>&1
        if !errorlevel! equ 0 (
            set "BASE_URL=http://!MY_IP!:1234"
            echo [+] Found LM Studio on network IP: !BASE_URL! [cite: 3]
            goto :FOUND
        )
    )
    echo [!] Auto-detection failed. [cite: 4]
    set /p "INPUT_URL=Enter IP/Host (e.g. 192.168.123.456:1234): "
    set "TEMP_URL=!INPUT_URL!"
    set "TEMP_URL=!TEMP_URL:http://=!"
    set "TEMP_URL=!TEMP_URL:https://=!"
    set "TEMP_URL=!TEMP_URL:/v1=!"
    if "!TEMP_URL:~-1!"=="/" set "TEMP_URL=!TEMP_URL:~0,-1!"
    set "BASE_URL=http://!TEMP_URL!"
)

:FOUND
set "QUERY_URL=%BASE_URL%/v1"
set "ANTHROPIC_BASE_URL=%BASE_URL%"

:: 4. Fetch and List Models [cite: 3]
echo [!] Attempting to reach: %QUERY_URL%/models
powershell -NoProfile -Command "try { $r = Invoke-RestMethod -Uri '%QUERY_URL%/models' -TimeoutSec 5; $r.data.id | Out-File -FilePath 'models.tmp' -Encoding ascii } catch { exit 1 }"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] FAILED TO CONNECT TO LM STUDIO. [cite: 4]
    pause
    exit /b
)

set count=0
for /f "usebackq delims=" %%i in ("models.tmp") do (
    set /a count+=1
    set "model!count!=%%i"
    echo [!count!] %%i
)
del models.tmp >nul 2>&1 [cite: 5]

if %count% equ 0 (
    echo [!] Server reached, but NO MODELS are loaded.
    pause
    exit /b
)

:: --- 10s DYNAMIC PROMPT & MODE SELECTION ---
echo.
set "CHOICE="
set "MODE=BYPASS"
set "TARGET_PATH=."

:: PowerShell loop for the dynamic countdown
powershell -NoProfile -Command "$t=10; $s=Get-Date; while($t -gt 0){ if($Host.UI.RawUI.KeyAvailable){exit 1}; Write-Host -NoNewline (\"`rSelect model number (\" + $t + \"s) : \"); Start-Sleep -m 500; $t=10-[math]::Floor(((Get-Date)-$s).TotalSeconds) }; exit 0"

if %errorlevel% equ 0 (
    echo.
    echo [!] Timer expired. Using Defaults: Model 1, Bypass Mode, Current Dir.
    set "CHOICE=1"
    set "BYPASS_FLAG=--dangerously-skip-permissions"
    goto :LAUNCH_CLAUDE
)

:: Manual Inputs if key was pressed
echo.
set /p "CHOICE=Select model number: "
set /p "M_INPUT=Mode? (1=Bypass, 2=Standard) [Default 1]: "
if "%M_INPUT%"=="2" (set "BYPASS_FLAG=") else (set "BYPASS_FLAG=--dangerously-skip-permissions")

set /p "TARGET_PATH=Enter path to open (or press Enter for current dir): "
if "!TARGET_PATH!"=="" set "TARGET_PATH=."

:LAUNCH_CLAUDE
set "SELECTED_MODEL=!model%CHOICE%!"

:: 6. Launch [cite: 6]
echo [!] Launching Claude in !TARGET_PATH! with %SELECTED_MODEL%...
cd /d "!TARGET_PATH!"
claude %BYPASS_FLAG% --model %SELECTED_MODEL%
pause
