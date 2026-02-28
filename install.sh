#!/usr/bin/env bash
# sketchup-linux — Install SketchUp on Linux via Steam + GE-Proton
# Version: 1.0.0
# Project: https://github.com/erkin98/sketchup-linux
# Credit:  Grosan Flaviu Gheorghe <https://grosan.co.uk/how-to-run-sketchup-2025-on-linux-using-steam-and-ge-proton/>
# License: MIT

set -euo pipefail

# ── Version ───────────────────────────────────────────────────────────────────
readonly VERSION="1.0.0"

# ── Defaults (overridable via config file, environment, or flags) ─────────────
GE_PROTON_VERSION="${GE_PROTON_VERSION:-GE-Proton10-25}"
SKETCHUP_VERSION="${SKETCHUP_VERSION:-SketchUp 2026}"
SKETCHUP_SRC="${SKETCHUP_SRC:-}"        # pre-supply source path (non-interactive)
APP_ID_OVERRIDE="${APP_ID_OVERRIDE:-}"  # pre-supply APP ID (skip Phase 2)
DRY_RUN=0
VERBOSE=0
NO_PAUSE=0
SKIP_PHASES=()
ONLY_PHASE=""

# ── Exit codes ────────────────────────────────────────────────────────────────
readonly E_SUCCESS=0
readonly E_ERROR=1
readonly E_USER_ABORT=2
readonly E_DEP_MISSING=3

# ── Paths ─────────────────────────────────────────────────────────────────────
readonly CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/sketchup-linux/config"
readonly STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/sketchup-linux/state"
LOG_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/sketchup-linux/install-$(date +%Y%m%d-%H%M%S).log"
readonly LOG_FILE

# ── Colors (respects NO_COLOR and non-TTY) ───────────────────────────────────
# https://no-color.org
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
if [[ ! -t 1 ]] || [[ -n "${NO_COLOR:-}" ]]; then
    RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

# ── Logging ───────────────────────────────────────────────────────────────────
_setup_log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    # Tee all stdout/stderr to log file; preserve terminal output
    exec > >(tee -a "$LOG_FILE") 2>&1
}

_ts()   { date '+%H:%M:%S'; }
log()   { echo -e "$(_ts) ${GREEN}✓${NC}  $*"; }
info()  { echo -e "$(_ts) ${BLUE}i${NC}  $*"; }
warn()  { echo -e "$(_ts) ${YELLOW}!${NC}  $*"; }
debug() { (( VERBOSE )) && echo -e "$(_ts) ${BLUE}DBG${NC}  $*" || true; }
step()  { echo -e "\n${BOLD}${BLUE}── $* ──────────────────────────────────────────${NC}"; }

die() {
    echo -e "$(_ts) ${RED}✗  $*${NC}" >&2
    echo -e "$(_ts) ${RED}✗  Log file: $LOG_FILE${NC}" >&2
    exit $E_ERROR
}

die_dep() {
    echo -e "$(_ts) ${RED}✗  $*${NC}" >&2
    exit $E_DEP_MISSING
}

# ── Signal handling ───────────────────────────────────────────────────────────
user_abort() {
    echo -e "\n${YELLOW}Aborted by user.${NC}"
    exit $E_USER_ABORT
}
trap user_abort INT TERM

# ── Cleanup ───────────────────────────────────────────────────────────────────
_CLEANUP_DIRS=()
_cleanup() {
    for d in "${_CLEANUP_DIRS[@]+"${_CLEANUP_DIRS[@]}"}"; do
        rm -rf "$d"
    done
}
trap _cleanup EXIT

# ── Interactive pause ─────────────────────────────────────────────────────────
pause() {
    (( NO_PAUSE )) && return 0
    echo
    read -rp "  [Press Enter to continue or Ctrl+C to abort]  " || user_abort
    echo
}

# ── Dry-run aware executor ────────────────────────────────────────────────────
# Wrap any destructive command with run() so --dry-run previews it safely
run() {
    if (( DRY_RUN )); then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} $*"
    else
        debug "exec: $*"
        "$@"
    fi
}

# ── Phase filter ──────────────────────────────────────────────────────────────
phase_enabled() {
    local phase="$1"
    if [[ -n "$ONLY_PHASE" ]]; then
        [[ "$phase" == "$ONLY_PHASE" ]] && return 0 || return 1
    fi
    local skip
    for skip in "${SKIP_PHASES[@]+"${SKIP_PHASES[@]}"}"; do
        [[ "$skip" == "$phase" ]] && return 1
    done
    return 0
}

# ── Config & state ────────────────────────────────────────────────────────────
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        debug "Loading config: $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    fi
    if [[ -f "$STATE_FILE" ]]; then
        debug "Loading state: $STATE_FILE"
        # shellcheck source=/dev/null
        source "$STATE_FILE"
    fi
}

save_state() {
    local key="$1" value="$2"
    mkdir -p "$(dirname "$STATE_FILE")"
    if [[ -f "$STATE_FILE" ]]; then
        grep -v "^${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi
    printf '%s=%q\n' "$key" "$value" >> "$STATE_FILE"
    debug "State saved: ${key}=${value}"
}

# ── Distro detection ──────────────────────────────────────────────────────────
DISTRO="unknown"
DISTRO_PM="your package manager"

detect_distro() {
    if   command -v apt-get &>/dev/null; then DISTRO="debian";  DISTRO_PM="sudo apt-get install"
    elif command -v dnf     &>/dev/null; then DISTRO="fedora";  DISTRO_PM="sudo dnf install"
    elif command -v pacman  &>/dev/null; then DISTRO="arch";    DISTRO_PM="sudo pacman -S"
    elif command -v zypper  &>/dev/null; then DISTRO="opensuse"; DISTRO_PM="sudo zypper install"
    fi
    debug "Detected distro: $DISTRO (pm: $DISTRO_PM)"
}

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}sketchup-linux v${VERSION}${NC} — Install SketchUp on Linux via Steam + GE-Proton

${BOLD}USAGE${NC}
  ./install.sh [OPTIONS]

${BOLD}OPTIONS${NC}
  -h, --help                 Show this help and exit
  -V, --version              Print version and exit
  -n, --dry-run              Preview all actions without making changes
  -v, --verbose              Enable debug output
      --no-pause             Skip interactive pauses (for use with --app-id/--src)
      --app-id ID            Provide Steam APP ID (skips Phase 2 Steam GUI)
      --src PATH             SketchUp source folder containing SketchUp.exe
      --skip-phase N         Skip phase N (1-7). Repeatable.
      --phase N              Run only phase N in isolation
      --ge-proton VERSION    GE-Proton version to install (default: $GE_PROTON_VERSION)
      --sketchup-version V   SketchUp version string (default: $SKETCHUP_VERSION)

${BOLD}ENVIRONMENT VARIABLES${NC}
  GE_PROTON_VERSION          Override GE-Proton version
  SKETCHUP_VERSION           Override SketchUp version
  APP_ID_OVERRIDE            Same as --app-id
  SKETCHUP_SRC               Same as --src
  NO_COLOR                   Disable colored output (https://no-color.org)

${BOLD}CONFIG FILE${NC}  $CONFIG_FILE
  GE_PROTON_VERSION="GE-Proton10-25"
  SKETCHUP_VERSION="SketchUp 2026"
  APP_ID_OVERRIDE="4294185554"
  SKETCHUP_SRC="/mnt/win/Program Files/SketchUp/SketchUp 2026/SketchUp"

${BOLD}PHASES${NC}
  0  Preflight checks
  1  Install GE-Proton
  2  Detect APP ID  (requires Steam GUI — skippable with --app-id)
  3  Copy SketchUp files
  4  Install Windows dependencies (Protontricks)
  5  Fix missing DLLs
  6  First run — triggers classic engine fallback
  7  Print Steam launch config

${BOLD}EXAMPLES${NC}
  # Full interactive install
  ./install.sh

  # Preview without making changes
  ./install.sh --dry-run

  # Fully non-interactive (known APP ID + source path)
  ./install.sh --app-id 4294185554 --src "/mnt/win/SketchUp 2026/SketchUp" --no-pause

  # SketchUp 2025 with custom GE-Proton version
  ./install.sh --sketchup-version "SketchUp 2025" --ge-proton GE-Proton10-24

  # Skip GE-Proton (already installed) and jump straight to file copy
  ./install.sh --app-id 4294185554 --skip-phase 1 --skip-phase 2 --src "/mnt/win/..."

  # Re-run only the DLL fix phase
  ./install.sh --app-id 4294185554 --phase 5

${BOLD}LOG${NC}
  $LOG_FILE

${BOLD}NOTES${NC}
  Requires SketchUp installed on a Windows machine/VM to copy files from.
  New AI Render engine is not supported — classic engine works fine.
  Bottles and Lutris do not work; only Steam + GE-Proton is confirmed.

  Credit: Grosan Flaviu Gheorghe
          https://grosan.co.uk/how-to-run-sketchup-2025-on-linux-using-steam-and-ge-proton/

EOF
    exit $E_SUCCESS
}

# ── Argument parsing ──────────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)           usage ;;
            -V|--version)        echo "sketchup-linux $VERSION"; exit $E_SUCCESS ;;
            -n|--dry-run)        DRY_RUN=1; shift ;;
            -v|--verbose)        VERBOSE=1; shift ;;
            --no-pause)          NO_PAUSE=1; shift ;;
            --app-id)            [[ -n "${2:-}" ]] || die "--app-id requires a value"
                                 APP_ID_OVERRIDE="$2"; shift 2 ;;
            --src)               [[ -n "${2:-}" ]] || die "--src requires a value"
                                 SKETCHUP_SRC="$2"; shift 2 ;;
            --skip-phase)        [[ "${2:-}" =~ ^[0-7]$ ]] || die "--skip-phase requires a number 0-7"
                                 SKIP_PHASES+=("$2"); shift 2 ;;
            --phase)             [[ "${2:-}" =~ ^[0-7]$ ]] || die "--phase requires a number 0-7"
                                 ONLY_PHASE="$2"; shift 2 ;;
            --ge-proton)         [[ -n "${2:-}" ]] || die "--ge-proton requires a value"
                                 GE_PROTON_VERSION="$2"; shift 2 ;;
            --sketchup-version)  [[ -n "${2:-}" ]] || die "--sketchup-version requires a value"
                                 SKETCHUP_VERSION="$2"; shift 2 ;;
            *)                   die "Unknown option: $1\nRun './install.sh --help' for usage." ;;
        esac
    done
}

# ── Steam path detection ──────────────────────────────────────────────────────
detect_steam() {
    local flatpak_path="$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
    local native_path1="$HOME/.local/share/Steam"
    local native_path2="$HOME/.steam/steam"
    local snap_path="$HOME/snap/steam/common/.steam/steam"

    if   [[ -d "$flatpak_path" ]]; then
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
        return 1
    fi

    COMPAT_TOOLS="$STEAM_BASE/compatibilitytools.d"
    COMPAT_DATA="$STEAM_BASE/steamapps/compatdata"
    COMPAT_LOG="$STEAM_BASE/logs/compat_log.txt"

    debug "Steam type: $STEAM_TYPE"
    debug "Steam base: $STEAM_BASE"
}

# ── Steam installer ───────────────────────────────────────────────────────────
_install_steam() {
    if command -v flatpak &>/dev/null; then
        info "Installing Steam via Flatpak..."
        run flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        run flatpak install -y flathub com.valvesoftware.Steam
        echo
        warn "Steam installed. You must now:"
        warn "  1. Launch Steam:  flatpak run com.valvesoftware.Steam"
        warn "  2. Log in to your Steam account."
        warn "  3. Go to Settings → Compatibility"
        warn "     Enable: 'Enable Steam Play for all other titles'"
        warn "  4. Close Steam completely, then re-run this script."
        exit $E_SUCCESS
    else
        die "Steam not found and Flatpak is not available to install it.
Install Steam manually for your distro:
  Debian/Ubuntu: sudo apt-get install steam-installer
  Arch:          sudo pacman -S steam
  Flatpak:       https://flathub.org/apps/com.valvesoftware.Steam
Then re-run this script."
    fi
}

# ── Phase 0: Preflight ────────────────────────────────────────────────────────
phase_preflight() {
    phase_enabled 0 || return 0
    step "Phase 0: Preflight"

    # Install Steam if not found
    if ! detect_steam 2>/dev/null; then
        warn "Steam not found. Installing..."
        _install_steam
    fi
    detect_steam
    log "Steam ($STEAM_TYPE): $STEAM_BASE"

    if [[ "$STEAM_TYPE" == "flatpak" ]]; then
        if ! flatpak list 2>/dev/null | grep -q "com.github.Matoking.protontricks"; then
            warn "Protontricks (Flatpak) not found. Installing..."
            run flatpak install -y flathub com.github.Matoking.protontricks
        fi
    else
        command -v protontricks &>/dev/null \
            || die_dep "protontricks not found.
Install with: $DISTRO_PM protontricks
Or visit: https://github.com/Matoking/protontricks"
    fi
    log "Protontricks: ${PROTONTRICKS_CMD[*]}"

    command -v curl &>/dev/null \
        || die_dep "curl not found. Install with: $DISTRO_PM curl"
    command -v tar &>/dev/null \
        || die_dep "tar not found. Install with: $DISTRO_PM tar"

    if (( DRY_RUN )); then
        warn "DRY-RUN mode: no changes will be made."
    fi

    log "Preflight passed. Log: $LOG_FILE"
}

# ── Phase 1: Install GE-Proton ────────────────────────────────────────────────
phase_install_ge_proton() {
    phase_enabled 1 || { info "Phase 1 skipped."; return 0; }
    step "Phase 1: Install GE-Proton ($GE_PROTON_VERSION)"

    local ge_url="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${GE_PROTON_VERSION}/${GE_PROTON_VERSION}.tar.gz"

    run mkdir -p "$COMPAT_TOOLS"

    if [[ -d "$COMPAT_TOOLS/$GE_PROTON_VERSION" ]]; then
        log "$GE_PROTON_VERSION already installed."
        return 0
    fi

    if (( DRY_RUN )); then
        info "[DRY-RUN] Would download: $ge_url"
        info "[DRY-RUN] Would extract to: $COMPAT_TOOLS/"
        return 0
    fi

    local tmp
    tmp=$(mktemp -d)
    _CLEANUP_DIRS+=("$tmp")

    info "Downloading $GE_PROTON_VERSION..."
    local http_code
    http_code=$(curl -L --write-out '%{http_code}' --progress-bar \
        "$ge_url" -o "$tmp/${GE_PROTON_VERSION}.tar.gz") \
        || die "Download failed (HTTP $http_code).
Check that '$GE_PROTON_VERSION' is a valid release:
  https://github.com/GloriousEggroll/proton-ge-custom/releases
Or specify a different version with: --ge-proton GE-Proton10-XX"

    if [[ "$http_code" != "200" ]]; then
        die "Download failed (HTTP $http_code). URL: $ge_url"
    fi

    tar -xzf "$tmp/${GE_PROTON_VERSION}.tar.gz" -C "$COMPAT_TOOLS/"
    log "Extracted to $COMPAT_TOOLS/$GE_PROTON_VERSION"

    echo
    warn "GE-Proton installed. Close Steam completely (Steam menu → Exit or Ctrl+Q)."
    warn "Relaunch Steam, then continue."
    pause
}

# ── Phase 2: Get APP ID ───────────────────────────────────────────────────────
phase_get_app_id() {
    phase_enabled 2 || { info "Phase 2 skipped."; return 0; }

    # Use override from flag/env/config/state
    if [[ -n "$APP_ID_OVERRIDE" ]]; then
        APP_ID="$APP_ID_OVERRIDE"
        [[ "$APP_ID" =~ ^[0-9]+$ ]] || die "Invalid APP ID: $APP_ID (must be numeric)"
        info "Using provided APP ID: $APP_ID"
        _set_proton_paths
        return 0
    fi

    step "Phase 2: Create Proton Prefix & Get APP ID"

    # Record log position BEFORE user action to avoid stale IDs
    local log_offset=0
    if [[ -f "$COMPAT_LOG" ]]; then
        log_offset=$(wc -l < "$COMPAT_LOG")
    fi
    debug "Log offset before action: $log_offset"

    echo "  You need to do these steps in Steam:"
    echo "  (This creates a throwaway entry to generate a Proton prefix.)"
    echo
    echo "  1. Games → Add a Non-Steam Game"
    echo "     Set executable to: /usr/bin/ls"
    echo "     (Browse... → type /usr/bin/ls manually)"
    echo
    echo "  2. Open the 'ls' app Properties → Compatibility"
    echo "     Enable: Force the use of a specific compatibility tool"
    echo "     Select: $GE_PROTON_VERSION"
    echo
    echo "  3. Close Properties. LAUNCH the 'ls' app. It closes instantly."
    echo
    pause

    info "Detecting APP ID from log (new entries only)..."

    local app_id=""
    if [[ -f "$COMPAT_LOG" ]]; then
        app_id=$(tail -n +"$((log_offset + 1))" "$COMPAT_LOG" 2>/dev/null \
                 | grep -oP 'release session\(s\) for appID \K[0-9]+' 2>/dev/null \
                 | tail -1 || true)
        debug "grep result: '$app_id'"
    fi

    # Fallback: find newest compat data directory
    if [[ -z "$app_id" && -d "$COMPAT_DATA" ]]; then
        local marker
        marker=$(mktemp)
        _CLEANUP_DIRS+=("$marker")
        local recent
        recent=$(find "$COMPAT_DATA" -maxdepth 1 -mindepth 1 -type d -newer "$marker" 2>/dev/null \
                 | sort -V | tail -1 | xargs basename 2>/dev/null || true)
        if [[ "$recent" =~ ^[0-9]+$ ]]; then
            app_id="$recent"
            debug "Fallback APP ID from find: $app_id"
        fi
    fi

    if [[ -n "$app_id" ]]; then
        log "Auto-detected APP ID: $app_id"
        local confirm
        read -rp "  Is this correct? [y/N]: " confirm
        [[ "${confirm,,}" == "y" ]] || app_id=""
    fi

    if [[ -z "$app_id" ]]; then
        info "Could not auto-detect. Find it manually:"
        info "  tail -f \"$COMPAT_LOG\""
        info "  Look for: OnAppLifetimeNotification: release session(s) for appID XXXXXXXXXX"
        read -rp "  Enter APP ID: " app_id
    fi

    [[ "$app_id" =~ ^[0-9]+$ ]] \
        || die "Invalid APP ID: '$app_id' — must be a numeric value (e.g. 4294185554)"

    APP_ID="$app_id"
    save_state "APP_ID_OVERRIDE" "$APP_ID"
    _set_proton_paths

    log "APP ID: $APP_ID"
    debug "Proton prefix: $PROTON_PREFIX"
}

_set_proton_paths() {
    PROTON_PREFIX="$COMPAT_DATA/$APP_ID/pfx"
    DRIVE_C="$PROTON_PREFIX/drive_c"
    PROG_FILES="$DRIVE_C/Program Files"
    SYS32="$DRIVE_C/windows/system32"
    SKETCHUP_DEST="$PROG_FILES/$SKETCHUP_VERSION/SketchUp"
}

# ── Phase 3: Copy SketchUp files ──────────────────────────────────────────────
phase_copy_sketchup() {
    phase_enabled 3 || { info "Phase 3 skipped."; return 0; }
    step "Phase 3: Copy SketchUp Files"

    # Idempotency: skip if already done and user doesn't want to re-copy
    if [[ -f "$SKETCHUP_DEST/SketchUp.exe" ]] && [[ -z "$SKETCHUP_SRC" ]]; then
        warn "SketchUp files already present at destination."
        local redo
        read -rp "  Re-copy? [y/N]: " redo
        if [[ "${redo,,}" != "y" ]]; then
            log "Skipping file copy."
            return 0
        fi
    fi

    local src_path="$SKETCHUP_SRC"

    if [[ -z "$src_path" ]]; then
        echo "  Provide the path to the SketchUp folder from your Windows install."
        echo "  This is the folder containing SketchUp.exe."
        echo
        echo "  Examples:"
        echo "    /mnt/windows/Program Files/SketchUp/$SKETCHUP_VERSION/SketchUp"
        echo "    /path/to/vm-share/$SKETCHUP_VERSION/SketchUp"
        echo
        read -rp "  Path to folder containing SketchUp.exe: " src_path
    fi

    # Normalize path
    src_path="${src_path%/}"

    [[ -d "$src_path" ]]           || die "Directory not found: $src_path"
    [[ -f "$src_path/SketchUp.exe" ]] || die "SketchUp.exe not found in: $src_path
Make sure you point to the folder containing SketchUp.exe, not its parent."

    # Guard against copying to self
    if [[ "$(realpath "$src_path" 2>/dev/null)" == "$(realpath "$SKETCHUP_DEST" 2>/dev/null)" ]]; then
        die "Source and destination are the same directory: $src_path"
    fi

    if (( DRY_RUN )); then
        info "[DRY-RUN] Would remove: $SKETCHUP_DEST"
        info "[DRY-RUN] Would copy: $src_path → $SKETCHUP_DEST"
        return 0
    fi

    # Remove old destination to prevent stale DLL contamination
    if [[ -d "$SKETCHUP_DEST" ]]; then
        info "Removing old destination to avoid stale file conflicts..."
        rm -rf "$SKETCHUP_DEST"
    fi
    mkdir -p "$SKETCHUP_DEST"

    info "Copying: $src_path"
    info "     to: $SKETCHUP_DEST"

    # Use rsync for progress if available, otherwise fall back to cp
    if command -v rsync &>/dev/null; then
        rsync -ah --info=progress2 "$src_path/" "$SKETCHUP_DEST/"
    else
        info "(This may take several minutes — install rsync for progress output)"
        cp -a "$src_path/." "$SKETCHUP_DEST/"
    fi

    [[ -f "$SKETCHUP_DEST/SketchUp.exe" ]] \
        || die "Copy failed — SketchUp.exe missing at destination: $SKETCHUP_DEST"
    log "SketchUp files copied."
}

# ── Phase 4: Install dependencies ─────────────────────────────────────────────
phase_install_deps() {
    phase_enabled 4 || { info "Phase 4 skipped."; return 0; }
    step "Phase 4: Install Dependencies (Protontricks)"

    local deps=(mfc140 vcrun2019 corefonts d3dx9_43 d3dcompiler_43 uiautomation)

    if (( DRY_RUN )); then
        info "[DRY-RUN] Would run: ${PROTONTRICKS_CMD[*]} $APP_ID ${deps[*]}"
        info "[DRY-RUN] Would run: ${PROTONTRICKS_CMD[*]} $APP_ID win10"
        return 0
    fi

    info "Installing: ${deps[*]}..."
    "${PROTONTRICKS_CMD[@]}" "$APP_ID" "${deps[@]}" \
        || die "Protontricks failed installing dependencies.
Retry manually:
  ${PROTONTRICKS_CMD[*]} $APP_ID ${deps[*]}"

    info "Setting Windows version to win10..."
    "${PROTONTRICKS_CMD[@]}" "$APP_ID" win10 \
        || warn "Setting Windows version failed — continuing anyway."

    log "Dependencies installed."
}

# ── Phase 5: Fix missing DLLs ─────────────────────────────────────────────────
phase_fix_dlls() {
    phase_enabled 5 || { info "Phase 5 skipped."; return 0; }
    step "Phase 5: Fix Missing DLLs"

    local failed=0

    for pattern in "msvcp140*.dll" "vcruntime140*.dll"; do
        local dll_files=()
        mapfile -t dll_files < <(find "$SYS32" -maxdepth 1 -name "$pattern" 2>/dev/null || true)

        if (( ${#dll_files[@]} > 0 )); then
            if (( DRY_RUN )); then
                info "[DRY-RUN] Would copy: ${dll_files[*]} → $SKETCHUP_DEST/"
            else
                cp -- "${dll_files[@]}" "$SKETCHUP_DEST/"
                debug "Copied ${#dll_files[@]} files matching $pattern"
            fi
        else
            warn "No files matching $pattern in system32."
            warn "If SketchUp fails to start, copy them from:"
            warn "  Windows: C:\\Windows\\System32\\${pattern}"
            warn "  Destination: $SKETCHUP_DEST/"
            (( failed++ ))
        fi
    done

    if (( failed == 0 )); then
        log "DLLs copied successfully."
    else
        warn "$failed DLL pattern(s) missing — SketchUp may still work."
    fi
}

# ── Phase 6: First run (expected crash) ───────────────────────────────────────
phase_first_run() {
    phase_enabled 6 || { info "Phase 6 skipped."; return 0; }
    step "Phase 6: First Test Run (Expected Crash)"

    # Locate wine64 by search — handles any GE-Proton internal layout
    local wine64
    wine64=$(find "$COMPAT_TOOLS/$GE_PROTON_VERSION" -name "wine64" -type f 2>/dev/null | head -1 || true)
    [[ -n "$wine64" ]] \
        || die "wine64 not found inside $COMPAT_TOOLS/$GE_PROTON_VERSION
Possible causes:
  - GE-Proton extraction failed (re-run Phase 1)
  - Version mismatch: try --ge-proton with a different version"

    if (( DRY_RUN )); then
        info "[DRY-RUN] Would launch: WINEPREFIX=$PROTON_PREFIX $wine64 SketchUp.exe"
        return 0
    fi

    warn "SketchUp will CRASH on first launch — this is EXPECTED."
    warn "It automatically reverts to the classic rendering engine."
    warn "You may see a brief black window or nothing at all."
    warn "After ~15 seconds (or when it closes), press Enter."
    echo

    local wine_log
    wine_log="/tmp/sketchup-first-run-$(date +%Y%m%d-%H%M%S).log"

    WINEPREFIX="$PROTON_PREFIX" \
    PROTON_USE_WINED3D=0 \
    DISABLE_VK_LAYER_VALVE_steam_overlay_1=1 \
    WINEDEBUG=+loaddll \
    "$wine64" "$SKETCHUP_DEST/SketchUp.exe" &>"$wine_log" &

    local wine_pid=$!
    info "Wine PID: $wine_pid (log: $wine_log)"
    pause

    if kill -0 "$wine_pid" 2>/dev/null; then
        kill "$wine_pid" 2>/dev/null || true
    fi
    wait "$wine_pid" 2>/dev/null || true

    log "First run complete. Classic engine fallback triggered."
    info "Wine log saved to: $wine_log"
}

# ── Phase 7: Print Steam launch config ────────────────────────────────────────
phase_print_config() {
    phase_enabled 7 || { info "Phase 7 skipped."; return 0; }
    step "Phase 7: Configure Steam Launch Entry"

    local target="$SKETCHUP_DEST/SketchUp.exe"
    local start_in="$SKETCHUP_DEST/"
    local launch_opts="PROTON_USE_WINED3D=0 DISABLE_VK_LAYER_VALVE_steam_overlay_1=1 WINEDEBUG=+loaddll %command%"

    local config_out="$HOME/sketchup-steam-config.txt"
    cat > "$config_out" <<EOF
# SketchUp Steam Launch Configuration
# Generated by sketchup-linux v${VERSION} — $(date)
# ─────────────────────────────────────────────────────────────────────────────
# In Steam: right-click the 'ls' entry → Properties
# Rename the entry and set the fields below.

Name:           $SKETCHUP_VERSION
Target:         $target
Start In:       $start_in
Launch Options: $launch_opts

# ─────────────────────────────────────────────────────────────────────────────
# Niri keyboard shortcut (replace YOUR_GAME_ID with the Steam shortcut ID):
# Mod+k { spawn "steam" "steam://rungameid/YOUR_GAME_ID"; }
#
# Wayland / blank screen: enable the niri X11 compatibility add-on.
# ─────────────────────────────────────────────────────────────────────────────
# Extension bug on startup:
# Window → Extension Manager → Uninstall faulty → Reinstall → Deactivate → Reactivate
EOF

    echo
    echo -e "${BOLD}  In Steam, rename the 'ls' entry and paste these values into Properties:${NC}"
    echo
    echo -e "  ${BOLD}Rename to:${NC}      $SKETCHUP_VERSION"
    echo -e "  ${BOLD}Target:${NC}         $target"
    echo -e "  ${BOLD}Start In:${NC}       $start_in"
    echo -e "  ${BOLD}Launch Options:${NC} $launch_opts"
    echo
    log "Config saved to: $config_out"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    _setup_log
    parse_args "$@"
    load_config
    detect_distro

    echo
    echo -e "${BOLD}${BLUE}  sketchup-linux v${VERSION}${NC}"
    echo -e "  SketchUp: ${SKETCHUP_VERSION}  |  Proton: ${GE_PROTON_VERSION}"
    (( DRY_RUN )) && echo -e "  ${YELLOW}DRY-RUN mode — no changes will be made${NC}"
    echo

    phase_preflight
    phase_install_ge_proton
    phase_get_app_id
    phase_copy_sketchup
    phase_install_deps
    phase_fix_dlls
    phase_first_run
    phase_print_config

    step "Complete"
    log "$SKETCHUP_VERSION setup complete."
    info "Launch from Steam using the entry you just configured."
    info "Wayland/niri blank screen: enable the X11 add-on for Wine apps."
    info "Full log: $LOG_FILE"
    echo
}

main "$@"
