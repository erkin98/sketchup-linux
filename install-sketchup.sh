#!/usr/bin/env bash
# SketchUp on Linux — Steam + GE-Proton Setup Script
# Based on: https://grosan.co.uk/how-to-run-sketchup-2025-on-linux-using-steam-and-ge-proton/
# Credit:   Grosan Flaviu Gheorghe

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
GE_PROTON_VERSION="${GE_PROTON_VERSION:-GE-Proton10-25}"
SKETCHUP_VERSION="${SKETCHUP_VERSION:-SketchUp 2026}"  # change to "SketchUp 2025" if needed
GE_PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${GE_PROTON_VERSION}/${GE_PROTON_VERSION}.tar.gz"

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}✓${NC}  $*"; }
info() { echo -e "${BLUE}i${NC}  $*"; }
warn() { echo -e "${YELLOW}!${NC}  $*"; }
die()  { echo -e "${RED}✗  $*${NC}" >&2; exit 1; }
step() { echo -e "\n${BOLD}${BLUE}── $* ──────────────────────────────────────────${NC}"; }
pause(){ echo; read -rp "  [Press Enter to continue]  "; echo; }

# ── Global cleanup ───────────────────────────────────────────────────────────
_CLEANUP_DIRS=()
cleanup() {
    for d in "${_CLEANUP_DIRS[@]+"${_CLEANUP_DIRS[@]}"}"; do
        rm -rf "$d"
    done
}
trap cleanup EXIT

# ── Steam path detection ─────────────────────────────────────────────────────
detect_steam() {
    local flatpak_path="$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
    local native_path1="$HOME/.local/share/Steam"
    local native_path2="$HOME/.steam/steam"
    local snap_path="$HOME/snap/steam/common/.steam/steam"

    if [[ -d "$flatpak_path" ]]; then
        STEAM_BASE="$flatpak_path"
        PROTONTRICKS_CMD=("flatpak" "run" "com.github.Matoking.protontricks")
        STEAM_TYPE="flatpak"
    elif [[ -d "$native_path1" ]]; then
        STEAM_BASE="$native_path1"
        PROTONTRICKS_CMD=("protontricks")
        STEAM_TYPE="native"
    elif [[ -d "$native_path2" ]]; then
        STEAM_BASE="$native_path2"
        PROTONTRICKS_CMD=("protontricks")
        STEAM_TYPE="native"
    elif [[ -d "$snap_path" ]]; then
        STEAM_BASE="$snap_path"
        PROTONTRICKS_CMD=("protontricks")
        STEAM_TYPE="snap"
    else
        die "Steam not found in any standard location. Install Steam first."
    fi

    COMPAT_TOOLS="$STEAM_BASE/compatibilitytools.d"
    COMPAT_DATA="$STEAM_BASE/steamapps/compatdata"
    COMPAT_LOG="$STEAM_BASE/logs/compat_log.txt"
}

# ── Phase 0: Preflight ───────────────────────────────────────────────────────
preflight() {
    step "Phase 0: Preflight"

    detect_steam
    log "Steam found ($STEAM_TYPE): $STEAM_BASE"

    if [[ "$STEAM_TYPE" == "flatpak" ]]; then
        flatpak list 2>/dev/null | grep -q "com.github.Matoking.protontricks" || {
            warn "Protontricks (Flatpak) not found. Installing..."
            flatpak install -y flathub com.github.Matoking.protontricks
        }
    else
        command -v protontricks &>/dev/null || die "protontricks not found. Install it from your package manager."
    fi
    log "Protontricks ready: ${PROTONTRICKS_CMD[*]}"

    command -v curl &>/dev/null || die "curl not found. Install curl."
    command -v tar  &>/dev/null || die "tar not found."
    log "curl and tar available"
}

# ── Phase 1: Install GE-Proton ───────────────────────────────────────────────
install_ge_proton() {
    step "Phase 1: Install GE-Proton ($GE_PROTON_VERSION)"

    mkdir -p "$COMPAT_TOOLS"

    if [[ -d "$COMPAT_TOOLS/$GE_PROTON_VERSION" ]]; then
        log "$GE_PROTON_VERSION already installed at $COMPAT_TOOLS/$GE_PROTON_VERSION"
        return
    fi

    info "Downloading from GitHub..."
    local tmp
    tmp=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmp")

    # --fail: treat HTTP errors (404 etc.) as failures instead of silently writing HTML
    curl -L --fail --progress-bar "$GE_PROTON_URL" \
        -o "$tmp/${GE_PROTON_VERSION}.tar.gz" \
        || die "Download failed. Check that $GE_PROTON_VERSION exists at:
    $GE_PROTON_URL"

    tar -xzf "$tmp/${GE_PROTON_VERSION}.tar.gz" -C "$COMPAT_TOOLS/"
    log "Extracted to $COMPAT_TOOLS/$GE_PROTON_VERSION"

    echo
    warn "GE-Proton installed. Close Steam completely (Steam menu → Exit or Ctrl+Q)."
    warn "Relaunch Steam, then press Enter."
    pause
}

# ── Phase 2: Get APP ID ──────────────────────────────────────────────────────
get_app_id() {
    step "Phase 2: Create Proton Prefix & Get APP ID"

    # Record log size BEFORE user action so we only scan NEW entries afterward
    local log_offset=0
    if [[ -f "$COMPAT_LOG" ]]; then
        log_offset=$(wc -l < "$COMPAT_LOG")
    fi

    echo "  You need to do these steps in Steam:"
    echo "  (We create a throwaway entry to generate a Proton prefix and get its APP ID.)"
    echo
    echo "  1. Games → Add a Non-Steam Game"
    echo "     Set executable to: /usr/bin/ls"
    echo "     (Browse... → type /usr/bin/ls manually)"
    echo
    echo "  2. Open the 'ls' app properties → Compatibility"
    echo "     Enable: Force the use of a specific compatibility tool"
    echo "     Select: $GE_PROTON_VERSION"
    echo
    echo "  3. Close Properties. LAUNCH the 'ls' app."
    echo "     It will close instantly — that is fine."
    echo
    pause

    info "Detecting APP ID from Steam log (only scanning new entries)..."

    local app_id=""
    if [[ -f "$COMPAT_LOG" ]]; then
        # tail from AFTER the pre-recorded offset — avoids stale IDs from old sessions
        app_id=$(tail -n +"$((log_offset + 1))" "$COMPAT_LOG" 2>/dev/null \
                 | grep -oP 'release session\(s\) for appID \K[0-9]+' 2>/dev/null \
                 | tail -1 || true)
    fi

    # Fallback: newest compat data dir created after we started watching
    if [[ -z "$app_id" && -d "$COMPAT_DATA" ]]; then
        local marker
        marker=$(mktemp)
        _CLEANUP_DIRS+=("$marker")
        local recent
        recent=$(find "$COMPAT_DATA" -maxdepth 1 -mindepth 1 -type d -newer "$marker" 2>/dev/null \
                 | sort -V | tail -1 | xargs basename 2>/dev/null || true)
        if [[ "$recent" =~ ^[0-9]+$ ]]; then
            app_id="$recent"
        fi
    fi

    if [[ -n "$app_id" ]]; then
        log "Auto-detected APP ID: $app_id"
        local confirm
        read -rp "  Is this correct? [y/N]: " confirm
        if [[ "${confirm,,}" != "y" ]]; then
            app_id=""
        fi
    fi

    if [[ -z "$app_id" ]]; then
        info "Could not auto-detect. Check the log manually:"
        info "  tail -f \"$COMPAT_LOG\""
        info "  Look for: OnAppLifetimeNotification: release session(s) for appID XXXXXXXXXX"
        read -rp "  Enter APP ID: " app_id
    fi

    [[ "$app_id" =~ ^[0-9]+$ ]] || die "Invalid APP ID: $app_id"
    APP_ID="$app_id"

    PROTON_PREFIX="$COMPAT_DATA/$APP_ID/pfx"
    DRIVE_C="$PROTON_PREFIX/drive_c"
    PROG_FILES="$DRIVE_C/Program Files"
    SYS32="$DRIVE_C/windows/system32"
    SKETCHUP_DEST="$PROG_FILES/$SKETCHUP_VERSION/SketchUp"

    log "APP ID: $APP_ID"
    log "Proton prefix: $PROTON_PREFIX"
}

# ── Phase 3: Copy SketchUp files ─────────────────────────────────────────────
copy_sketchup_files() {
    step "Phase 3: Copy SketchUp Files"

    # Skip if already done
    if [[ -f "$SKETCHUP_DEST/SketchUp.exe" ]]; then
        warn "SketchUp files already present at destination."
        local redo
        read -rp "  Re-copy? [y/N]: " redo
        [[ "${redo,,}" == "y" ]] || { log "Skipping file copy."; return; }
    fi

    echo "  Provide the path to the SketchUp folder from your Windows install."
    echo "  This is the folder that contains SketchUp.exe."
    echo
    echo "  Examples:"
    echo "    /mnt/windows/Program Files/SketchUp/$SKETCHUP_VERSION/SketchUp"
    echo "    /path/to/vm-share/$SKETCHUP_VERSION/SketchUp"
    echo
    read -rp "  Path to folder containing SketchUp.exe: " src_path

    # Strip trailing slash
    src_path="${src_path%/}"

    [[ -d "$src_path" ]] || die "Directory not found: $src_path"
    [[ -f "$src_path/SketchUp.exe" ]] || die "SketchUp.exe not found in: $src_path"

    # Remove stale destination to avoid old DLL contamination
    if [[ -d "$SKETCHUP_DEST" ]]; then
        info "Removing existing destination to prevent stale file conflicts..."
        rm -rf "$SKETCHUP_DEST"
    fi
    mkdir -p "$SKETCHUP_DEST"

    info "Copying files from: $src_path"
    info "          to:       $SKETCHUP_DEST"
    info "(This may take several minutes for large installs...)"
    cp -a "$src_path/." "$SKETCHUP_DEST/"

    # Verify the copy succeeded
    [[ -f "$SKETCHUP_DEST/SketchUp.exe" ]] || die "Copy failed — SketchUp.exe not found at destination."
    log "SketchUp files copied."
}

# ── Phase 4: Install dependencies ────────────────────────────────────────────
install_deps() {
    step "Phase 4: Install Dependencies (Protontricks)"

    info "Installing: mfc140 vcrun2019 corefonts d3dx9_43 d3dcompiler_43 uiautomation..."
    "${PROTONTRICKS_CMD[@]}" "$APP_ID" mfc140 vcrun2019 corefonts d3dx9_43 d3dcompiler_43 uiautomation \
        || die "Protontricks failed. Try running manually:
    ${PROTONTRICKS_CMD[*]} $APP_ID mfc140 vcrun2019 corefonts d3dx9_43 d3dcompiler_43 uiautomation"

    info "Setting Windows version to win10..."
    "${PROTONTRICKS_CMD[@]}" "$APP_ID" win10 \
        || warn "Setting Windows version failed — continuing anyway."

    log "Dependencies installed."
}

# ── Phase 5: Fix missing DLLs ────────────────────────────────────────────────
fix_dlls() {
    step "Phase 5: Fix Missing DLLs"

    local copied=0
    local failed=0

    for pattern in "msvcp140*.dll" "vcruntime140*.dll"; do
        # Use mapfile to safely handle filenames with spaces
        local dll_files=()
        mapfile -t dll_files < <(find "$SYS32" -maxdepth 1 -name "$pattern" 2>/dev/null || true)

        if (( ${#dll_files[@]} > 0 )); then
            cp -- "${dll_files[@]}" "$SKETCHUP_DEST/"
            ((copied++))
        else
            warn "No files matching $pattern found in system32 — may need manual copy later."
            ((failed++))
        fi
    done

    if (( failed > 0 )); then
        warn "$failed DLL pattern(s) not found. If SketchUp fails to start, manually copy"
        warn "msvcp140*.dll and vcruntime140*.dll from another source into:"
        warn "  $SKETCHUP_DEST/"
    else
        log "All DLLs copied successfully."
    fi
}

# ── Phase 6: First run (expected crash) ──────────────────────────────────────
first_run() {
    step "Phase 6: First Test Run (Expected Crash)"

    # Locate wine64 by search rather than assuming exact GE-Proton internal layout
    local wine64
    wine64=$(find "$COMPAT_TOOLS/$GE_PROTON_VERSION" -name "wine64" -type f 2>/dev/null | head -1 || true)
    [[ -n "$wine64" ]] || die "wine64 not found inside $COMPAT_TOOLS/$GE_PROTON_VERSION"

    warn "SketchUp will CRASH on first launch — this is EXPECTED."
    warn "It reverts to the classic rendering engine automatically."
    warn "You may see a brief black window or nothing at all."
    warn "After ~10 seconds (or when the process closes), press Enter."
    echo

    # Pass WINEPREFIX inline — no export needed
    WINEPREFIX="$PROTON_PREFIX" \
    PROTON_USE_WINED3D=0 \
    DISABLE_VK_LAYER_VALVE_steam_overlay_1=1 \
    WINEDEBUG=+loaddll \
    "$wine64" "$SKETCHUP_DEST/SketchUp.exe" &>/tmp/sketchup-first-run.log &

    local wine_pid=$!
    pause

    # Only kill if still running (avoids "no such process" noise)
    if kill -0 "$wine_pid" 2>/dev/null; then
        kill "$wine_pid" 2>/dev/null || true
    fi
    wait "$wine_pid" 2>/dev/null || true

    log "First run complete. Classic engine fallback triggered."
}

# ── Phase 7: Print Steam launch config ───────────────────────────────────────
print_steam_config() {
    step "Phase 7: Configure Steam Launch Entry"

    # Use the computed SKETCHUP_DEST for both Flatpak and native — always correct
    local target="$SKETCHUP_DEST/SketchUp.exe"
    local start_in="$SKETCHUP_DEST/"
    local launch_opts="PROTON_USE_WINED3D=0 DISABLE_VK_LAYER_VALVE_steam_overlay_1=1 WINEDEBUG=+loaddll %command%"

    local config_file="$HOME/sketchup-steam-config.txt"
    cat > "$config_file" <<EOF
# SketchUp Steam Launch Configuration
# Generated by install-sketchup.sh
# ─────────────────────────────────────────────────────────
# In Steam, edit the 'ls' non-Steam game entry:
#   Right-click → Properties

Name:           $SKETCHUP_VERSION
Target:         $target
Start In:       $start_in
Launch Options: $launch_opts

# ─────────────────────────────────────────────────────────
# Niri shortcut (replace YOUR_GAME_ID with the Steam shortcut ID):
# Mod+k { spawn "steam" "steam://rungameid/YOUR_GAME_ID"; }
#
# If nothing shows on Wayland: enable the niri X11 add-on.
# ─────────────────────────────────────────────────────────
# Extension bug on startup:
# Uninstall faulty extension → Reinstall → Deactivate → Reactivate
EOF

    echo
    echo -e "${BOLD}  Paste these values into Steam → Properties for your 'ls' app:${NC}"
    echo
    echo -e "  ${BOLD}Rename app to:${NC}  $SKETCHUP_VERSION"
    echo -e "  ${BOLD}Target:${NC}         $target"
    echo -e "  ${BOLD}Start In:${NC}       $start_in"
    echo -e "  ${BOLD}Launch Options:${NC} $launch_opts"
    echo
    log "Config also saved to: $config_file"
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo
    echo -e "${BOLD}${BLUE}  SketchUp on Linux — Steam + GE-Proton Installer${NC}"
    echo -e "  Version: ${SKETCHUP_VERSION} | Proton: ${GE_PROTON_VERSION}"
    echo -e "  Override: SKETCHUP_VERSION=\"SketchUp 2025\" $0"
    echo

    preflight
    install_ge_proton
    get_app_id
    copy_sketchup_files
    install_deps
    fix_dlls
    first_run
    print_steam_config

    step "Done"
    log "$SKETCHUP_VERSION is ready."
    echo
    info "Launch from Steam using the entry you just configured."
    info "On niri with Wayland issues, enable the X11 compatibility add-on."
    echo
}

main "$@"
