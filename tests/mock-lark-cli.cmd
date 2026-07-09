@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mock-lark-cli.ps1" %*
exit /b %ERRORLEVEL%
