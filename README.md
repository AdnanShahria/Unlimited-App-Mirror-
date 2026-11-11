# Unlimited App Mirror — Multi-Account Clone Generator

Run any number of accounts of an app side-by-side on Windows, each strictly isolated in its own folder with **zero connection** between their logins, cookies, cache, profiles, and downloads.

---

## The Windows WhatsApp Reality Check

On Windows 10/11, the native WhatsApp Desktop is a **UWP / MSIX Store package** (`5319275A.WhatsAppDesktop`). Windows sandboxes MSIX apps per Windows login, not per process:

* They refuse environment variable redirection (`USERPROFILE`, `APPDATA`, `LOCALAPPDATA`).
* Copying `WindowsApps` executables is blocked by OS ACLs.
* They are hardcoded to a single user data container (`%LOCALAPPDATA%\Packages\5319275A.WhatsAppDesktop_...\LocalState`).

### The Solution: Web Application Mode (`-Mode Web`, default)
The cleanest, 100% reliable way to run unlimited isolated WhatsApp accounts on Windows is to launch **WhatsApp Web as standalone Chromium app windows** (`--app=https://web.whatsapp.com`), each pinned to its own `--user-data-dir` inside the clone's folder.

* Looks and behaves like a standalone desktop app (dedicated window, taskbar icon, no URL bar, no browser tabs).
* **Zero shared data**: completely isolated cookies, IndexedDB, local storage, cache, and session tokens.
* **Per-clone downloads**: files saved from account X go directly into `all_datas_of_systemX\Downloads`.
* Supports audio/video calls, desktop notifications, camera/microphone permissions.

---

## Quick Start (WhatsApp — 4 Accounts)

### Option A: Double-click
Double-click **`Clone-WhatsApp.bat`** and press **Enter** (defaults to 4 accounts).

### Option B: PowerShell
```powershell
# Creates 4 clones on Desktop: system1, system2, system3, system4
.\New-AppClones.ps1 -Count 4

# Or with custom names:
.\New-AppClones.ps1 -Names system1,systemx,systemy,systemz
```

---

## Folder Layout Created

By default on your Desktop:

```
C:\Users\<you>\Desktop\whatsapp_accounts\
├── all_datas_of_system1\
│   ├── BrowserProfile\       <- 100% isolated cookies, sessions, cache
│   │   └── Default\Preferences (preconfigured: download folder pinned)
│   ├── Downloads\            <- ALL downloads from account 1 land here
│   └── Launch.cmd            <- Launches this single clone
├── all_datas_of_system2\
│   ├── BrowserProfile\
│   ├── Downloads\
│   └── Launch.cmd
├── all_datas_of_systemx\
│   └── ...
├── WhatsApp - system1.lnk    <- Shortcuts to each clone
├── WhatsApp - system2.lnk
└── Launch-All.cmd            <- One click opens EVERY clone at once
```

---

## How to Log In

1. Open `WhatsApp - system1.lnk` (or run `all_datas_of_system1\Launch.cmd`).
2. Scan the QR code with phone #1.
3. Open `WhatsApp - system2.lnk`.
4. Scan the QR code with phone #2.
5. Repeat for system3, system4, etc.

Because `--user-data-dir` points to each clone's own folder, **sessions persist across reboots**. You only scan once per account.

---

## Other Apps (Telegram, Discord, Slack, etc.)

The script also supports classic Win32 and Electron `.exe` apps via `-Mode Exe`:

```powershell
# Telegram Desktop (native multi-instance via -workdir)
.\New-AppClones.ps1 -AppName Telegram -Mode Exe `
    -ExePath "$env:APPDATA\Telegram Desktop\Telegram.exe" `
    -ExeArgs '-workdir "%C%Home"' `
    -Count 3

# Slack / Discord / other Electron apps
.\New-AppClones.ps1 -AppName Slack -Mode Exe `
    -ExePath "$env:LOCALAPPDATA\slack\slack.exe" `
    -ElectronUserDataDir `
    -Count 2
```

In `Exe` mode, `Launch.cmd` isolates the process by redirecting:
* `USERPROFILE` -> `<clone>\Home`
* `APPDATA` -> `<clone>\Home\AppData\Roaming`
* `LOCALAPPDATA` -> `<clone>\Home\AppData\Local`
* `TEMP` / `TMP` -> `<clone>\Temp`

---

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Count` | int | `4` | Number of clones to generate (`system1..systemN`) |
| `-Names` | string[] | — | Explicit clone names (e.g. `system1,systemx,systemy`) |
| `-Root` | string | `<Desktop>\<app>_accounts` | Parent folder holding all clones |
| `-AppName` | string | `WhatsApp` | App display name |
| `-Prefix` | string | `system` | Name prefix when using `-Count` |
| `-FolderPrefix` | string | `all_datas_of_` | Subfolder prefix |
| `-Mode` | Web \| Exe | `Web` | `Web` (Chromium app window) or `Exe` (redirected env) |
| `-Browser` | Auto \| Edge \| Chrome \| Brave | `Auto` | Browser engine for `Web` mode |
| `-Url` | string | `https://web.whatsapp.com` | Web target URL |
| `-DesktopShortcuts` | switch | `false` | Also drop shortcuts directly onto the Windows Desktop |
| `-Launch` | switch | `false` | Launch all clones immediately after creation |

