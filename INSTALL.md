# SketchUp 2026 on Linux — Step-by-Step Guide

> **Method:** Steam (Flatpak / APT / Snap) + GE-Proton
> **Credit:** [Grosan Flaviu Gheorghe](https://grosan.co.uk/how-to-run-sketchup-2025-on-linux-using-steam-and-ge-proton/)
> **Confirmed working:** Feb 2026

---

## Before You Start

**You need:**
- A Linux machine (Ubuntu 22.04+ or equivalent)
- A Windows machine or VM with SketchUp 2026 already installed
- Steam installed (Flatpak, APT, or Snap — all supported)
- Internet access

**What works / doesn't work:**

| Feature | Status |
|-|-|
| Modeling, save, load | ✅ Works |
| Classic rendering engine | ✅ Works |
| Extensions (after fix) | ✅ Works |
| New AI Render / DX12 engine | ❌ Crashes |
| Direct `.exe` installer | ❌ Fails |
| Bottles / Lutris | ❌ Not working |

---

## Step 1 — Install Steam and Enable Steam Play

Choose one of these methods:

### Option A — Ubuntu Software Center (easiest)

Open **Ubuntu Software Center**, search for **Steam**, and install it.

### Option B — APT

```bash
sudo apt install steam-installer
```

### Option C — Flatpak (recommended for this guide)

```bash
# Install Flatpak support if not already present
sudo apt install flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Install Steam
flatpak install flathub com.valvesoftware.Steam
```

> Full guide: https://itsfoss.com/install-steam-ubuntu-linux/

> **Steam path by install method:**
>
> | Method | Steam base path |
> |-|-|
> | Flatpak | `~/.var/app/com.valvesoftware.Steam/.local/share/Steam/` |
> | APT / native | `~/.local/share/Steam/` |
> | Snap | `~/snap/steam/common/.steam/steam/` |
>
> The script auto-detects your install. For the manual steps below, substitute your actual path.

### Enable Steam Play

Open Steam → **Settings → Compatibility**
Enable: **"Enable Steam Play for all other titles"**

---

## Step 2 — Install GE-Proton

Download **GE-Proton10-25** from:
https://github.com/GloriousEggroll/proton-ge-custom/releases

Extract it to the compatibilitytools directory:

```bash
mkdir -p ~/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d/

tar -xzf GE-Proton10-25.tar.gz \
  -C ~/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d/
```

**Restart Steam.**

> Or use the automated installer script instead of steps 1–6:
> ```bash
> ./install-sketchup.sh
> ```

---

## Step 3 — Create a Dummy Steam Entry

In Steam: **Games → Add a Non-Steam Game**

- Click **Browse**
- Type the path manually: `/usr/bin/ls`
- Click **Add Selected Programs**

---

## Step 4 — Set GE-Proton for the Dummy App

In your Steam library, find the `ls` entry.
Right-click → **Properties → Compatibility**

- Check: **Force the use of a specific Steam Play compatibility tool**
- Select: **GE-Proton10-25**

Close Properties.

---

## Step 5 — Watch the Log for Your APP ID

**Important:** Start watching the log BEFORE you launch the dummy app — this way you only
see the new entry and won't confuse it with IDs from previous sessions.

```bash
tail -f ~/.var/app/com.valvesoftware.Steam/.local/share/Steam/logs/compat_log.txt
```

> If the file is not found:
> ```bash
> find ~/ -name compat_log.txt 2>/dev/null
> ```

Leave this terminal open.

---

## Step 6 — Launch the Dummy App

Back in Steam, click **Play** on the `ls` entry.

It closes instantly — that is expected.

In your terminal you will now see a line like:

```
OnAppLifetimeNotification: release session(s) for appID 3255798437
```

**Note that number — this is your APP ID.** You can now close the tail command (Ctrl+C).

---

## Step 7 — Copy SketchUp Files from Windows

On your Windows machine, SketchUp is installed at:
```
C:\Program Files\SketchUp\SketchUp 2026\SketchUp\
```

Copy that `SketchUp` folder to your Linux machine (USB, shared folder, scp, etc.).

Then place it inside the Proton prefix:

```bash
# Replace 3255798437 with your actual APP ID
APP_ID=3255798437
DEST="$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/compatdata/$APP_ID/pfx/drive_c/Program Files/SketchUp 2026/SketchUp"

# Remove old files first to avoid stale DLL contamination on re-runs
rm -rf "$DEST"
mkdir -p "$DEST"

# -a preserves metadata and handles hidden files correctly
cp -a /path/to/your/SketchUp/. "$DEST/"

# Verify it worked
ls "$DEST/SketchUp.exe" && echo "OK"
```

After this the structure should be:
```
drive_c/
  Program Files/
    SketchUp 2026/
      SketchUp/
        SketchUp.exe   ← must exist here
```

---

## Step 8 — Install Dependencies with Protontricks

Install Protontricks if not already installed:

```bash
flatpak install flathub com.github.Matoking.protontricks
```

Then install required Windows libraries:

```bash
APP_ID=3255798437   # replace with yours

flatpak run com.github.Matoking.protontricks $APP_ID \
  mfc140 vcrun2019 corefonts d3dx9_43 d3dcompiler_43 uiautomation

flatpak run com.github.Matoking.protontricks $APP_ID win10
```

---

## Step 9 — Fix Missing DLLs

Navigate to the SketchUp directory inside the prefix:

```bash
APP_ID=3255798437   # replace with yours
SKETCHUP_DIR="$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/compatdata/$APP_ID/pfx/drive_c/Program Files/SketchUp 2026/SketchUp"
SYS32="$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/compatdata/$APP_ID/pfx/drive_c/windows/system32"

# Use find + loop to safely handle any filenames with spaces
find "$SYS32" -maxdepth 1 -name "msvcp140*.dll" -exec cp -- {} "$SKETCHUP_DIR/" \;
find "$SYS32" -maxdepth 1 -name "vcruntime140*.dll" -exec cp -- {} "$SKETCHUP_DIR/" \;
```

> **If you see errors like `MSVCP140_1.dll not found`** when launching later, the DLL
> is corrupt. Copy a fresh copy from your Windows machine's `System32` folder.

---

## Step 10 — First Launch (Crash is Expected)

Run SketchUp once from the terminal. It will crash — this triggers the automatic
fallback to the classic rendering engine:

```bash
APP_ID=3255798437   # replace with yours
COMPAT_TOOLS="$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d"
PREFIX="$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/compatdata/$APP_ID/pfx"
SKETCHUP_EXE="$PREFIX/drive_c/Program Files/SketchUp 2026/SketchUp/SketchUp.exe"

# Locate wine64 by search — handles any GE-Proton internal layout
WINE64=$(find "$COMPAT_TOOLS/GE-Proton10-25" -name "wine64" -type f | head -1)

# Pass WINEPREFIX inline (no export — avoids polluting the shell session)
WINEPREFIX="$PREFIX" \
PROTON_USE_WINED3D=0 \
DISABLE_VK_LAYER_VALVE_steam_overlay_1=1 \
WINEDEBUG=+loaddll \
"$WINE64" "$SKETCHUP_EXE"
```

You may see a brief black window or nothing at all. After it crashes or closes, proceed.

> `PROTON_USE_WINED3D=0` — required; enables DX12 support via Proton

---

## Step 11 — Configure the Steam Launch Entry

In Steam, right-click the `ls` entry → **Properties**:

**Rename** the app to: `SketchUp 2026`

The paths depend on your Steam install type. Run this to print the exact values:

```bash
APP_ID=3255798437   # replace with yours
SKETCHUP_DIR="$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/compatdata/$APP_ID/pfx/drive_c/Program Files/SketchUp 2026/SketchUp"
echo "Target:         $SKETCHUP_DIR/SketchUp.exe"
echo "Start In:       $SKETCHUP_DIR/"
echo "Launch Options: PROTON_USE_WINED3D=0 DISABLE_VK_LAYER_VALVE_steam_overlay_1=1 WINEDEBUG=+loaddll %command%"
```

Copy those values into Steam Properties:

| Field | Value |
|-|-|
| Target | output from above |
| Start In | output from above |
| Launch Options | `PROTON_USE_WINED3D=0 DISABLE_VK_LAYER_VALVE_steam_overlay_1=1 WINEDEBUG=+loaddll %command%` |

Click **Close**.

You can now launch SketchUp from Steam.

---

## Troubleshooting

### Extension error dialog on startup

If an extension crashes and shows an error window every time SketchUp opens:

1. Open **Window → Extension Manager**
2. Uninstall the faulty extension
3. Reinstall it
4. Deactivate it, then Reactivate it

It will work normally after that.

### DLL errors at launch

If you see `MSVCP140_1.dll not found` in terminal output:

Copy the DLLs directly from your Windows machine's `C:\Windows\System32\` into the
SketchUp directory inside the Proton prefix (same as Step 9).

### Nothing appears on screen (Wayland / niri)

Wine apps may not show on Wayland compositors. On **niri**, install the X11 add-on:

```
# In your niri config:
# Enable xwayland
```

Or use the `DISPLAY` variable to force X11 output.

---

## Launching with a Keyboard Shortcut (niri)

Find your Steam game ID (visible in the Steam URL or Properties).

Add to your niri config:

```
Mod+k { spawn "steam" "steam://rungameid/YOUR_GAME_ID"; }
```

---

## Automation

All steps from 2 onwards can be run with the included script:

```bash
./install-sketchup.sh

# For SketchUp 2025:
SKETCHUP_VERSION="SketchUp 2025" ./install-sketchup.sh
```

Steps 3–4 (Steam GUI) still require manual action — Steam has no CLI for adding
non-Steam games. The script pauses and guides you through them.
