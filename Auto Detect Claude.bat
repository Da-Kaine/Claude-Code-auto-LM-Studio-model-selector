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

:: 3. AUTO-DETECTION LOGIC
echo [!] Detecting LM Studio Server...

:: Check Localhost first [cite: 2]
set "BASE_URL=http://localhost:1234"
powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri '%BASE_URL%/v1/models' -TimeoutSec 2 -UseBasicParsing; exit 0 } catch { exit 1 }" >nul 2>&1

if %errorlevel% equ 0 (
    echo [+] Found LM Studio on localhost.
) else (
    echo [-] Localhost not responding. Checking Local Network IP...
    
    :: Get the local IP address (IPv4)
    for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr "IPv4"') do (
        set "MY_IP=%%a"
        set "MY_IP=!MY_IP: =!"
        
        :: Test the detected IP
        powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://!MY_IP!:1234/v1/models' -TimeoutSec 2 -UseBasicParsing; exit 0 } catch { exit 1 }" >nul 2>&1
        
        if !errorlevel! equ 0 (
            set "BASE_URL=http://!MY_IP!:1234"
            echo [+] Found LM Studio on network IP: !BASE_URL!
            goto :FOUND
        )
    )
    
    :: Final Fallback: Manual Input [cite: 2]
    echo [!] Auto-detection failed.
    set /p "INPUT_URL=Enter IP/Host (e.g. 192.168.123.567:1234): "
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

:: 4. Fetch and List Models (Robust Version) [cite: 3]
echo [!] Attempting to reach: %QUERY_URL%/models
echo [!] Please wait...

:: Executing clean PowerShell command without citation text to avoid ParserErrors
powershell -NoProfile -Command "try { $r = Invoke-RestMethod -Uri '%QUERY_URL%/models' -TimeoutSec 5; $r.data.id | Out-File -FilePath 'models.tmp' -Encoding ascii } catch { exit 1 }"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] FAILED TO CONNECT TO LM STUDIO. [cite: 4]
    echo 1. Is LM Studio "Local Server" actually RUNNING? [cite: 4]
    echo 2. Is "Cross-Origin (CORS)" ENABLED in LM Studio? [cite: 4]
    echo 3. Can you open %QUERY_URL%/models in your browser? [cite: 4]
    if exist models.tmp del models.tmp >nul 2>&1 [cite: 5]
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
    echo [!] Server reached, but NO MODELS are loaded in LM Studio.
    pause
    exit /b
)

set /p "CHOICE=Select model number: "
set "SELECTED_MODEL=!model%CHOICE%!"

:: 5. Create Quick-Launch BAT [cite: 6]
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

:: 6. Launch [cite: 6]
echo [!] Launching Claude with %SELECTED_MODEL%...
claude --model %SELECTED_MODEL% --dangerously-skip-permissions
pause
