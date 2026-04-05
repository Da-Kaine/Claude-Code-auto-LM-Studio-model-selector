@echo off
setlocal enabledelayedexpansion

:: 1. Check for Claude CLI Installation
where claude >nul 2>nul
if %errorlevel% neq 0 (
    echo [!] Claude CLI not found. Installing...
    call npm install -g @anthropic-ai/claude-code
)

:: 2. Resolve Auth Conflict & Set Variables
set "ANTHROPIC_AUTH_TOKEN="
set "ANTHROPIC_API_KEY=lm-studio"
set "DEFAULT_URL=http://localhost:1234"
set "BASE_URL=%DEFAULT_URL%"

echo.
echo Current Local URL: %DEFAULT_URL%
set /p "CONFIRM=Is this correct? (Y/N): "

if /i "%CONFIRM%" neq "Y" (
    set /p "INPUT_URL=Enter custom IP/Host (e.g. 192.168.56.1:1234): "
    set "TEMP_URL=!INPUT_URL!"
    set "TEMP_URL=!TEMP_URL:http://=!"
    set "TEMP_URL=!TEMP_URL:https://=!"
    set "TEMP_URL=!TEMP_URL:/v1=!"
    if "!TEMP_URL:~-1!"=="/" set "TEMP_URL=!TEMP_URL:~0,-1!"
    set "BASE_URL=http://!TEMP_URL!"
)

set "QUERY_URL=%BASE_URL%/v1"
set "ANTHROPIC_BASE_URL=%BASE_URL%"

:: 3. Fetch and List Models (Robust Version)
echo [!] Attempting to reach: %QUERY_URL%/models
echo [!] Please wait...

:: We write the powershell output to a temporary file to prevent the loop crash
powershell -NoProfile -Command "try { $r = Invoke-RestMethod -Uri '%QUERY_URL%/models' -TimeoutSec 5; $r.data.id | Out-File -FilePath 'models.tmp' -Encoding ascii } catch { exit 1 }"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] FAILED TO CONNECT TO LM STUDIO.
    echo 1. Is LM Studio "Local Server" actually RUNNING?
    echo 2. Is "Cross-Origin (CORS)" ENABLED in LM Studio?
    echo 3. Can you open %QUERY_URL%/models in your browser?
    del models.tmp >nul 2>&1
    pause
    exit /b
)

set count=0
for /f "usebackq delims=" %%i in ("models.tmp") do (
    set /a count+=1
    set "model!count!=%%i"
    echo [!count!] %%i
)
del models.tmp >nul 2>&1

if %count% equ 0 (
    echo [!] Server reached, but NO MODELS are loaded in LM Studio.
    pause
    exit /b
)

set /p "CHOICE=Select model number: "
set "SELECTED_MODEL=!model%CHOICE%!"

:: 4. Create Quick-Launch BAT
set /p "CREATE_L=Create a quick-launch .bat? (Y/N): "
if /i "%CREATE_L%" equ "Y" (
    set "SAFE_NAME=%SELECTED_MODEL::=-%"
    (
        echo @echo off
        echo set "ANTHROPIC_AUTH_TOKEN="
        echo set "ANTHROPIC_API_KEY=lm-studio"
        echo set "ANTHROPIC_BASE_URL=%BASE_URL%"
        echo claude --model %SELECTED_MODEL% %%*
        echo pause
    ) > "launch-!SAFE_NAME!.bat"
)

:: 5. Launch
claude --model %SELECTED_MODEL% --dangerously-skip-permissions
pause