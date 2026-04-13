@echo off
REM ======================================================================
REM  2 - PACKAGE INSTALLER (MSI)
REM
REM  Wraps WiX v5. Reads the version from the built DLL automatically.
REM  Output: setup\out\nullCarbon-LCA-Export-win64-<version>.msi
REM
REM  Click 1-build.cmd FIRST, then click this.
REM  Requires: WiX v5 (dotnet tool install --global wix).
REM  The wrapped build-installer.ps1 will install it on first run if missing.
REM ======================================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\build-installer.ps1" %*
if errorlevel 1 (
    echo.
    echo Installer packaging failed.
    pause
    exit /b 1
)
echo.
echo Installer ready in setup\out\
pause
