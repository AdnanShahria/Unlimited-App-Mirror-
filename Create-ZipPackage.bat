@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

echo =====================================================================
echo          APP MIRROR - CREATE PORTABLE DISTRIBUTION PACKAGE
echo =====================================================================
echo.
echo Packaging App-Mirror into a distributable .zip file...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$desktop = [Environment]::GetFolderPath('Desktop'); $zip = Join-Path $desktop 'App-Mirror-Portable.zip'; if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }; Compress-Archive -Path 'App-Mirror.bat', 'README.md' -DestinationPath $zip; Write-Host ' [OK] Ready for sharing!' -ForegroundColor Green; Write-Host (' Location: ' + $zip) -ForegroundColor Cyan"

echo.
pause
