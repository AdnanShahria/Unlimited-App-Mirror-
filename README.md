# App Mirror — Multi-Account & Workspace Cloner for Windows

Run unlimited, strictly isolated copies ("clones") of any app on Windows side-by-side. Every clone lives in its own root folder with **zero connection** between their logins, cookies, cache, local profiles, and downloads.

Designed for business, power users, and multi-account operators. **Self-contained, portable, and requires no administrator privileges.**

---

## What Does "App Mirror" Do?

When you run multiple accounts of an app (like WhatsApp, Discord, Telegram, or Antigravity/VS Code) on Windows, the operating system normally forces them to share the same login session, cache, and `%APPDATA%` folders, resulting in repeated logins and logouts.

**App Mirror** eliminates this by creating independent sandboxed directories for each account:

```text
C:\Users\<You>\Desktop\whatsapp_accounts\
├── all_datas_of_system1\    <-- Account #1 (Own cookies, session, & Downloads)
├── all_datas_of_system2\    <-- Account #2 (Own cookies, session, & Downloads)
├── all_datas_of_system3\    <-- Account #3 (Own cookies, session, & Downloads)
├── all_datas_of_system4\    <-- Account #4 (Own cookies, session, & Downloads)
├── WhatsApp - Open All.lnk  <-- Opens all 4 accounts with one click
├── WhatsApp - Close All.lnk <-- Safely closes only these accounts
└── READ ME.txt              <-- Portable documentation
```

---

## Sharing With Friends & Team Members

**You only need to send a single file:**
> 📁 **`App-Mirror.bat`**

* **100% Self-Contained:** Contains the wizard, the isolation engine, process manager, and shortcut generator inside one `.bat` file.
* **No Dependencies:** Runs on standard Windows 10 & 11 using built-in PowerShell 5.1+. No Python, Node.js, or external runtimes required.
* **No Admin Rights:** Operates entirely within standard user permissions.
* **Non-Destructive:** Existing accounts and personal browser tabs are never touched or closed.

---

## How to Use: Step-by-Step

Double-click **`App-Mirror.bat`** to open the interactive terminal wizard:

### 1. Which App Do You Want to Clone?
You can provide any of the following:
* **App Name:** Type `whatsapp`, `telegram`, or `antigravity` to automatically detect your installed applications.
* **Drag-and-Drop:** Drag any desktop `.exe` or shortcut (`.lnk`) directly into the terminal window.
* **Folder Path:** Paste the path to any portable app folder.
* **Website URL:** Paste any web app URL (e.g., `https://web.whatsapp.com` or `https://chatgpt.com`).

> **Note on Microsoft Store (MSIX) Apps:**  
> Windows Store apps (including native WhatsApp Desktop from the Store) are locked by Microsoft to a single account per Windows user. When App Mirror detects a Store app, it automatically switches to the app's official Web Application mode, giving you isolated, borderless native desktop windows with zero session cross-over.

---

### 2. "Installed" vs. "Not Installed" (Portable)

When cloning desktop `.exe` applications, App Mirror asks:

| Mode | What It Means | Disk Usage | Best For |
| :--- | :--- | :--- | :--- |
| **Installed** | Clones reuse your existing installed program files (`C:\Program Files\...`), but **redirect all user data, settings, sessions, and downloads** into each clone's separate folder. | Minimal (~5–50 MB per clone) | Standard installed programs, Antigravity IDE, VS Code, Discord, Slack. |
| **Not Installed** | Useful for portable apps or apps not in your system directories. App Mirror **copies the entire program folder** into each clone directory so each clone is 100% standalone and portable. | Medium (App size × number of clones) | Portable software, standalone tools, or standalone utilities on a USB drive. |

---

### 3. Choose Clone Names & Count
* **By Count:** Enter a number (e.g. `4`) and a base name (e.g. `system` or `account`) &rarr; Generates `all_datas_of_system1` through `all_datas_of_system4`.
* **By Name:** Enter specific names separated by commas (e.g. `work, personal, support`).

---

### 4. Choose Storage & Shortcuts
* **Destination:** Defaults to `Desktop\<app>_accounts`, or choose any custom drive/folder (e.g., `D:\MyAccounts`).
* **Shortcuts:** Place launch shortcuts directly on your **Desktop**, inside the **Clones Folder**, in the **Start Menu**, or in a custom folder.

---

## Managing Existing Clones

Launch **`App-Mirror.bat`** and select **`[2] Manage my clones`** to:
1. **View Disk Usage:** Monitor real-time folder sizes (MB) for each account.
2. **Check Running Status:** See which accounts are currently active.
3. **Add More Clones:** Add `system5` without overwriting or logging out existing accounts.
4. **Surgical Close (`Close All` / `Stop.cmd`):** Politely closes running clone processes without touching your regular browser windows or personal apps.
5. **Delete Clones:** Safely delete an individual account's data or remove the entire library cleanly.

---

## Supported App Ecosystem

* **Web & Communication Apps:** WhatsApp, Telegram Web, Discord, Slack, Microsoft Teams, Messenger, Instagram, ChatGPT, Spotify.
* **Developer IDEs & Code Editors:** Google Antigravity IDE, Visual Studio Code, Cursor, Obsidian, Postman.
* **Portable & Win32 Applications:** Telegram Desktop (`-workdir`), OBS Studio (`--portable`), Notepad++, VLC, FileZilla.

---

## Technical Architecture

* **Isolated User Data Directories:** Chromium/Electron `--user-data-dir` partitioning isolates IndexedDB, local storage, WebSockets, and cookies.
* **Environment Variable Redirection:** Diverts `%USERPROFILE%`, `%APPDATA%`, `%LOCALAPPDATA%`, and `%TEMP%` dynamically inside each clone's runtime scope.
* **Automated Preferences Seeding:** Downloads for each clone are pinned to `<clone>\Downloads` via injected JSON preferences.
* **Process Lineage Filtering:** `Stop.cmd` queries Windows WMI (`Win32_Process`) using process path and command-line matching to terminate only instances originating from that clone folder.

---

## License
MIT License. Free to use, modify, and distribute.
