@echo off
rem  Fable System - one-click restore. Double-click me.
rem  Runs the PowerShell installer with a bypassed execution policy
rem  (script files downloaded from the internet are blocked by default).
setlocal
rem Clear any inherited PSModulePath (e.g. from a PowerShell 7 parent) so
rem Windows PowerShell 5.1 rebuilds its own defaults and finds its modules.
set "PSModulePath="
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set EC=%ERRORLEVEL%
echo.
if %EC%==0 (
  echo  All done. Follow the NEXT STEPS printed above.
) else if %EC%==2 (
  echo  Aborted by user - nothing was changed.
) else (
  echo  Installer reported problems - scroll up or check the log path it printed.
)
echo.
pause
exit /b %EC%
