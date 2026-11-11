@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

echo ========================================================
echo   WhatsApp Multi-Account Clone Generator
echo ========================================================
echo.
echo How many WhatsApp accounts do you want to clone? (default: 4)
set /p COUNT="Enter number [e.g. 4]: "
if "%COUNT%"=="" set COUNT=4

echo.
echo Generating %COUNT% isolated clones...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-AppClones.ps1" -AppName WhatsApp -Count %COUNT%

echo.
pause

