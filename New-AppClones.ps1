<#
.SYNOPSIS
    Creates any number of fully isolated "clones" of an app. Each clone lives in
    its own root folder and shares nothing with the others (logins, cookies,
    cache, settings, downloads).

.DESCRIPTION
    Layout produced (defaults):

        <Desktop>\whatsapp_accounts\
            all_datas_of_system1\   <- clone 1 (own profile, own Downloads, Launch.cmd)
            all_datas_of_system2\   <- clone 2
            ...
            WhatsApp - system1.lnk  <- shortcuts
            Launch-All.cmd          <- opens every clone at once

    Two modes:

    Web  (default, recommended for WhatsApp)
        Each clone is a Chromium (Edge/Chrome/Brave) "app window" running
        web.whatsapp.com with its OWN --user-data-dir inside the clone folder.
        Separate browser profiles share nothing, so every clone is a separate
        WhatsApp session. Downloads go to <clone>\Downloads.

    Exe  (normal Win32 / Electron desktop apps: Telegram, Discord, Slack, ...)
        Each clone launches the app with USERPROFILE / APPDATA / LOCALAPPDATA /
        TEMP redirected into the clone folder (optionally with its own copy of
        the program files and an Electron --user-data-dir).

    NOTE: Microsoft Store (MSIX) apps, including the current WhatsApp Desktop,
    cannot be cloned this way. Windows ties their data to the logged-in user
    (%LOCALAPPDATA%\Packages\...) and blocks running a copy. Use Web mode for them.

.EXAMPLE
    .\New-AppClones.ps1 -Count 4
    # 4 isolated WhatsApp Web clones: system1..system4

.EXAMPLE
    .\New-AppClones.ps1 -Names system1,systemx,systemy,systemz -Launch

.EXAMPLE
    .\New-AppClones.ps1 -AppName Telegram -Mode Exe `
        -ExePath "$env:APPDATA\Telegram Desktop\Telegram.exe" -ExeArgs '-workdir "%C%Home"' -Count 3

.EXAMPLE
    .\New-AppClones.ps1 -AppName Slack -Mode Exe -ExePath "$env:LOCALAPPDATA\slack\slack.exe" -ElectronUserDataDir -Count 2
#>
[CmdletBinding(DefaultParameterSetName = 'Count')]
param(
    # Display name used for folders/shortcuts.
    [string]$AppName = 'WhatsApp',

    # Parent folder holding all clones. Default: <Desktop>\<appname>_accounts
    [string]$Root,

    # How many clones to create (named <Prefix>1..<Prefix>N).
    [Parameter(ParameterSetName = 'Count')]
    [ValidateRange(1, 200)]
    [int]$Count = 4,

    # Or give explicit clone names, e.g. system1,systemx,systemy
    [Parameter(ParameterSetName = 'Names', Mandatory)]
    [string[]]$Names,

    [string]$Prefix = 'system',
    [string]$FolderPrefix = 'all_datas_of_',

    [ValidateSet('Web', 'Exe')]
    [string]$Mode = 'Web',

    # ---- Web mode ----
    [string]$Url = 'https://web.whatsapp.com',
    [ValidateSet('Auto', 'Edge', 'Chrome', 'Brave')]
    [string]$Browser = 'Auto',

    # ---- Exe mode ----
    [string]$ExePath,
    # Extra args. %C% expands to the clone folder (with trailing backslash) at launch.
    [string]$ExeArgs = '',
    # Add --user-data-dir="<clone>\Home\AppData\Roaming\<AppName>" (Electron apps).
    [switch]$ElectronUserDataDir,
    # Copy the program folder into each clone (<clone>\App) and run that copy.
    [switch]$CopyApp,

    # ---- Common ----
    [string]$IconPath,
    [switch]$NoShortcuts,
    [switch]$DesktopShortcuts,
    # Folder(s) to put the shortcuts in. Default: the clones root folder.
    [string[]]$ShortcutDir,
    # Open all clones after creating them.
    [switch]$Launch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- helpers ---
function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Write-Cmd([string]$Path, [string[]]$Lines) {
    # CRLF + UTF-8 (no BOM) + chcp 65001 keeps non-ASCII paths working.
    Write-Utf8NoBom $Path (($Lines -join "`r`n") + "`r`n")
}

function Find-Browser([string]$Pref) {
    $pf = $env:ProgramFiles; $pf86 = ${env:ProgramFiles(x86)}; $la = $env:LOCALAPPDATA
    $map = [ordered]@{
        Edge   = @("$pf86\Microsoft\Edge\Application\msedge.exe", "$pf\Microsoft\Edge\Application\msedge.exe")
        Chrome = @("$pf\Google\Chrome\Application\chrome.exe", "$pf86\Google\Chrome\Application\chrome.exe", "$la\Google\Chrome\Application\chrome.exe")
        Brave  = @("$pf\BraveSoftware\Brave-Browser\Application\brave.exe", "$la\BraveSoftware\Brave-Browser\Application\brave.exe")
    }
    $order = if ($Pref -eq 'Auto') { 'Chrome', 'Edge', 'Brave' } else { , $Pref }
    foreach ($b in $order) {
        foreach ($p in $map[$b]) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    }
    throw "No Chromium browser found (looked for: $($order -join ', ')). Install Chrome/Edge or use -Browser."
}

function New-Shortcut([string]$Lnk, [string]$Target, [string]$Arguments, [string]$WorkDir, [string]$Icon, [string]$Desc) {
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($Lnk)
    $s.TargetPath = $Target
    $s.Arguments = $Arguments
    $s.WorkingDirectory = $WorkDir
    $s.WindowStyle = 7          # minimized -> the helper cmd window doesn't flash up
    $s.Description = $Desc
    if ($Icon) { $s.IconLocation = $Icon }
    $s.Save()
}

function Write-Utf8Bom([string]$Path, [string]$Text) {
    # Windows PowerShell 5.1 needs a BOM to read non-ASCII .ps1 files correctly.
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($true)))
}

function Get-StopScript([string]$MatchSuffix) {
    # Stops ONLY processes whose command line / exe path contains the clone folder.
    # Skips itself and its parent cmd.exe (their command lines contain the path too).
    $suffix = $MatchSuffix -replace "'", "''"
    @'
# Closes only the processes that belong to these clones (matched by folder path).
# Your normal browser / app windows are not touched.
$match = $PSScriptRoot.TrimEnd('\') + '\' + '__SUFFIX__'
$parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
function Get-Targets {
    @(Get-CimInstance Win32_Process | Where-Object {
        $_.ProcessId -ne $PID -and $_.ProcessId -ne $parent -and (
            ($_.CommandLine -and $_.CommandLine.IndexOf($match, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or
            ($_.ExecutablePath -and $_.ExecutablePath.StartsWith($match, [StringComparison]::OrdinalIgnoreCase)))
    })
}
$targets = Get-Targets
if (-not $targets.Count) { Write-Host "Nothing running under $match"; return }
# Ask windows to close first so apps can save their data, then force what's left.
foreach ($t in $targets) {
    $p = Get-Process -Id $t.ProcessId -ErrorAction SilentlyContinue
    if ($p -and $p.MainWindowHandle -ne [IntPtr]::Zero) { [void]$p.CloseMainWindow() }
}
$deadline = (Get-Date).AddSeconds(5)
while ((Get-Date) -lt $deadline -and (Get-Targets).Count) { Start-Sleep -Milliseconds 300 }
$left = Get-Targets
foreach ($t in $left) { Stop-Process -Id $t.ProcessId -Force -ErrorAction SilentlyContinue }
Write-Host ("Closed {0} process(es){1}." -f $targets.Count, $(if ($left.Count) { " ($($left.Count) force-killed)" } else { '' }))
'@.Replace('__SUFFIX__', $suffix)
}

function New-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

# --------------------------------------------------------------- validate ---
if (-not $Root) {
    $safe = ($AppName -replace '[^\w\-]', '_').ToLower()
    $Root = Join-Path ([Environment]::GetFolderPath('Desktop')) "${safe}_accounts"
}
$Root = [IO.Path]::GetFullPath($Root)

if ($PSCmdlet.ParameterSetName -eq 'Count') {
    $Names = 1..$Count | ForEach-Object { "$Prefix$_" }
}
# 'powershell -File' passes 'a,b' as one string -> split it.
$Names = @($Names | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$bad = $Names | Where-Object { $_ -match '[\\/:*?"<>|]' }
if ($bad) { throw "Invalid characters in clone name(s): $($bad -join ', ')" }
$dupes = $Names | Group-Object | Where-Object Count -gt 1
if ($dupes) { throw "Duplicate clone names: $($dupes.Name -join ', ')" }

$browserExe = $null
$exeFull = $null
if ($Mode -eq 'Web') {
    $browserExe = Find-Browser $Browser
    if (-not $IconPath) { $IconPath = "$browserExe,0" }
}
else {
    if (-not $ExePath) { throw "-ExePath is required in Exe mode." }
    $exeFull = [IO.Path]::GetFullPath($ExePath)
    if ($exeFull -like '*\WindowsApps\*') {
        throw "'$exeFull' is a Microsoft Store (MSIX) app. Windows doesn't let you redirect or copy its data, so it can't be cloned. Use -Mode Web instead (WhatsApp: -Url https://web.whatsapp.com)."
    }
    if (-not (Test-Path -LiteralPath $exeFull)) { throw "Executable not found: $exeFull" }
    if (-not $IconPath) { $IconPath = "$exeFull,0" }
}

New-Dir $Root
Write-Host "Root: $Root" -ForegroundColor Cyan
Write-Host "Mode: $Mode $(if ($browserExe) { "($browserExe)" } else { "($exeFull)" })" -ForegroundColor Cyan

# ----------------------------------------------------------- build clones ---
$created = @()
foreach ($name in $Names) {
    $clone = Join-Path $Root ($FolderPrefix + $name)
    $isNew = -not (Test-Path -LiteralPath $clone)
    New-Dir $clone
    $downloads = Join-Path $clone 'Downloads'
    New-Dir $downloads

    $lines = @('@echo off', 'chcp 65001 >nul', 'setlocal', 'set "C=%~dp0"')

    if ($Mode -eq 'Web') {
        $profileDir = Join-Path $clone 'BrowserProfile'
        New-Dir (Join-Path $profileDir 'Default')

        # Seed preferences once: per-clone download folder, no first-run noise.
        $prefFile = Join-Path $profileDir 'Default\Preferences'
        if (-not (Test-Path -LiteralPath $prefFile)) {
            $prefs = @{
                download = @{ default_directory = $downloads; prompt_for_download = $false; directory_upgrade = $true }
                savefile = @{ default_directory = $downloads }
                profile  = @{ name = "$AppName - $name"; exit_type = 'Normal'; exited_cleanly = $true }
                browser  = @{ has_seen_welcome_page = $true }
            }
            Write-Utf8NoBom $prefFile ($prefs | ConvertTo-Json -Depth 5)
        }

        $lines += "start `"`" `"$browserExe`" --user-data-dir=`"%C%BrowserProfile`" --app=`"$Url`" --no-first-run --no-default-browser-check"
    }
    else {
        $home_ = Join-Path $clone 'Home'
        foreach ($d in 'AppData\Roaming', 'AppData\Local', 'Documents', 'Desktop') { New-Dir (Join-Path $home_ $d) }
        New-Dir (Join-Path $clone 'Temp')

        $exeDir = Split-Path $exeFull -Parent
        $exeName = Split-Path $exeFull -Leaf
        if ($CopyApp) {
            $appCopy = Join-Path $clone 'App'
            if (-not (Test-Path -LiteralPath (Join-Path $appCopy $exeName))) {
                Write-Host "  copying program files -> $appCopy" -ForegroundColor DarkGray
                New-Dir $appCopy
                Copy-Item -Path (Join-Path $exeDir '*') -Destination $appCopy -Recurse -Force
            }
            $runExe = "%C%App\$exeName"; $runDir = '%C%App'
        }
        else {
            $runExe = $exeFull; $runDir = $exeDir
        }

        $extra = $ExeArgs
        if ($ElectronUserDataDir) { $extra = "--user-data-dir=`"%C%Home\AppData\Roaming\$AppName`" $extra" }

        $lines += @(
            'set "USERPROFILE=%C%Home"',
            'set "HOME=%C%Home"',
            'set "HOMEDRIVE=%C:~0,2%"',
            'set "HOMEPATH=%C:~2%Home"',
            'set "APPDATA=%C%Home\AppData\Roaming"',
            'set "LOCALAPPDATA=%C%Home\AppData\Local"',
            'set "TEMP=%C%Temp"',
            'set "TMP=%C%Temp"',
            "start `"`" /D `"$runDir`" `"$runExe`" $extra".TrimEnd()
        )
    }

    $lines += 'endlocal'
    Write-Cmd (Join-Path $clone 'Launch.cmd') $lines

    # Stop.cmd closes this clone only.
    Write-Utf8Bom (Join-Path $clone 'Stop.ps1') (Get-StopScript '')
    Write-Cmd (Join-Path $clone 'Stop.cmd') @(
        '@echo off',
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Stop.ps1"'
    )

    if (-not $NoShortcuts) {
        $lnkName = "$AppName - $name.lnk"
        $targets = @()
        if ($ShortcutDir) { foreach ($d in $ShortcutDir) { New-Dir $d; $targets += Join-Path $d $lnkName } }
        else { $targets += Join-Path $Root $lnkName }
        if ($DesktopShortcuts) { $targets += Join-Path ([Environment]::GetFolderPath('Desktop')) $lnkName }
        foreach ($lnk in ($targets | Select-Object -Unique)) {
            New-Shortcut $lnk "$env:ComSpec" "/c `"$(Join-Path $clone 'Launch.cmd')`"" $clone $IconPath "$AppName ($name) - isolated clone"
        }
    }

    $created += $clone
    Write-Host ("  [{0}] {1}" -f $(if ($isNew) { 'new ' } else { 'kept' }), $clone) -ForegroundColor $(if ($isNew) { 'Green' } else { 'Yellow' })
}

# Stop-All.cmd closes every clone in this root; normal apps/browsers are untouched.
Write-Utf8Bom (Join-Path $Root 'Stop-All.ps1') (Get-StopScript $FolderPrefix)
Write-Cmd (Join-Path $Root 'Stop-All.cmd') @(
    '@echo off',
    'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Stop-All.ps1"',
    'timeout /t 3 >nul'
)

Write-Cmd (Join-Path $Root 'Launch-All.cmd') @(
    '@echo off',
    'chcp 65001 >nul',
    "for /d %%D in (`"%~dp0$FolderPrefix*`") do if exist `"%%D\Launch.cmd`" call `"%%D\Launch.cmd`""
)

Write-Host "`nDone. $($created.Count) isolated clone(s). Open them with the shortcuts or Launch-All.cmd in:" -ForegroundColor Cyan
Write-Host "  $Root"
if (-not $NoShortcuts -and $ShortcutDir) {
    foreach ($d in ($ShortcutDir | Select-Object -Unique)) {
        New-Shortcut (Join-Path $d "$AppName - Launch All.lnk") "$env:ComSpec" "/c `"$(Join-Path $Root 'Launch-All.cmd')`"" $Root $IconPath "Open all $AppName clones"
        New-Shortcut (Join-Path $d "$AppName - Stop All.lnk") "$env:ComSpec" "/c `"$(Join-Path $Root 'Stop-All.cmd')`"" $Root "$env:SystemRoot\System32\shell32.dll,27" "Close all $AppName clones"
    }
    Write-Host "Shortcuts: $(($ShortcutDir | Select-Object -Unique) -join ' | ')"
}

if ($Launch) {
    foreach ($c in $created) {
        Start-Process -FilePath $env:ComSpec -ArgumentList "/c `"$(Join-Path $c 'Launch.cmd')`"" -WindowStyle Hidden
        Start-Sleep -Milliseconds 400
    }
}
