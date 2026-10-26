#!/bin/bash
#
# Restore CrossOver's stock D3DMetal, undoing reapply-gptk4.sh.
#
# Expect DX12 to crash again afterward with the GGlobalSamplerDescriptorHeapSize
# assertion -- that is the point of reverting, not a failure. See README.md.
#
# Restore sources, in order of preference:
#   1. backup-stock-apple_gptk-CX<version>/  (kept outside the app bundle)
#   2. external.old / wine.old               (left in place by the swap)
#
# Usage:
#   ./revert-gptk4.sh              restore stock D3DMetal
#   ./revert-gptk4.sh --dry-run    print the plan, change nothing
#
# BOTTLE_NAME=<name> targets a bottle other than "Satisfactory".
#
# Requires App Management permission for the calling terminal -- see README.md.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$HERE/common.sh"

DRY=0
case "${1:-}" in
    --dry-run) DRY=1 ;;
    "")        ;;
    *) echo "usage: $(basename "$0") [--dry-run]" >&2; exit 2 ;;
esac

[ -d "$GPTK" ] || die "CrossOver apple_gptk not found: $GPTK"

CURRENT="$(d3dmetal_version_at "$GPTK")"
info "CrossOver $CXVER, D3DMetal currently $CURRENT, bottle $BOTTLE_NAME"

# A CrossOver update already put stock libraries back; only the bottle needs
# cleaning up.
if [ "$CURRENT" != "$WANT" ] && [ "$CURRENT" != "none" ] && ! has_old; then
    SRC="none"; SRC_DESC="nothing - bundle is already stock"
    STOCK_VER="$CURRENT"
elif backup_ok; then
    SRC="$BACKUP"; SRC_DESC="backup: $(basename "$BACKUP")"
    STOCK_VER="$(d3dmetal_version_at "$SRC")"
elif [ -d "$GPTK/external.old" ] && [ -d "$GPTK/wine.old" ]; then
    SRC="inplace"; SRC_DESC="in-place external.old / wine.old"
    STOCK_VER="$(plist_version "$GPTK/external.old/D3DMetal.framework/Resources/Info.plist" unknown)"
else
    die "no restore source found - reinstall CrossOver to get stock libraries back"
fi
info "restore source: $SRC_DESC"
info "would restore D3DMetal $STOCK_VER"

if [ "$DRY" = "1" ]; then
    step "would do:"
    cx_running && info "quit CrossOver"
    [ "$SRC" = "none" ] || info "restore external/ and wine/ from $SRC_DESC"
    info "restore or remove ${BOTTLE_DLLS[*]} in bottle $BOTTLE_NAME's system32"
    exit 0
fi

quit_crossover

# Put the bottle back first, while the GPTK copies are still around to compare
# against. Only files that match a GPTK copy are deleted.
GPTK_DLL_DIRS=("$GPTK/wine/x86_64-windows" "$PAYLOAD/wine/x86_64-windows")
is_gptk_copy() {
    local f="$1" d
    for d in "${GPTK_DLL_DIRS[@]}"; do
        cmp -s "$SYS32/$f" "$d/$f" && return 0
        [ "$f" = nvngx.dll ] && cmp -s "$SYS32/$f" "$d/nvngx-on-metalfx.dll" && return 0
    done
    return 1
}

if [ -d "$SYS32" ]; then
    step "Cleaning up bottle $BOTTLE_NAME"
    for f in "${BOTTLE_DLLS[@]}"; do
        if [ -e "$SYS32/$f$SAVED_SUFFIX" ]; then
            mv -f "$SYS32/$f$SAVED_SUFFIX" "$SYS32/$f"
            info "restored original $f"
        elif [ -e "$SYS32/$f" ]; then
            if is_gptk_copy "$f"; then
                rm -f "$SYS32/$f"
                info "removed $f"
            else
                warn "left $SYS32/$f alone - not a GPTK copy"
            fi
        fi
    done
fi

if [ "$SRC" != "none" ]; then
    step "Restoring stock D3DMetal $STOCK_VER"
    cd "$GPTK"
    if [ "$SRC" = "inplace" ]; then
        rm -rf external wine
        mv external.old external
        mv wine.old     wine
    else
        rm -rf external wine external.old wine.old
        ditto "$SRC/" .
    fi
    info "restored."
fi

step "Verifying"
NOW="$(d3dmetal_version_at "$GPTK")"
[ "$NOW" != "none" ] || die "no D3DMetal present after restore - reinstall CrossOver"
[ "$NOW" != "$WANT" ] || die "D3DMetal still reports $WANT after restore"
info "D3DMetal $NOW active."

cat <<EOF

Reverted. DX12 will crash again in UE 5.6 titles; use -DX11 in the Steam launch
options as a stopgap, or re-run ./reapply-gptk4.sh to go back to D3DMetal 4.
EOF
