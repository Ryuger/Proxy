@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0StartProxyServer.ps1"
if %ERRORLEVEL% neq 0 (
  echo Failed to start proxy stack.
  exit /b %ERRORLEVEL%
)
endlocal
