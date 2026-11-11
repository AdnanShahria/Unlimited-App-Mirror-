@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
cd /d "%~dp0"

:MENU
cls
echo =====================================================================
echo               UNLIMITED APP MIRROR - MULTI-ACCOUNT MANAGER
echo =====================================================================
echo.
echo   [1] WhatsApp Web        - Unlimited Isolated WhatsApp Accounts
echo   [2] Antigravity IDE     - Isolated IDE Brains, Workspaces, and Extensions
echo   [3] Telegram Desktop    - Isolated Win32 Instances (-workdir)
echo   [4] Discord / Slack     - Isolated Electron Chat Clients
echo   [5] Custom Web App      - Clone any website as a standalone App (URL)
echo   [6] Custom Desktop Exe  - Clone any Win32/Electron .exe
echo   [7] Inspect Disk Usage  - View size of all created clone folders
echo   [0] Exit
echo.
echo =====================================================================
set /p CHOICE="Select an option [0-7]: "

if "%CHOICE%"=="1" goto CLONE_WHATSAPP
if "%CHOICE%"=="2" goto CLONE_ANTIGRAVITY
if "%CHOICE%"=="3" goto CLONE_TELEGRAM
if "%CHOICE%"=="4" goto CLONE_DISCORD
if "%CHOICE%"=="5" goto CLONE_CUSTOM_WEB
if "%CHOICE%"=="6" goto CLONE_CUSTOM_EXE
if "%CHOICE%"=="7" goto CHECK_DISK
if "%CHOICE%"=="0" exit /b 0

echo Invalid choice.
timeout /t 2 >nul
goto MENU

:: -----------------------------------------------------------------------
:CLONE_WHATSAPP
cls
echo [ WhatsApp Web Cloner ]
echo.
set /p COUNT="Enter number of accounts to clone (default 4): "
if "%COUNT%"=="" set COUNT=4
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-AppClones.ps1" -AppName WhatsApp -Count %COUNT%
echo.
pause
goto MENU

:: -----------------------------------------------------------------------
:CLONE_ANTIGRAVITY
cls
echo [ Antigravity IDE Cloner ]
echo.
set /p COUNT="Enter number of Antigravity clones to create (default 2): "
if "%COUNT%"=="" set COUNT=2
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-AppClones.ps1" -AppName Antigravity -Mode Exe -ExePath "$env:LOCALAPPDATA\Programs\Antigravity IDE\Antigravity IDE.exe" -ExeArgs '--user-data-dir=\"%%C%%Data\" --extensions-dir=\"%%C%%Extensions\"' -Count %COUNT%
echo.
pause
goto MENU

:: -----------------------------------------------------------------------
:CLONE_TELEGRAM
cls
echo [ Telegram Desktop Cloner ]
echo.
set /p COUNT="Enter number of Telegram accounts to clone (default 2): "
if "%COUNT%"=="" set COUNT=2
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-AppClones.ps1" -AppName Telegram -Mode Exe -ExePath "$env:APPDATA\Telegram Desktop\Telegram.exe" -ExeArgs '-workdir \"%%C%%Home\"' -Count %COUNT%
echo.
pause
goto MENU

:: -----------------------------------------------------------------------
:CLONE_DISCORD
cls
echo [ Discord Cloner ]
echo.
set /p COUNT="Enter number of Discord clones to create (default 2): "
if "%COUNT%"=="" set COUNT=2
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-AppClones.ps1" -AppName Discord -Mode Exe -ExePath "$env:LOCALAPPDATA\Discord\Update.exe" -ExeArgs '--processStart Discord.exe' -ElectronUserDataDir -Count %COUNT%
echo.
pause
goto MENU

:: -----------------------------------------------------------------------
:CLONE_CUSTOM_WEB
cls
echo [ Custom Web App Cloner ]
echo.
set /p APPNAME="Enter App Name (e.g. ChatGPT, Twitter, Notion): "
if "%APPNAME%"=="" goto MENU
set /p APPURL="Enter Web URL (e.g. https://chatgpt.com): "
if "%APPURL%"=="" goto MENU
set /p COUNT="Enter number of clones (default 2): "
if "%COUNT%"=="" set COUNT=2
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-AppClones.ps1" -AppName "%APPNAME%" -Url "%APPURL%" -Count %COUNT%
echo.
pause
goto MENU

:: -----------------------------------------------------------------------
:CLONE_CUSTOM_EXE
cls
echo [ Custom Desktop Exe Cloner ]
echo.
set /p APPNAME="Enter App Name: "
if "%APPNAME%"=="" goto MENU
set /p EXEPATH="Enter Full Path to Executable (.exe): "
if "%EXEPATH%"=="" goto MENU
set /p COUNT="Enter number of clones (default 2): "
if "%COUNT%"=="" set COUNT=2
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-AppClones.ps1" -AppName "%APPNAME%" -Mode Exe -ExePath "%EXEPATH%" -Count %COUNT%
echo.
pause
goto MENU

:: -----------------------------------------------------------------------
:CHECK_DISK
cls
echo =====================================================================
echo                    CLONED ACCOUNTS DISK USAGE
echo =====================================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { `$desktop = [Environment]::GetFolderPath('Desktop'); `$dirs = Get-ChildItem -Directory -Path `$desktop -Filter '*_accounts'; if (-not `$dirs) { Write-Host 'No clone directories found on Desktop.' -ForegroundColor Yellow; return }; foreach (`$d in `$dirs) { Write-Host 'Directory: ' `$d.FullName -ForegroundColor Cyan; Get-ChildItem -Directory -Path `$d.FullName -Filter 'all_datas_of_*' | ForEach-Object { `$sub = `$_; `$size = (Get-ChildItem -Path `$sub.FullName -Recurse -File -Force -EA 0 | Measure-Object -Property Length -Sum).Sum; `$mb = [math]::Round((`$size / 1MB), 2); Write-Host ('  - {0,-30} : {1,8} MB' -f `$sub.Name, `$mb) }; Write-Host '' } }"
echo.
pause
goto MENU
