# 🚀 BOB - Deployment Guide

Complete guide to install and run BOB on a new machine.

## 📋 Prerequisites

### System Requirements
- **Operating System**: Windows 10/11 (required - PowerShell scripts use Win32 API)
- **RAM**: 4GB minimum
- **Disk**: 500MB free space

### Required Software

#### 1. Node.js 18+
Download and install from: https://nodejs.org/

Verify installation:
```powershell
node --version  # Should show v18.x.x or higher
npm --version   # Should show 9.x.x or higher
```

#### 2. Rust
Required for building Tauri applications.

**Install via rustup:**
```powershell
# Download and run installer from:
# https://www.rust-lang.org/tools/install

# Or use winget:
winget install Rustlang.Rust.MSVC
```

Verify installation:
```powershell
rustc --version  # Should show rustc 1.7x.x or higher
cargo --version
```

#### 3. Visual Studio Build Tools (for Rust)
Required for compiling native code on Windows.

```powershell
# Install via winget:
winget install Microsoft.VisualStudio.2022.BuildTools

# Or download from:
# https://visualstudio.microsoft.com/visual-cpp-build-tools/
```

During installation, select:
- "Desktop development with C++"
- Windows 10/11 SDK

#### 4. PowerShell 5.1+
Already included in Windows 10/11. Verify:
```powershell
$PSVersionTable.PSVersion
```

---

## 🔧 Installation

### Step 1: Clone the Repository
```powershell
git clone https://github.com/TimeKast/bob.git
cd bob
```

### Step 2: Install Dependencies
```powershell
npm install
```

### Step 3: Run in Development Mode
```powershell
npm run tauri dev
```

The app will compile and open. First compilation takes 2-5 minutes.

---

## 🏗️ Building for Production

### Create Executable
```powershell
npm run tauri build
```

The installer will be created at:
```
src-tauri/target/release/bundle/msi/bob_x.x.x_x64_en-US.msi
```

### Install the App
Run the MSI installer or copy the executable from:
```
src-tauri/target/release/bob.exe
```

---

## ⚙️ Configuration

### First Run Setup

1. **Scan for Instances**: Click "🔍 Scan" to detect VS Code windows with Antigravity
2. **Configure Discord Webhook** (optional): Go to Settings → Discord Webhook URL
3. **Set Default Prompt**: The prompt sent when chat is ready
4. **Set Max Retries**: Number of retry attempts before notifying Discord (default: 3)

### Project Structure Requirements

For backlog tracking to work, your projects should have:
```
your-project/
└── docs/
    └── backlog/
        └── v1.0/           # or any vX.X version folder
            └── issues/
                ├── ISSUE-001.md
                ├── ISSUE-002.md
                └── ...
```

Issue files should contain `Status: ✅ Done` or `Status: Done` when completed.

---

## 🎮 Usage

### Basic Workflow

1. Open VS Code windows with Antigravity extension active
2. Run BOB
3. Click "🔍 Scan" to detect instances
4. Toggle ON the instances you want to automate
5. Click "▶️ Start" to begin auto-monitoring

### What the Monitor Does

- **Detects UI State**: Scans for Accept buttons, Retry buttons, chat input
- **Auto-Clicks Accept**: Clicks "Accept all" for file changes
- **Auto-Clicks Accept Dialog**: Sends Alt+Enter for command confirmations
- **Auto-Sends Prompts**: When chat is ready (gray button), sends configured prompt
- **Handles Errors**: Clicks Retry up to max attempts, then notifies Discord
- **Tracks Progress**: Shows completed/total issues from backlog

---

## 🔧 Troubleshooting

### "Rust not found"
```powershell
# Reinstall Rust
rustup self update
rustup update
```

### "Build failed - linker not found"
Install Visual Studio Build Tools with C++ workload.

### "PowerShell scripts not executing"
```powershell
# Run as Administrator:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "Window not detected"
- Ensure VS Code window title contains "Antigravity"
- Try clicking "🔍 Scan" again
- Check that Antigravity extension is active in VS Code

### "Click not working"
- The monitor needs to bring windows to foreground
- Avoid using mouse/keyboard during automation
- Consider running in a VM or secondary monitor

---

## 📁 File Structure

```
bob/
├── src/                        # Frontend (Svelte + TypeScript)
│   ├── routes/+page.svelte     # Main dashboard
│   └── lib/
│       ├── InstanceCard.svelte # Instance UI component
│       ├── Settings.svelte     # Settings panel
│       ├── store.ts            # State management
│       └── types.ts            # TypeScript types
├── src-tauri/                  # Backend (Rust)
│   └── src/lib.rs              # Tauri commands
├── scripts/                    # PowerShell automation
│   ├── detect-ui-state.ps1     # UI detection
│   ├── click-button.ps1        # Mouse click
│   ├── write-to-chat.ps1       # Send prompts
│   ├── accept-dialog.ps1       # Alt+Enter
│   ├── scroll-to-bottom.ps1    # Scroll handling
│   └── read-backlog.ps1        # Backlog parsing
└── package.json
```

---

## 🔗 Links

- **Repository**: https://github.com/TimeKast/bob
- **Tauri Documentation**: https://tauri.app/
- **Rust Installation**: https://www.rust-lang.org/tools/install

---

## 📝 License

MIT License - See LICENSE file for details.
