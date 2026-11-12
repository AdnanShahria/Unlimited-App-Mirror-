<# :
@echo off
:: ===========================================================================
::  App Mirror 1.0  -  run several fully separate copies of any app
::
::  Just double-click this file. Everything is inside this one file;
::  no installation and no admin rights needed.
::  (Technical note: this is a batch + PowerShell hybrid. The batch part only
::   starts PowerShell, which then runs the rest of this same file.)
:: ===========================================================================
setlocal
title App Mirror
set "AM_SELF=%~f0"
where powershell.exe >nul 2>&1 || (echo Windows PowerShell is required but was not found. & pause & exit /b 1)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create([IO.File]::ReadAllText($env:AM_SELF)))"
if errorlevel 1 pause
exit /b
#>

# ============================================================================
#  App Mirror - PowerShell section
# ============================================================================
$ErrorActionPreference = 'Stop'
$AppTitle   = 'App Mirror'
$AppVersion = '1.0.0'
$DataDir    = Join-Path $env:LOCALAPPDATA 'AppMirror'
$Libraries  = Join-Path $DataDir 'libraries.txt'     # list of clone folders created on this PC
$LogFile    = Join-Path $DataDir 'app-mirror.log'
$Manifest   = 'AppMirror.json'                        # settings file stored in every clone folder
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
try { $Host.UI.RawUI.WindowTitle = "$AppTitle $AppVersion" } catch { }

# Store apps can't be cloned directly; these are their official web versions.
$WebVersions = [ordered]@{
    whatsapp = 'https://web.whatsapp.com';  telegram  = 'https://web.telegram.org'
    discord  = 'https://discord.com/app';   messenger = 'https://www.messenger.com'
    instagram= 'https://www.instagram.com'; slack     = 'https://app.slack.com'
    teams    = 'https://teams.microsoft.com'; spotify = 'https://open.spotify.com'
    chatgpt  = 'https://chatgpt.com';       outlook   = 'https://outlook.live.com'
}

# =============================================================== UI helpers ==
function Write-Log([string]$msg) {
    try { Add-Content -LiteralPath $LogFile -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg) } catch { }
}
function Say([string]$t = '', [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Ok([string]$t)   { Write-Host "  [OK] $t" -ForegroundColor Green }
function Warn([string]$t) { Write-Host "  [!]  $t" -ForegroundColor Yellow }
function Fail([string]$t) { Write-Host "  [X]  $t" -ForegroundColor Red }

function Show-Header([string]$sub = '') {
    Clear-Host
    Say ''
    Say '  ============================================================' DarkCyan
    Say ("    {0}  {1}" -f $AppTitle.ToUpper(), $AppVersion) Cyan
    Say '    Run several fully separate copies of any app' DarkGray
    Say '  ============================================================' DarkCyan
    if ($sub) { Say "    $sub" White; Say '  ------------------------------------------------------------' DarkCyan }
    Say ''
}

function Step([int]$n, [int]$of, [string]$t) {
    Say ''
    Say ("  STEP {0}/{1}  {2}" -f $n, $of, $t) Cyan
    Say ('  ' + ('-' * 58)) DarkCyan
}

function Ask([string]$q, [string]$default = '') {
    $prompt = if ($default) { "  $q [$default]" } else { "  $q" }
    $a = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($a)) { return $default }
    return $a.Trim().Trim('"').Trim("'").Trim()        # drag-and-drop adds quotes
}

function Ask-YesNo([string]$q, [bool]$default) {
    $d = if ($default) { 'Y' } else { 'N' }
    while ($true) {
        $a = Ask "$q (Y/N)" $d
        if ($a -match '^(y|yes)$') { return $true }
        if ($a -match '^(n|no)$')  { return $false }
        Warn 'Please answer Y or N.'
    }
}

function Ask-Choice([string]$q, [string[]]$opts, [int]$default = 1, [switch]$AllowBack) {
    for ($i = 0; $i -lt $opts.Count; $i++) { Say ("   [{0}] {1}" -f ($i + 1), $opts[$i]) White }
    if ($AllowBack) { Say '   [0] Back' DarkGray }
    while ($true) {
        $n = -1
        $a = Ask $q "$default"
        if ([int]::TryParse($a, [ref]$n)) {
            if ($n -ge 1 -and $n -le $opts.Count) { return $n }
            if ($AllowBack -and $n -eq 0) { return 0 }
        }
        Warn "Type a number from $(if ($AllowBack) { 0 } else { 1 }) to $($opts.Count)."
    }
}

function Ask-Folder([string]$q, [string]$default) {
    Say '  Enter = use the suggestion, or paste a full path, or type B to browse.' DarkGray
    while ($true) {
        $a = Ask $q $default
        if ($a -match '^[Bb]$') {
            Add-Type -AssemblyName System.Windows.Forms
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = $q; $dlg.ShowNewFolderButton = $true
            if ($dlg.ShowDialog() -ne 'OK') { continue }
            $a = $dlg.SelectedPath
        }
        $a = [Environment]::ExpandEnvironmentVariables($a)
        if ($a -match '^[A-Za-z]:\\' -or $a -match '^\\\\[^\\]+\\') { return [IO.Path]::GetFullPath($a).TrimEnd('\') }
        Warn 'Please give a full path, for example  D:\whatsapp_accounts'
    }
}

function Pause-Key { Say ''; [void](Read-Host '  Press Enter to continue') }

function Get-SafeName([string]$n) {
    $n = ($n -replace '[\\/:*?"<>|]', '').Trim().TrimEnd('.')
    if ($n -match '^(con|prn|aux|nul|com\d|lpt\d)$') { return '' }
    return $n
}

function Get-FolderSizeMB([string]$dir) {
    $sum = (Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if (-not $sum) { return 0 }
    [math]::Round($sum / 1MB, 0)
}

# ============================================================ file helpers ==
function New-Dir([string]$p) { if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Text([string]$p, [string]$t, [bool]$bom = $false) { [IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($bom))) }
function Write-Cmd([string]$p, [string[]]$lines) { Write-Text $p (($lines -join "`r`n") + "`r`n") }

function New-Shortcut([string]$lnk, [string]$target, [string]$arguments, [string]$workDir, [string]$icon, [string]$desc, [int]$style = 1) {
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
    $s.TargetPath = $target; $s.Arguments = $arguments; $s.WorkingDirectory = $workDir
    $s.WindowStyle = $style; $s.Description = $desc
    if ($icon) { $s.IconLocation = $icon }
    $s.Save()
}

function Find-Browser {
    $pf = $env:ProgramFiles; $pf86 = ${env:ProgramFiles(x86)}; $la = $env:LOCALAPPDATA
    $candidates = @(
        "$pf\Google\Chrome\Application\chrome.exe", "$pf86\Google\Chrome\Application\chrome.exe", "$la\Google\Chrome\Application\chrome.exe",
        "$pf86\Microsoft\Edge\Application\msedge.exe", "$pf\Microsoft\Edge\Application\msedge.exe",
        "$pf\BraveSoftware\Brave-Browser\Application\brave.exe", "$la\BraveSoftware\Brave-Browser\Application\brave.exe"
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
    throw 'No supported browser found. Install Google Chrome or Microsoft Edge and try again.'
}

# ======================================================= process control ==
# Closes only processes whose command line or exe path lives under $Match.
# The same function is copied into every clone's Stop.ps1.
function Stop-CloneProcesses([string]$Match) {
    $self = $PID
    $parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
    $find = {
        @(Get-CimInstance Win32_Process | Where-Object {
            $_.ProcessId -ne $self -and $_.ProcessId -ne $parent -and (
                ($_.CommandLine -and $_.CommandLine.IndexOf($Match, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                ($_.ExecutablePath -and $_.ExecutablePath.StartsWith($Match, [StringComparison]::OrdinalIgnoreCase)))
        })
    }
    $targets = @(& $find)
    if (-not $targets.Count) { return 0 }
    foreach ($t in $targets) {     # polite close first, so apps can save their data
        $p = Get-Process -Id $t.ProcessId -ErrorAction SilentlyContinue
        if ($p -and $p.MainWindowHandle -ne [IntPtr]::Zero) { [void]$p.CloseMainWindow() }
    }
    $deadline = (Get-Date).AddSeconds(6)
    while ((Get-Date) -lt $deadline -and (@(& $find)).Count) { Start-Sleep -Milliseconds 300 }
    $rem = @(& $find)
    foreach ($t in $rem) { Stop-Process -Id $t.ProcessId -Force -ErrorAction SilentlyContinue }
    return $targets.Count
}

function Get-RunningClones([string]$root, [string]$prefix) {
    $base = $root.TrimEnd('\') + '\' + $prefix
    $running = @{}
    Get-CimInstance Win32_Process | ForEach-Object {
        $s = "$($_.CommandLine) $($_.ExecutablePath)"
        $i = $s.IndexOf($base, [StringComparison]::OrdinalIgnoreCase)
        if ($i -ge 0) {
            $rest = $s.Substring($i + $base.Length)
            $name = ($rest -split '[\\"]')[0]
            if ($name) { $running[$name.ToLower()] = $true }
        }
    }
    return $running
}

# ============================================================ library data ==
function Register-Library([string]$root) {
    $list = @(Get-KnownLibraries) + $root | Select-Object -Unique
    Set-Content -LiteralPath $Libraries -Value $list -Encoding UTF8
}

function Get-KnownLibraries {
    if (-not (Test-Path -LiteralPath $Libraries)) { return @() }
    @(Get-Content -LiteralPath $Libraries -Encoding UTF8 | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ $Manifest)) } | Select-Object -Unique)
}

function Read-Library([string]$root) {
    $j = Get-Content -LiteralPath (Join-Path $root $Manifest) -Raw -Encoding UTF8 | ConvertFrom-Json
    $cfg = @{}
    foreach ($p in $j.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
    $cfg.Root = $root                                      # folder may have been moved
    $cfg.Clones = @($cfg.Clones | Where-Object { $_ })
    $cfg.ShortcutDirs = @($cfg.ShortcutDirs | Where-Object { $_ })
    return $cfg
}

function Save-Library($cfg) {
    $m = [ordered]@{
        Product = $AppTitle; Version = $AppVersion; AppName = $cfg.AppName; Mode = $cfg.Mode
        Url = $cfg.Url; Browser = $cfg.Browser; ExePath = $cfg.ExePath; ExeArgs = $cfg.ExeArgs
        CopyApp = [bool]$cfg.CopyApp; Kind = $cfg.Kind; FolderPrefix = $cfg.FolderPrefix; BaseName = $cfg.BaseName
        ShortcutDirs = @($cfg.ShortcutDirs); Clones = @($cfg.Clones | Select-Object -Unique)
        Created = $(if ($cfg.Created) { $cfg.Created } else { (Get-Date).ToString('s') }); Updated = (Get-Date).ToString('s')
    }
    Write-Text (Join-Path $cfg.Root $Manifest) ($m | ConvertTo-Json -Depth 4)
    Register-Library $cfg.Root
}

# ================================================================ engine ==
function Build-Clones($cfg, [string[]]$names) {
    New-Dir $cfg.Root
    if ($cfg.Mode -eq 'Web' -and (-not $cfg.Browser -or -not (Test-Path -LiteralPath $cfg.Browser))) { $cfg.Browser = Find-Browser }
    if ($cfg.Mode -eq 'Exe' -and -not (Test-Path -LiteralPath $cfg.ExePath)) { throw "The program was not found any more: $($cfg.ExePath)" }

    $stopFn = "function Stop-CloneProcesses {`r`n" + ${function:Stop-CloneProcesses}.ToString() + "`r`n}`r`n"
    $made = 0

    foreach ($name in $names) {
        $clone = Join-Path $cfg.Root ($cfg.FolderPrefix + $name)
        $isNew = -not (Test-Path -LiteralPath $clone)
        New-Dir $clone
        $downloads = Join-Path $clone 'Downloads'; New-Dir $downloads
        $lines = @('@echo off', 'chcp 65001 >nul', 'setlocal', 'set "C=%~dp0"')

        if ($cfg.Mode -eq 'Web') {
            $profileDir = Join-Path $clone 'BrowserProfile'
            New-Dir (Join-Path $profileDir 'Default')
            $pref = Join-Path $profileDir 'Default\Preferences'
            if (-not (Test-Path -LiteralPath $pref)) {
                $prefs = @{
                    download = @{ default_directory = $downloads; prompt_for_download = $false; directory_upgrade = $true }
                    savefile = @{ default_directory = $downloads }
                    profile  = @{ name = "$($cfg.AppName) - $name"; exit_type = 'Normal'; exited_cleanly = $true }
                    browser  = @{ has_seen_welcome_page = $true }
                }
                Write-Text $pref ($prefs | ConvertTo-Json -Depth 5)
            }
            $webArgs = "--user-data-dir=`"$profileDir`" --app=`"$($cfg.Url)`" --no-first-run --no-default-browser-check"
            $lines += "start `"`" `"$($cfg.Browser)`" --user-data-dir=`"%C%BrowserProfile`" --app=`"$($cfg.Url)`" --no-first-run --no-default-browser-check"
            $lnkTarget = $cfg.Browser; $lnkArgs = $webArgs; $lnkIcon = "$($cfg.Browser),0"; $lnkStyle = 1
        }
        else {
            $homeDir = Join-Path $clone 'Home'
            foreach ($d in 'AppData\Roaming', 'AppData\Local', 'Documents', 'Desktop') { New-Dir (Join-Path $homeDir $d) }
            New-Dir (Join-Path $clone 'Temp')
            $exeDir = Split-Path $cfg.ExePath -Parent
            $exeName = Split-Path $cfg.ExePath -Leaf
            if ($cfg.CopyApp) {
                $appCopy = Join-Path $clone 'App'
                if (-not (Test-Path -LiteralPath (Join-Path $appCopy $exeName))) {
                    Say "       copying program files for $name ..." DarkGray
                    New-Dir $appCopy
                    Copy-Item -Path (Join-Path $exeDir '*') -Destination $appCopy -Recurse -Force
                }
                $runExe = "%C%App\$exeName"; $runDir = '%C%App'; $lnkIcon = "$(Join-Path $appCopy $exeName),0"
            }
            else { $runExe = $cfg.ExePath; $runDir = $exeDir; $lnkIcon = "$($cfg.ExePath),0" }

            $lines += @(
                'set "USERPROFILE=%C%Home"', 'set "HOME=%C%Home"',
                'set "HOMEDRIVE=%C:~0,2%"', 'set "HOMEPATH=%C:~2%Home"',
                'set "APPDATA=%C%Home\AppData\Roaming"', 'set "LOCALAPPDATA=%C%Home\AppData\Local"',
                'set "TEMP=%C%Temp"', 'set "TMP=%C%Temp"',
                ("start `"`" /D `"$runDir`" `"$runExe`" $($cfg.ExeArgs)").TrimEnd()
            )
            $lnkTarget = $env:ComSpec; $lnkArgs = "/c `"$(Join-Path $clone 'Launch.cmd')`""; $lnkStyle = 7
        }

        $lines += 'endlocal'
        Write-Cmd (Join-Path $clone 'Launch.cmd') $lines
        Write-Text (Join-Path $clone 'Stop.ps1') ($stopFn + "[void](Stop-CloneProcesses (`$PSScriptRoot.TrimEnd('\') + '\'))`r`n") $true
        Write-Cmd (Join-Path $clone 'Stop.cmd') @('@echo off', 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Stop.ps1"')

        foreach ($d in $cfg.ShortcutDirs) {
            New-Dir $d
            New-Shortcut (Join-Path $d "$($cfg.AppName) - $name.lnk") $lnkTarget $lnkArgs $clone $lnkIcon "$($cfg.AppName) ($name) - App Mirror clone" $lnkStyle
        }
        if ($isNew) { $made++; Ok "$($cfg.FolderPrefix)$name" } else { Say "  [=]  $($cfg.FolderPrefix)$name (already existed, kept as is)" DarkGray }
    }

    # Library-level helpers
    $prefixLit = $cfg.FolderPrefix -replace "'", "''"
    Write-Text (Join-Path $cfg.Root 'Stop-All.ps1') ($stopFn + "`$n = Stop-CloneProcesses (`$PSScriptRoot.TrimEnd('\') + '\' + '$prefixLit')`r`nWrite-Host `"Closed `$n process(es).`"`r`n") $true
    Write-Cmd (Join-Path $cfg.Root 'Stop-All.cmd') @('@echo off', 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Stop-All.ps1"', 'timeout /t 2 >nul')
    Write-Cmd (Join-Path $cfg.Root 'Launch-All.cmd') @(
        '@echo off', 'chcp 65001 >nul',
        "for /d %%D in (`"%~dp0$($cfg.FolderPrefix)*`") do if exist `"%%D\Launch.cmd`" call `"%%D\Launch.cmd`""
    )
    $icon = if ($cfg.Mode -eq 'Web') { "$($cfg.Browser),0" } else { "$($cfg.ExePath),0" }
    foreach ($d in $cfg.ShortcutDirs) {
        New-Shortcut (Join-Path $d "$($cfg.AppName) - Open All.lnk") $env:ComSpec "/c `"$(Join-Path $cfg.Root 'Launch-All.cmd')`"" $cfg.Root $icon "Open all $($cfg.AppName) clones" 7
        New-Shortcut (Join-Path $d "$($cfg.AppName) - Close All.lnk") $env:ComSpec "/c `"$(Join-Path $cfg.Root 'Stop-All.cmd')`"" $cfg.Root "$env:SystemRoot\System32\shell32.dll,27" "Close all $($cfg.AppName) clones" 7
    }
    Write-Text (Join-Path $cfg.Root 'READ ME.txt') @"
$($cfg.AppName) clones - made with $AppTitle $AppVersion

Every "$($cfg.FolderPrefix)..." folder is one fully separate copy of $($cfg.AppName),
with its own login, settings, cache and Downloads folder.

  Launch-All.cmd    open every copy
  Stop-All.cmd      close every copy (your normal apps are not touched)
  <copy>\Launch.cmd open one copy
  <copy>\Stop.cmd   close one copy
  <copy>\Downloads  files downloaded in that copy

To add or remove copies, run App Mirror again and choose "Manage my clones".
Deleting a copy's folder deletes that account's data on this PC.
"@

    $cfg.Clones = @(@($cfg.Clones) + $names | Where-Object { $_ } | Select-Object -Unique)
    Save-Library $cfg
    Write-Log "BUILD '$($cfg.AppName)' at '$($cfg.Root)': $($names -join ',')"
    return $made
}

function Remove-Clone($cfg, [string]$name) {
    $clone = Join-Path $cfg.Root ($cfg.FolderPrefix + $name)
    [void](Stop-CloneProcesses ($clone.TrimEnd('\') + '\'))
    if (Test-Path -LiteralPath $clone) { Remove-Item -LiteralPath $clone -Recurse -Force }
    foreach ($d in $cfg.ShortcutDirs) {
        $l = Join-Path $d "$($cfg.AppName) - $name.lnk"
        if (Test-Path -LiteralPath $l) { Remove-Item -LiteralPath $l -Force }
    }
    $cfg.Clones = @($cfg.Clones | Where-Object { $_ -ne $name })
    Save-Library $cfg
    Write-Log "REMOVE clone '$name' from '$($cfg.Root)'"
}

function Start-Clone($cfg, [string]$name) {
    $l = Join-Path (Join-Path $cfg.Root ($cfg.FolderPrefix + $name)) 'Launch.cmd'
    if (Test-Path -LiteralPath $l) { Start-Process -FilePath $env:ComSpec -ArgumentList "/c `"$l`"" -WindowStyle Hidden }
}

# ======================================================== app detection ==
function Find-InstalledApp([string]$query) {
    $hits = New-Object System.Collections.ArrayList
    $sh = New-Object -ComObject WScript.Shell
    $menus = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs") | Where-Object { Test-Path -LiteralPath $_ }
    Get-ChildItem -LiteralPath $menus -Recurse -Filter *.lnk -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -like "*$query*" -and $_.BaseName -notmatch 'uninstall|help|readme|website' } |
        ForEach-Object {
            $t = $sh.CreateShortcut($_.FullName).TargetPath
            if ($t -and $t -like '*.exe' -and (Test-Path -LiteralPath $t)) { [void]$hits.Add([pscustomobject]@{ Name = $_.BaseName; Store = $false; Path = $t }) }
        }
    Get-AppxPackage -Name "*$query*" -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework -and $_.SignatureKind -ne 'System' } |
        ForEach-Object { [void]$hits.Add([pscustomobject]@{ Name = $_.Name; Store = $true; Path = $_.InstallLocation }) }
    return ,@($hits | Sort-Object Path -Unique)
}

function Select-ExeInFolder([string]$dir) {
    $skip = 'unins|uninstall|update|crash|helper|setup|elevat|notification|squirrel|vc_redist'
    $exes = @(Get-ChildItem -LiteralPath $dir -Filter *.exe -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $skip })
    if (-not $exes.Count) { $exes = @(Get-ChildItem -LiteralPath $dir -Filter *.exe -File -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $skip }) }
    if (-not $exes.Count) { Warn 'No program (.exe) found in that folder.'; return $null }
    if ($exes.Count -eq 1) { return $exes[0].FullName }
    Say '  Several programs are in that folder. Which one is the app?'
    $i = Ask-Choice 'Number' ($exes | Select-Object -First 15 | ForEach-Object { $_.FullName.Substring($dir.TrimEnd('\').Length + 1) }) 1
    return $exes[$i - 1].FullName
}

function Get-WebVersion([string]$name) {
    foreach ($k in $WebVersions.Keys) { if ($name -match $k) { return $WebVersions[$k] } }
    return ''
}

function Get-StoreAppName([string]$n) {
    $n = $n -replace '^[0-9A-F]{4,}\.', '' -replace '_.*$', '' -replace '^Microsoft\.', '' -replace 'Desktop$', '' -replace 'Beta$', ''
    if (-not $n) { return 'App' }
    return $n
}

# ============================================================ create flow ==
function Start-CreateWizard {
    Show-Header 'Create new clones'
    $cfg = @{ Mode = ''; ExePath = ''; Url = ''; ExeArgs = ''; CopyApp = $false; Kind = ''; Browser = ''; Clones = @(); ShortcutDirs = @() }
    $suggested = ''
    $total = 6

    # ---------------------------------------------------------- 1. which app
    Step 1 $total 'Which app do you want to clone?'
    Say '  Tell App Mirror which application you want to create multiple accounts for.' White
    Say '  You can enter any of the following:' DarkGray
    Say '    [1] App Name       : Type the name to search installed apps on this PC (e.g. whatsapp, antigravity)'
    Say '    [2] Drag & Drop    : Drag any .exe or desktop shortcut (.lnk) directly into this window'
    Say '    [3] Folder Path    : Enter the folder path of a portable (non-installed) app'
    Say '    [4] Website URL    : Enter a website to create isolated app windows (e.g. https://web.whatsapp.com)'
    Say ''
    while (-not $cfg.Mode) {
        $loc = Ask 'Enter app name, file path, or web URL'
        if (-not $loc) { continue }
        $loc = [Environment]::ExpandEnvironmentVariables($loc)
        $store = $false

        if ($loc -match '^https?://\S+$') {
            $cfg.Mode = 'Web'; $cfg.Url = $loc; $cfg.Kind = 'Web app window'
            $suggested = (([uri]$loc).Host -replace '^(www|web|app|open)\.', '' -split '\.')[0]
            if ($suggested) { $suggested = $suggested.Substring(0, 1).ToUpper() + $suggested.Substring(1) }
            break
        }
        if ($loc -like '*.lnk' -and (Test-Path -LiteralPath $loc)) {
            $target = (New-Object -ComObject WScript.Shell).CreateShortcut($loc).TargetPath
            $suggested = [IO.Path]::GetFileNameWithoutExtension($loc)
            if (-not $target -or $target -like '*\WindowsApps\*') { $store = $true } else { $loc = $target }
        }
        if (-not $store -and (Test-Path -LiteralPath $loc -PathType Container)) {
            $picked = Select-ExeInFolder $loc
            if (-not $picked) { continue }
            $loc = $picked
        }
        if (-not $store -and -not (Test-Path -LiteralPath $loc)) {
            if ($loc -match '[\\/]') { Warn "Path not found: $loc"; continue }
            Say "  Searching installed apps for '$loc' ..." DarkGray
            $hits = @(Find-InstalledApp $loc)
            if (-not $hits.Count) { Warn "No installed app matches '$loc'. Try typing the full path to the .exe."; continue }
            $labels = $hits | ForEach-Object { if ($_.Store) { "$(Get-StoreAppName $_.Name)   (Microsoft Store app)" } else { "$($_.Name)   ($($_.Path))" } }
            $pick = Ask-Choice 'Which app did you mean' $labels 1 -AllowBack
            if ($pick -eq 0) { continue }
            $h = $hits[$pick - 1]
            $loc = $h.Path; $store = $h.Store; $suggested = $(if ($h.Store) { Get-StoreAppName $h.Name } else { $h.Name })
        }
        if ($store -or $loc -like '*\WindowsApps\*') {
            if (-not $suggested) { $suggested = Get-StoreAppName (Split-Path $loc -Leaf) }
            Say ''
            Warn "Notice: '$suggested' is a Microsoft Store (UWP/MSIX) application."
            Say  '  Why this matters:' Yellow
            Say  '  Windows locks Store apps to a single Windows account and blocks copying their program' Yellow
            Say  '  files. To give you 100% separate accounts, App Mirror will launch the official WEB' Yellow
            Say  '  version as dedicated, borderless desktop app windows. Each clone has its own completely' Yellow
            Say  '  isolated login, cookies, cache, and Downloads folder (no shared session).' Yellow
            Say ''
            $url = Ask 'Web URL to use for this app (Enter to accept default)' (Get-WebVersion $suggested.ToLower())
            if ($url -notmatch '^https?://') { Warn 'Please enter a valid web address starting with https://'; continue }
            $cfg.Mode = 'Web'; $cfg.Url = $url; $cfg.Kind = 'Web Application Window (Isolated profiles)'; break
        }
        if ($loc -notlike '*.exe') { Warn 'Please provide a valid .exe, .lnk shortcut, app folder, or web URL.'; continue }
        if ((Split-Path $loc -Leaf) -match '(setup|install|installer)[^\\]*\.exe$') {
            Warn 'The selected file appears to be an INSTALLER, not the installed application.'
            Say  '  Please point to the actual application .exe or install the software first.' Yellow
            continue
        }
        $cfg.Mode = 'Exe'; $cfg.ExePath = [IO.Path]::GetFullPath($loc)
        $vi = (Get-Item -LiteralPath $cfg.ExePath).VersionInfo
        $suggested = @($suggested, $vi.ProductName, $vi.FileDescription, [IO.Path]::GetFileNameWithoutExtension($cfg.ExePath)) |
            Where-Object { $_ -and $_.Trim() } | Select-Object -First 1
    }
    if ($cfg.Mode -eq 'Web') { Ok "Target: $($cfg.Url)" } else { Ok "Program Executable: $($cfg.ExePath)" }

    # ------------------------------------------------- 2. installed or not
    Step 2 $total 'Storage Mode: Installed vs. Not Installed'
    if ($cfg.Mode -eq 'Web') {
        Say '  Web application: Each clone runs in an independent Chromium container.' White
        Say '  No local program installation needed. Skipping to Step 3.' DarkGray
    }
    else {
        $exeDir = Split-Path $cfg.ExePath -Parent
        $looksInstalled = ($cfg.ExePath -like "$env:ProgramFiles\*") -or ($cfg.ExePath -like "${env:ProgramFiles(x86)}\*") -or
                          ($cfg.ExePath -like "$env:LOCALAPPDATA\*") -or ($cfg.ExePath -like "$env:APPDATA\*")
        $mb = Get-FolderSizeMB $exeDir

        Say '  How should the program files be handled for each clone?' White
        Say ''
        Say '  [1] Installed (RECOMMENDED)' Cyan
        Say '      - What it does: All clones launch from your single existing program installation.'
        Say '      - Data isolation: Every clone gets its OWN separate folder for logins, chats, brain'
        Say '        data, settings, and downloads (%USERPROFILE%, %APPDATA%, and --user-data-dir).'
        Say '      - Disk space: Saves gigabytes of storage! Uses only ~10-50 MB per clone.'
        Say '      - Updates: When the app updates, all clones automatically receive the update.'
        Say ''
        Say '  [2] Not Installed (Portable / Standalone Copy)' Cyan
        Say "      - What it does: Copies the entire program folder ($mb MB) into EACH clone folder."
        Say '      - Disk space: Uses significantly more disk space (' + ($mb * 4) + ' MB for 4 clones).'
        Say '      - Best for: Portable apps from a USB stick or apps you want to move between PCs'
        Say '        as completely self-contained directories.'
        Say ''

        $c = Ask-Choice 'Select Storage Mode' @(
            'Installed      - Share program files, isolate all accounts/data (Recommended, saves disk space)',
            'Not installed  - Duplicate program folder into each clone (Standalone, uses more disk space)'
        ) $(if ($looksInstalled) { 1 } else { 2 })

        if ($c -eq 2) {
            $cfg.CopyApp = $true
            Say "  -> Mode selected: Standalone copy (Each clone will duplicate $mb MB of files)." Yellow
        }
        else {
            Say '  -> Mode selected: Installed (Shared binary, strictly isolated account profiles).' Green
        }

        # Detect specific environment flags
        $res = Join-Path $exeDir 'resources'
        if (Test-Path -LiteralPath (Join-Path $res 'app\product.json')) {
            $cfg.Kind = 'Code editor (VS Code / Antigravity / Cursor family)'
            $cfg.ExeArgs = '--user-data-dir="%C%Data" --extensions-dir="%C%Extensions"'
        }
        elseif ((Test-Path -LiteralPath (Join-Path $res 'app.asar')) -or (Test-Path -LiteralPath (Join-Path $res 'app'))) {
            $cfg.Kind = 'Electron framework application'
            $cfg.ExeArgs = '--user-data-dir="%C%Data"'
        }
        elseif ((Split-Path $cfg.ExePath -Leaf) -ieq 'Telegram.exe') {
            $cfg.Kind = 'Telegram Desktop'
            $cfg.ExeArgs = '-workdir "%C%Home"'
        }
        else { $cfg.Kind = 'Standard Win32 executable' }
        Say ''
        Ok "Environment architecture detected: $($cfg.Kind)"
        if ($cfg.Kind -eq 'Standard Win32 executable') {
            Warn 'Standard apps are isolated by redirecting %USERPROFILE%, %APPDATA%, and %TEMP%.'
            Say  '  Most apps isolate cleanly. Some legacy software stores credentials in the Windows' Yellow
            Say  '  registry and may still share logins. Test with 2 accounts first.' Yellow
        }
    }

    # -------------------------------------------------------------- 3. names
    Step 3 $total 'Clone Naming & Account Count'
    Say '  Configure the display name and how many isolated accounts to create.' White
    Say ''
    while (-not $cfg.AppName) {
        $cfg.AppName = Get-SafeName (Ask 'App display name (used for shortcuts and folder names)' (Get-SafeName $suggested))
        if (-not $cfg.AppName) { Warn 'Please enter a valid application name.' }
    }
    Say ''
    Say '  How would you like to create and name your clones?' DarkGray
    Say '    * By Count : Enter a number (e.g. 4) to create system1, system2, system3, system4'
    Say '    * By Name  : Enter comma-separated custom names (e.g. work, personal, trading, client2)'
    Say ''
    $names = @()
    while (-not $names.Count) {
        $a = Ask 'Enter number of clones OR comma-separated names' '4'
        if ($a -match '^\d+$') {
            $n = [int]$a
            if ($n -lt 1 -or $n -gt 100) { Warn 'Please choose a number between 1 and 100.'; continue }
            $base = Get-SafeName (Ask 'Base name prefix for numbered clones' 'system')
            if (-not $base) { $base = 'system' }
            $cfg.BaseName = $base
            $names = @(1..$n | ForEach-Object { "$base$_" })
        }
        else {
            $names = @($a -split ',' | ForEach-Object { Get-SafeName $_ } | Where-Object { $_ } | Select-Object -Unique)
            if (-not $names.Count) { Warn 'Please enter valid folder names without special characters.' }
        }
    }
    Say ''
    Say '  Folder naming: each clone will be placed inside its own folder starting with this prefix.' DarkGray
    $cfg.FolderPrefix = (Ask 'Folder prefix' 'all_datas_of_') -replace '[\\/:*?"<>|]', ''
    $secondExample = if ($names.Count -gt 1) { $names[1] } else { '...' }
    Say "  -> Resulting clone folders: $($cfg.FolderPrefix)$($names[0]), $($cfg.FolderPrefix)$secondExample" DarkCyan

    # ------------------------------------------------------------ 4. location
    Step 4 $total 'Storage Destination'
    Say '  Where should all the isolated clone accounts be stored on this computer?' White
    Say '  Every account gets its own self-contained folder inside this parent directory.' DarkGray
    Say ''
    $defRoot = Join-Path ([Environment]::GetFolderPath('Desktop')) ((($cfg.AppName -replace '[^\w\-]', '_').ToLower()) + '_accounts')
    $cfg.Root = Ask-Folder 'Select destination root directory' $defRoot
    if (Test-Path -LiteralPath (Join-Path $cfg.Root $Manifest)) {
        $old = Read-Library $cfg.Root
        Say ''
        Warn "This directory already contains $($old.AppName) clones ($($old.Clones -join ', '))."
        Say  '  Existing account data will be safely kept. New clones will be added alongside them.' Yellow
        $cfg.Clones = $old.Clones; $cfg.Created = $old.Created
    }
    $drive = [IO.Path]::GetPathRoot($cfg.Root)
    try {
        $free = [math]::Round((New-Object IO.DriveInfo($drive)).AvailableFreeSpace / 1GB, 1)
        Say "  Available disk space on drive $drive : $free GB free" DarkGray
    } catch { }

    # ----------------------------------------------------------- 5. shortcuts
    Step 5 $total 'Shortcut Placement'
    Say '  Where would you like to place one-click launch shortcuts?' White
    Say '  App Mirror creates a shortcut for each individual account, plus "Open All" and "Close All" controls.' DarkGray
    Say ''
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) "$($cfg.AppName) clones"
    Say '   [1] Windows Desktop                 - Quick access directly from your desktop' White
    Say '   [2] Inside the Clones Directory     - Keeps your desktop clean; shortcuts sit next to the data' White
    Say "   [3] Windows Start Menu              - Adds a folder named `"$($cfg.AppName) clones`" to Start" White
    Say '   [4] Custom Directory                - Choose any custom folder' White
    Say '   [5] Do Not Create Shortcuts         - No shortcuts will be generated' White
    Say ''
    Say '  Tip: You can select multiple locations by separating with commas (e.g. 1,2)' DarkGray
    $dirs = @()
    while ($true) {
        $sel = @((Ask 'Enter shortcut location choice(s)' '1,2') -split '[,\s]+' | Where-Object { $_ })
        if ($sel -contains '5') { $dirs = @(); break }
        $bad = @($sel | Where-Object { $_ -notmatch '^[1-4]$' })
        if ($bad.Count -or -not $sel.Count) { Warn 'Please enter numbers from 1 to 5, separated by commas.'; continue }
        foreach ($s in $sel) {
            switch ($s) {
                '1' { $dirs += $desktop }
                '2' { $dirs += $cfg.Root }
                '3' { $dirs += $startMenu }
                '4' { $dirs += Ask-Folder 'Enter custom shortcut folder' (Join-Path $desktop "$($cfg.AppName) shortcuts") }
            }
        }
        break
    }
    $cfg.ShortcutDirs = @($dirs | Select-Object -Unique)

    # ------------------------------------------------------------- 6. confirm
    Step 6 $total 'Review Configuration & Confirm'
    Say '  Please review your settings before App Mirror creates your clones:' White
    Say '  --------------------------------------------------------------------------' DarkGray
    $rows = [ordered]@{ 'Application' = $cfg.AppName }
    if ($cfg.Mode -eq 'Web') { 
        $rows['App Type'] = "Web Application Window (Chromium isolated profiles)"
        $rows['Web Target'] = $cfg.Url
    }
    else {
        $rows['Executable'] = $cfg.ExePath
        $rows['Storage Mode'] = $(if ($cfg.CopyApp) { 'Not Installed (Standalone - Program copied into each clone)' } else { 'Installed (Shared binary - Isolated data profiles)' })
        $rows['Architecture'] = $cfg.Kind
    }
    $rows['Accounts/Clones'] = ($names | ForEach-Object { "$($cfg.FolderPrefix)$_" }) -join ', '
    $rows['Clone Directory'] = $cfg.Root
    $rows['Shortcuts'] = $(if ($cfg.ShortcutDirs.Count) { $cfg.ShortcutDirs -join " `n               " } else { 'None (Skipped)' })
    
    foreach ($k in $rows.Keys) { 
        Say ("  {0,-16}: {1}" -f $k, $rows[$k]) White 
    }
    Say '  --------------------------------------------------------------------------' DarkGray
    Say ''
    if (-not (Ask-YesNo 'Proceed and create these isolated clones now?' $true)) { 
        Warn 'Setup cancelled. No changes were made to your system.'; Pause-Key; return 
    }

    Say ''
    $made = Build-Clones $cfg $names
    Say ''
    Ok "Successfully provisioned $made new clone(s) in: $($cfg.Root)"
    if ($cfg.Mode -eq 'Web') { 
        Say '  Quick Start: Open each clone once and log in (e.g. scan the WhatsApp QR code with your phone).' DarkCyan 
        Say '  Because profiles are isolated, each account will stay logged in permanently.' DarkCyan
    }
    Say ''
    if (Ask-YesNo 'Would you like to open all clones right now?' $false) { 
        Start-Process -FilePath $env:ComSpec -ArgumentList "/c `"$(Join-Path $cfg.Root 'Launch-All.cmd')`"" -WindowStyle Hidden 
    }
    if (Ask-YesNo 'Open the clones folder in File Explorer?' $true) { 
        Start-Process explorer.exe -ArgumentList "`"$($cfg.Root)`"" 
    }
}

# ============================================================ manage flow ==
function Start-ManageMenu {
    while ($true) {
        Show-Header 'Manage my clones'
        $libs = @(Get-KnownLibraries)
        $labels = @($libs | ForEach-Object {
            try { $c = Read-Library $_; "{0,-16} {1,2} clone(s)   {2}" -f $c.AppName, $c.Clones.Count, $_ } catch { "(unreadable)  $_" }
        })
        $labels += 'Find a clones folder that is not listed (e.g. moved or copied from another PC)'
        if ($libs.Count -eq 0) { Say '  No clones created on this PC yet.' DarkGray; Say '' }
        $pick = Ask-Choice 'Choose' $labels 1 -AllowBack
        if ($pick -eq 0) { return }
        if ($pick -eq $labels.Count) {
            $f = Ask-Folder 'Clones folder' ([Environment]::GetFolderPath('Desktop'))
            if (Test-Path -LiteralPath (Join-Path $f $Manifest)) { Register-Library $f; Ok 'Added to the list.' }
            else { Warn "No App Mirror clones in that folder (missing $Manifest)." }
            Pause-Key; continue
        }
        Start-LibraryMenu $libs[$pick - 1]
    }
}

function Start-LibraryMenu([string]$root) {
    while ($true) {
        $cfg = Read-Library $root
        Show-Header "$($cfg.AppName)  -  $root"
        $running = Get-RunningClones $cfg.Root $cfg.FolderPrefix
        if (-not $cfg.Clones.Count) { Say '  (no clones)' DarkGray }
        foreach ($n in $cfg.Clones) {
            $state = if ($running.ContainsKey(("$n").ToLower())) { 'running' } else { '' }
            $size = Get-FolderSizeMB (Join-Path $cfg.Root ($cfg.FolderPrefix + $n))
            Say ("   * {0,-28} {1,7} MB   {2}" -f "$($cfg.FolderPrefix)$n", $size, $state) $(if ($state) { 'Green' } else { 'White' })
        }
        Say ''
        $a = Ask-Choice 'Action' @('Open all', 'Open one', 'Close all', 'Add more clones', 'Remove a clone', 'Show folder', 'Remove ALL these clones') 1 -AllowBack
        switch ($a) {
            0 { return }
            1 { Start-Process -FilePath $env:ComSpec -ArgumentList "/c `"$(Join-Path $cfg.Root 'Launch-All.cmd')`"" -WindowStyle Hidden; Ok 'Opening...'; Start-Sleep 1 }
            2 {
                if (-not $cfg.Clones.Count) { continue }
                $i = Ask-Choice 'Which' $cfg.Clones 1 -AllowBack
                if ($i) { Start-Clone $cfg $cfg.Clones[$i - 1]; Ok 'Opening...'; Start-Sleep 1 }
            }
            3 {
                $n = Stop-CloneProcesses ($cfg.Root.TrimEnd('\') + '\' + $cfg.FolderPrefix)
                Ok "Closed $n process(es)."; Pause-Key
            }
            4 {
                Say '  Type a number of extra clones, or names separated by commas.' DarkGray
                $x = Ask 'Add' '1'
                if ($x -match '^\d+$') {
                    $base = if ($cfg.BaseName) { $cfg.BaseName } else { 'system' }
                    $used = @($cfg.Clones | ForEach-Object { if ($_ -match ('^' + [regex]::Escape($base) + '(\d+)$')) { [int]$Matches[1] } })
                    $next = if ($used.Count) { ($used | Measure-Object -Maximum).Maximum + 1 } else { 1 }
                    $new = @(0..([int]$x - 1) | ForEach-Object { "$base$($next + $_)" })
                }
                else { $new = @($x -split ',' | ForEach-Object { Get-SafeName $_ } | Where-Object { $_ -and $cfg.Clones -notcontains $_ } | Select-Object -Unique) }
                if (-not $new.Count -or [int]("0$x" -replace '\D', '') -gt 100) { Warn 'Nothing to add.'; Pause-Key; continue }
                $made = Build-Clones $cfg $new
                Ok "$made clone(s) added."; Pause-Key
            }
            5 {
                if (-not $cfg.Clones.Count) { continue }
                $i = Ask-Choice 'Remove which' $cfg.Clones 1 -AllowBack
                if (-not $i) { continue }
                $n = $cfg.Clones[$i - 1]
                Warn "This permanently deletes '$($cfg.FolderPrefix)$n' - its login, chats cache and Downloads on this PC."
                if (Ask-YesNo 'Delete it?' $false) { Remove-Clone $cfg $n; Ok 'Removed.' }
                Pause-Key
            }
            6 { Start-Process explorer.exe -ArgumentList "`"$($cfg.Root)`"" }
            7 {
                Warn "This permanently deletes ALL $($cfg.Clones.Count) clone(s) in $($cfg.Root), with their data and Downloads."
                if ((Ask "Type DELETE to confirm") -ceq 'DELETE') {
                    foreach ($n in @($cfg.Clones)) { Remove-Clone $cfg $n }
                    foreach ($d in $cfg.ShortcutDirs) {
                        foreach ($l in "Open All", "Close All") { $p = Join-Path $d "$($cfg.AppName) - $l.lnk"; if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }
                    }
                    foreach ($f in 'Launch-All.cmd', 'Stop-All.cmd', 'Stop-All.ps1', 'READ ME.txt', $Manifest) {
                        $p = Join-Path $cfg.Root $f; if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
                    }
                    if (-not (Get-ChildItem -LiteralPath $cfg.Root -Force)) { Remove-Item -LiteralPath $cfg.Root -Force }
                    Write-Log "REMOVE ALL '$($cfg.AppName)' at '$root'"
                    Ok 'All clones removed.'; Pause-Key; return
                }
                Warn 'Not confirmed - nothing deleted.'; Pause-Key
            }
        }
    }
}

# ================================================================== help ==
function Show-Help {
    Show-Header 'Help'
    Say '  WHAT IT DOES' Cyan
    Say '  Makes several copies ("clones") of an app. Each clone lives in its own folder'
    Say '  and has its own login, settings, cache and Downloads. Log in to a different'
    Say '  account in each clone and use them all at the same time.'
    Say ''
    Say '  WHICH APPS WORK' Cyan
    Say '   * Websites / web apps (WhatsApp Web, Telegram Web, ChatGPT ...)  - always'
    Say '   * Microsoft Store apps (e.g. WhatsApp from the Store)          - via their web version'
    Say '   * Code editors (Antigravity, VS Code, Cursor) and Electron apps - yes'
    Say '   * Telegram Desktop                                             - yes'
    Say '   * Other Windows programs - most work; apps that store data in the Windows'
    Say '     registry, use drivers, or allow only one running copy may not.'
    Say ''
    Say '  WEB CLONES NEED' Cyan
    Say '   Google Chrome, Microsoft Edge or Brave installed (Edge comes with Windows).'
    Say ''
    Say '  GOOD TO KNOW' Cyan
    Say '   * Nothing is installed and no admin rights are needed.'
    Say '   * Deleting a clone folder deletes that account''s data on this PC.'
    Say '   * Windows may warn about a downloaded .bat file (SmartScreen). Choose'
    Say '     "More info" -> "Run anyway" if you trust where you got it from.'
    Say "   * Log file: $LogFile"
    Pause-Key
}

# ================================================================== main ==
Write-Log "START $AppVersion"
while ($true) {
    try {
        Show-Header
        $libs = @(Get-KnownLibraries)
        $m = Ask-Choice 'Choose' @('Create new clones', "Manage my clones$(if ($libs.Count) { "  ($($libs.Count) on this PC)" })", 'Help') 1
        switch ($m) {
            1 { Start-CreateWizard }
            2 { Start-ManageMenu }
            3 { Show-Help }
        }
    }
    catch {
        Write-Log "ERROR $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)"
        Say ''
        Fail $_.Exception.Message
        Say "       Details were saved to $LogFile" DarkGray
        Pause-Key
    }
}
