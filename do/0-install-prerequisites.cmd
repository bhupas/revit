@echo off
REM ======================================================================
REM  0 - INSTALL EVERYTHING (FIRST TIME ONLY)
REM
REM  Installs the tools you need to build + package:
REM    - .NET SDK 8
REM    - .NET Framework 4.8 Developer Pack
REM    - WiX v5 (dotnet global tool)
REM    - GitHub CLI
REM
REM  Idempotent: each one is checked first, skipped if already installed.
REM  Click this once on a fresh machine, then re-open Explorer and click
REM  do\1-build.cmd.
REM ======================================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\install-prerequisites.ps1" %*
echo.
pause
