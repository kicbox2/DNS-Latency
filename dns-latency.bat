@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "COUNT=5"
set "TIMEOUT=1000"

set "SHOWALL=0"
if /I "%~1"=="/all" set "SHOWALL=1"

set "ALL_COUNT=0"
set "RESULTS_FILE=%TEMP%\dns_latency_%RANDOM%_%RANDOM%.txt"
if exist "%RESULTS_FILE%" del /q "%RESULTS_FILE%" >nul 2>&1

echo ===========================================================
echo DNS Latency Check (MIN latency, 0%% loss eligible)
echo Attempts: %COUNT%   Timeout: %TIMEOUT% ms
echo Syntax: %~nx0  or  %~nx0 /all
echo ===========================================================
echo.

REM ---------- DNS LIST ----------
call :TEST "Google DNS (8.8.8.8)" 8.8.8.8
call :TEST "Google DNS (8.8.4.4)" 8.8.4.4
call :TEST "Level3 / Verizon (4.2.2.2)" 4.2.2.2
call :TEST "Cloudflare (1.1.1.1)" 1.1.1.1
call :TEST "Quad9 (9.9.9.9)" 9.9.9.9
call :TEST "Comcast DNS 1 (75.75.75.75)" 75.75.75.75
call :TEST "Comcast DNS 2 (75.75.76.76)" 75.75.76.76
call :TEST "ATT Fiber DNS 1 (68.94.156.11)" 68.94.156.11
call :TEST "ATT Fiber DNS 2 (68.94.157.11)" 68.94.157.11

if "%ALL_COUNT%"=="0" (
  echo ===========================================================
  echo No DNS servers had 0%% packet loss in this run.
  echo Done.
  goto :CLEANUP_END
)

REM =========================
REM Optional /all output
REM =========================
if "%SHOWALL%"=="1" (
  echo ===========================================================
  echo ALL ELIGIBLE RESULTS ^(0%% loss, sorted by MIN latency^)
  echo ===========================================================
  call :SHOW_SORTED
  echo.
)

REM =========================
REM Detect active adapter
REM =========================
set "ACTIVE_ADAPTER="
call :GET_ACTIVE_ADAPTER
if not defined ACTIVE_ADAPTER (
  echo Could not auto-detect an active network adapter.
  echo DNS settings unchanged.
  goto :CLEANUP_END
)
echo Active adapter detected: "%ACTIVE_ADAPTER%"
echo.

REM =========================
REM Interactive selection
REM =========================
set "PRIMARY_DNS="
set "PRIMARY_NAME="
set "SECONDARY_DNS="
set "SECONDARY_NAME="

call :PICK_ONE "PRIMARY"
if not defined PRIMARY_DNS (
  echo No primary DNS chosen. Exiting without changes.
  goto :CLEANUP_END
)

call :PICK_ONE "SECONDARY"
REM Secondary is optional; if none chosen, we apply only primary.

echo ===========================================================
echo Selection:
echo   Primary  : %PRIMARY_NAME%  [%PRIMARY_DNS%]
if defined SECONDARY_DNS (
  echo   Secondary: %SECONDARY_NAME%  [%SECONDARY_DNS%]
) else (
  echo   Secondary: (none selected)
)
echo Adapter: "%ACTIVE_ADAPTER%"
echo ===========================================================
echo.

choice /C YN /N /M "Apply these DNS settings now? (Y = apply, N = exit): "
if errorlevel 2 (
  echo DNS settings unchanged.
  goto :CLEANUP_END
)

echo.
echo Applying DNS to "%ACTIVE_ADAPTER%"
echo (Run CMD as Administrator if this fails.)

REM Set primary
netsh interface ip set dns name="%ACTIVE_ADAPTER%" static %PRIMARY_DNS% primary >nul 2>&1

REM Set secondary only if selected
if defined SECONDARY_DNS (
  netsh interface ip add dns name="%ACTIVE_ADAPTER%" %SECONDARY_DNS% index=2 >nul 2>&1
)

echo Done. Verify with: ipconfig /all
goto :CLEANUP_END


REM ============================================================
REM Cleanup / Exit
REM ============================================================
:CLEANUP_END
if exist "%RESULTS_FILE%" del /q "%RESULTS_FILE%" >nul 2>&1
echo ===========================================================
echo Done.
endlocal
exit /b 0


REM ============================================================
REM TEST ONE DNS (writes eligible results to RESULTS_FILE)
REM ============================================================
:TEST
set "NAME=%~1"
set "IP=%~2"
set "LOSS="
set "MINMS="

echo Testing: %NAME%  [%IP%] ...

for /f "delims=" %%L in ('ping -n %COUNT% -w %TIMEOUT% %IP% ^| findstr /i "Lost ="') do (
  for /f "tokens=2 delims=(" %%A in ("%%L") do (
    for /f "tokens=1 delims=%%" %%B in ("%%A") do set "LOSS=%%B"
  )
)

for /f "delims=" %%L in ('ping -n %COUNT% -w %TIMEOUT% %IP% ^| findstr /i "Minimum ="') do (
  for /f "tokens=2 delims==, " %%A in ("%%L") do set "MINMS=%%A"
)

if "%LOSS%"=="" set "LOSS=?"
if "%MINMS%"=="" set "MINMS=?"

echo Result : Loss=%LOSS%%%  Min=%MINMS%
echo.

if not "%LOSS%"=="0" goto :EOF
if "%MINMS%"=="?" goto :EOF

set "MINNUM=%MINMS:ms=%"
set "PAD=00000%MINNUM%"
set "KEY=!PAD:~-5!"

set /a ALL_COUNT+=1
>>"%RESULTS_FILE%" echo !KEY!^|%NAME%^|%IP%

exit /b


REM ============================================================
REM Show sorted eligible list
REM ============================================================
:SHOW_SORTED
for /f "usebackq tokens=1-3 delims=|" %%A in (`sort "%RESULTS_FILE%"`) do (
  set "K=%%A"
  set "MS=!K!"
  for /f "tokens=* delims=0" %%Z in ("!MS!") do set "MS=%%Z"
  if "!MS!"=="" set "MS=0"
  echo !MS!ms  -  %%B  [%%C]
)
exit /b


REM ============================================================
REM Interactive picker
REM   call :PICK_ONE "PRIMARY"  or  call :PICK_ONE "SECONDARY"
REM ============================================================
:PICK_ONE
set "MODE=%~1"

echo ===========================================================
if /I "%MODE%"=="PRIMARY" (
  echo Pick PRIMARY DNS (Y = use it, N = try next, Esc/Ctrl+C = exit)
) else (
  echo Pick SECONDARY DNS (optional) (Y = use it, N = try next)
)
echo ===========================================================

for /f "usebackq tokens=1-3 delims=|" %%A in (`sort "%RESULTS_FILE%"`) do (
  set "K=%%A"
  set "CAND_NAME=%%B"
  set "CAND_IP=%%C"

  REM Skip if already chosen as primary when picking secondary
  if /I "%MODE%"=="SECONDARY" (
    if defined PRIMARY_DNS (
      if "%%C"=="%PRIMARY_DNS%" (
        REM skip
        set "SKIP=1"
      ) else (
        set "SKIP="
      )
    )
  ) else (
    set "SKIP="
  )

  if not defined SKIP (
    set "MS=!K!"
    for /f "tokens=* delims=0" %%Z in ("!MS!") do set "MS=%%Z"
    if "!MS!"=="" set "MS=0"

    echo Candidate: !CAND_NAME!  [!CAND_IP!]  Min=!MS!ms
    choice /C YN /N /M "Use this one? (Y/N): "
    if errorlevel 2 (
      echo.
    ) else (
      if /I "%MODE%"=="PRIMARY" (
        set "PRIMARY_DNS=!CAND_IP!"
        set "PRIMARY_NAME=!CAND_NAME!"
      ) else (
        set "SECONDARY_DNS=!CAND_IP!"
        set "SECONDARY_NAME=!CAND_NAME!"
      )
      goto :PICK_DONE
    )
  )
)

:PICK_DONE
echo.
exit /b


REM ============================================================
REM Auto-detect active adapter (first with a Default Gateway)
REM ============================================================
:GET_ACTIVE_ADAPTER
set "ACTIVE_ADAPTER="
set "CUR_ADAPTER="
set "AWAIT_GW=0"

for /f "delims=" %%L in ('ipconfig') do (
  set "LINE=%%L"

  echo !LINE! | findstr /I " adapter " >nul
  if not errorlevel 1 (
    for /f "tokens=1 delims=:" %%H in ("!LINE!") do (
      set "HEAD=%%H"
      set "CUR_ADAPTER=!HEAD:*adapter =!"
      set "AWAIT_GW=0"
    )
  )

  echo !LINE! | findstr /I "Default Gateway" >nul
  if not errorlevel 1 (
    for /f "tokens=2 delims=:" %%G in ("!LINE!") do (
      set "GW=%%G"
      set "GW=!GW: =!"
      if defined GW (
        set "ACTIVE_ADAPTER=!CUR_ADAPTER!"
        goto :DONE_ADAPTER
      ) else (
        set "AWAIT_GW=1"
      )
    )
  ) else (
    if "!AWAIT_GW!"=="1" (
      set "TMP=!LINE: =!"
      echo !TMP! | findstr /R "^[0-9][0-9]*\.[0-9]" >nul
      if not errorlevel 1 (
        set "ACTIVE_ADAPTER=!CUR_ADAPTER!"
        goto :DONE_ADAPTER
      )
    )
  )
)

:DONE_ADAPTER
exit /b
