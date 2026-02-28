# sketchup-linux

[![ShellCheck](https://github.com/erkin98/sketchup-linux/actions/workflows/ci.yml/badge.svg)](https://github.com/erkin98/sketchup-linux/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Bash 5+](https://img.shields.io/badge/Bash-5%2B-green.svg)](https://www.gnu.org/software/bash/)
[![SketchUp 2026](https://img.shields.io/badge/SketchUp-2026-orange.svg)](https://www.sketchup.com/)

**Automated installer that runs SketchUp 2026 (and 2025) on Linux via Steam + GE-Proton.**

No native Linux build exists — this script wires up the only confirmed working method:
Steam + GE-Proton. Plain Wine, Bottles, and Lutris do not work.

> Credit: [Grosan Flaviu Gheorghe](https://grosan.co.uk/how-to-run-sketchup-2025-on-linux-using-steam-and-ge-proton/)
> for discovering and documenting the original technique.

---

## What works

| Feature | Status |
|-|-|
| Modeling, save, load | ✅ Works |
| Classic rendering engine | ✅ Works |
| Extensions (after fix) | ✅ Works |
| New AI Render / DX12 engine | ❌ Crashes |
| Direct `.exe` installer | ❌ Fails |
| Bottles / Lutris | ❌ Not working |

---

## Prerequisites

- Linux (Ubuntu 22.04+, Fedora, Arch, or equivalent)
- **Steam** installed — Flatpak, APT, Snap, or native
- **A Windows machine or VM** with SketchUp already installed (to copy files from)
- Internet access (to download GE-Proton)

The script auto-detects your Steam installation type.

---

## Quick start

```bash
git clone https://github.com/erkin98/sketchup-linux.git
cd sketchup-linux
chmod +x install.sh
./install.sh
```

The script walks you through each step interactively, pausing at the two Steam GUI steps that cannot be automated.

---

## Usage

```
./install.sh [OPTIONS]

OPTIONS
  -h, --help                 Show help and exit
  -V, --version              Print version and exit
  -n, --dry-run              Preview all actions without making changes
  -v, --verbose              Enable debug output
      --no-pause             Skip interactive pauses
      --app-id ID            Provide Steam APP ID (skips Phase 2)
      --src PATH             SketchUp source folder containing SketchUp.exe
      --skip-phase N         Skip phase N (0-7). Repeatable.
      --phase N              Run only phase N in isolation
      --ge-proton VERSION    GE-Proton version (default: GE-Proton10-25)
      --sketchup-version V   SketchUp version string (default: SketchUp 2026)
```

### Examples

```bash
# Full interactive install
./install.sh

# Preview without making any changes
./install.sh --dry-run

# Fully non-interactive (supply APP ID and source path)
./install.sh --app-id 4294185554 --src "/mnt/win/SketchUp 2026/SketchUp" --no-pause

# SketchUp 2025
./install.sh --sketchup-version "SketchUp 2025"

# Re-run only the DLL fix phase
./install.sh --app-id 4294185554 --phase 5

# Skip phases already completed
./install.sh --app-id 4294185554 --skip-phase 1 --skip-phase 2 --src "/mnt/..."
```

---

## Phases

| # | Phase | Manual step? |
|-|-|-|
| 0 | Preflight checks | No |
| 1 | Download & install GE-Proton | No |
| 2 | Create Proton prefix & detect APP ID | **Yes — 3 clicks in Steam** |
| 3 | Copy SketchUp files from Windows | No (interactive path prompt) |
| 4 | Install Windows dependencies (Protontricks) | No |
| 5 | Fix missing DLLs | No |
| 6 | First run (expected crash triggers classic engine) | **Yes — press Enter when it closes** |
| 7 | Print Steam launch configuration | No |

Phases 2 and 6 require brief manual interaction in Steam or terminal. The script pauses and explains each step clearly.

---

## Config file

Persistent defaults can be stored in `~/.config/sketchup-linux/config`:

```bash
GE_PROTON_VERSION="GE-Proton10-25"
SKETCHUP_VERSION="SketchUp 2026"
APP_ID_OVERRIDE="4294185554"
SKETCHUP_SRC="/mnt/win/Program Files/SketchUp/SketchUp 2026/SketchUp"
```

The script also saves the detected APP ID to `~/.cache/sketchup-linux/state`
so you don't need to re-run Phase 2 after the first install.

---

## Logs

Every run writes a timestamped log to:

```
~/.cache/sketchup-linux/install-YYYYMMDD-HHMMSS.log
```

Attach this file to bug reports.

---

## Troubleshooting

### Extension error dialog on startup

1. Open **Window → Extension Manager**
2. Uninstall the faulty extension
3. Reinstall it
4. Deactivate → Reactivate

### DLL errors at launch (`MSVCP140_1.dll not found`)

Re-run Phase 5:

```bash
./install.sh --app-id YOUR_APP_ID --phase 5
```

If the error persists, copy the DLLs directly from your Windows machine's
`C:\Windows\System32\` into the SketchUp directory inside the Proton prefix.

### Blank screen (Wayland / niri)

Wine apps may not display on some Wayland compositors. On **niri**, enable the X11 add-on.
On other compositors, try setting `DISPLAY=:0` before launching Steam.

### App ID not auto-detected

Run this in a terminal before clicking Play in Steam:

```bash
tail -f ~/.var/app/com.valvesoftware.Steam/.local/share/Steam/logs/compat_log.txt
```

Look for: `OnAppLifetimeNotification: release session(s) for appID XXXXXXXXXX`

---

## Keyboard shortcut (niri)

After completing setup, add to your niri config (replace `YOUR_GAME_ID` with the
numeric ID visible in Steam → Properties):

```
Mod+k { spawn "steam" "steam://rungameid/YOUR_GAME_ID"; }
```

---

## Manual installation

Prefer doing it step by step? See [INSTALL.md](INSTALL.md) for the full manual guide.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License

MIT — see [LICENSE](LICENSE).
