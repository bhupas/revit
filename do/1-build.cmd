@echo off
REM ======================================================================
REM  1 - BUILD
REM
REM  Builds the add-in for Revit 2023 + 2024 + 2025 + 2026 + 2027.
REM  Output: src\bin\Release<year>\
REM
REM  Click this first when you've changed code.
REM  Requires: .NET SDK 10 for Revit 2027, plus the .NET Framework 4.8
REM  Developer Pack for 2023/2024 (the script tells you how to install them).
REM ======================================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\build.ps1" %*
if errorlevel 1 (
    echo.
    echo Build failed.
    pause
    exit /b 1
)
echo.
echo Build OK.
pause
