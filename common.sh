# Shared by reapply-gptk4.sh and revert-gptk4.sh. Sourced, not executed.
#
# Environment overrides: BOTTLE_NAME=<name> for another bottle,
# BOTTLE=<full path to the bottle> if it is not in the default location
# (e.g. on an external drive), CROSSOVER=<path to CrossOver.app> if it is
# not in /Applications.

CROSSOVER="${CROSSOVER:-/Applications/CrossOver.app}"
GPTK="$CROSSOVER/Contents/SharedSupport/CrossOver/lib64/apple_gptk"
BOTTLE_NAME="${BOTTLE_NAME:-Satisfactory}"
BOTTLE="${BOTTLE:-$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE_NAME}"
SYS32="$BOTTLE/drive_c/windows/system32"
PAYLOAD="$HERE/gptk4-b2/lib"
WANT="4.0b3"

# DLLs the swap copies into the bottle's system32. Anything already there is
# moved aside to <name>$SAVED_SUFFIX first and put back by the revert.
BOTTLE_DLLS=(nvngx.dll nvapi64.dll)
SAVED_SUFFIX=".pre-gptk4"

info() { printf '  %s\n' "$*"; }
step() { printf '\n%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# plist_version <Info.plist> <fallback>
plist_version() {
    plutil -extract CFBundleShortVersionString raw "$1" 2>/dev/null || echo "$2"
}

# d3dmetal_version_at <dir containing external/>
d3dmetal_version_at() {
    plist_version "$1/external/D3DMetal.framework/Resources/Info.plist" none
}

CXVER="$(plist_version "$CROSSOVER/Contents/Info.plist" unknown)"
BACKUP="$HERE/backup-stock-apple_gptk-CX${CXVER}"

# A backup counts only if it finished: written to .partial, then renamed.
backup_ok() {
    [ -d "$BACKUP/external" ] && [ -d "$BACKUP/wine" ] \
        && [ "$(d3dmetal_version_at "$BACKUP")" != "none" ]
}

has_old() { [ -e "$GPTK/external.old" ] || [ -e "$GPTK/wine.old" ]; }

cx_running()   { pgrep -f "$CROSSOVER/Contents/MacOS/CrossOver" >/dev/null 2>&1; }
# Games keep running after the CrossOver UI quits; the libraries we replace are
# loaded by them, so any live wineserver means hands off.
wine_running() { pgrep -x wineserver >/dev/null 2>&1; }

quit_crossover() {
    if cx_running; then
        step "Quitting CrossOver"
        osascript -e 'tell application "CrossOver" to quit' || true
        for _ in $(seq 1 15); do cx_running || break; sleep 1; done
        cx_running && die "CrossOver is still running - quit it and retry."
        info "quit."
    fi
    if wine_running; then
        die "Wine processes are still running (game, Steam?) - quit them and retry."
    fi
}
