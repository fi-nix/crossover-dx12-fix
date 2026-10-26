#!/bin/bash
#
# Apply Apple's Game Porting Toolkit 4 (D3DMetal 4.0b2) to CrossOver.
#
# CrossOver 26.3 ships D3DMetal 3.0, under which UE 5.6 titles (Satisfactory,
# StarRupture) die during renderer init with:
#
#   Assertion failed: GGlobalSamplerDescriptorHeapSize <= MaximumSamplerHeapSize
#   [Engine\Source\Runtime\D3D12RHI\Private\D3D12Device.cpp] [Line: 372]
#
# D3DMetal 4 reports the sampler descriptor heap limits UE 5.6 expects, so DX12
# initializes. Every CrossOver update reverts the swap -- re-run this script.
#
# The procedure is Apple's own, from the Read Me inside the GPTK 4 disk image.
# The payload must be extracted to gptk4-b2/lib/ first -- see README.md,
# "First-time setup".
#
# Usage:
#   ./reapply-gptk4.sh              apply (idempotent)
#   ./reapply-gptk4.sh --status     report what is installed, change nothing
#   ./reapply-gptk4.sh --dry-run    print the plan, change nothing
#
# BOTTLE_NAME=<name> targets a bottle other than "Satisfactory".
#
# Requires the calling terminal to hold System Settings -> Privacy & Security ->
# App Management. Without it every write fails with "Operation not permitted",
# and sudo does NOT help. See README.md.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$HERE/common.sh"

MODE="apply"
case "${1:-}" in
    --status)  MODE="status" ;;
    --dry-run) MODE="dry-run" ;;
    "")        ;;
    *) echo "usage: $(basename "$0") [--status|--dry-run]" >&2; exit 2 ;;
esac

[ -d "$GPTK" ] || die "CrossOver apple_gptk not found: $GPTK"

CURRENT="$(d3dmetal_version_at "$GPTK")"

# ---------------------------------------------------------------- status ----
if [ "$MODE" = "status" ]; then
    printf 'CrossOver      %s\n' "$CXVER"
    printf 'D3DMetal       %s   (want %s)\n' "$CURRENT" "$WANT"
    printf 'payload        %s\n' \
        "$([ -d "$PAYLOAD" ] && d3dmetal_version_at "$PAYLOAD" || echo 'MISSING - see README "First-time setup"')"
    if backup_ok; then
        printf 'stock backup   %s (D3DMetal %s)\n' "$(basename "$BACKUP")" "$(d3dmetal_version_at "$BACKUP")"
    elif [ -d "$BACKUP" ]; then
        printf 'stock backup   %s INCOMPLETE\n' "$(basename "$BACKUP")"
    else
        printf 'stock backup   none for this CrossOver version\n'
    fi
    printf 'nvngx bridge   %s\n' \
        "$([ -e "$GPTK/wine/x86_64-windows/nvngx.dll" ] && echo present || echo absent)"
    printf 'bottle         %s\n' \
        "$([ -d "$SYS32" ] && echo "$BOTTLE_NAME" || echo "$BOTTLE_NAME (NOT FOUND)")"
    printf 'bottle nvngx   %s\n' \
        "$([ -e "$SYS32/nvngx.dll" ] && echo present || echo absent)"
    printf 'CrossOver      %s\n' "$(cx_running && echo running || echo 'not running')"
    printf 'wineserver     %s\n' "$(wine_running && echo running || echo 'not running')"
    if [ "$CURRENT" = "$WANT" ]; then
        printf '\n=> patched\n'
    else
        printf '\n=> NOT patched -- run %s\n' "$(basename "$0")"
    fi
    exit 0
fi

info "CrossOver $CXVER, D3DMetal $CURRENT (want $WANT), bottle $BOTTLE_NAME"

[ "$CXVER" != "unknown" ] || die "cannot read CrossOver's version from $CROSSOVER/Contents/Info.plist"
[ -d "$PAYLOAD" ] || die "payload missing: $PAYLOAD (see 'First-time setup' in README.md)"
PAYLOAD_VER="$(d3dmetal_version_at "$PAYLOAD")"
[ "$PAYLOAD_VER" = "$WANT" ] \
    || die "payload is D3DMetal $PAYLOAD_VER but WANT=$WANT -- update WANT in common.sh"

if [ "$CURRENT" = "$WANT" ]; then
    info "already patched - nothing to do."
    exit 0
fi

# Leftover .old dirs mean an earlier swap was interrupted (or done by hand).
# They may be the only stock copy, so never touch them without a backup.
if ! backup_ok && has_old; then
    die "found external.old / wine.old but no complete backup - run ./revert-gptk4.sh first"
fi

if [ "$MODE" = "dry-run" ]; then
    step "would do:"
    cx_running && info "quit CrossOver"
    backup_ok || info "back up stock apple_gptk (D3DMetal $CURRENT) -> $(basename "$BACKUP")"
    info "swap in D3DMetal $WANT from gptk4-b2/lib/"
    info "rename nvngx-on-metalfx.{so,dll} -> nvngx.{so,dll}"
    info "copy ${BOTTLE_DLLS[*]} into bottle $BOTTLE_NAME's system32 (existing files kept as *$SAVED_SUFFIX)"
    exit 0
fi

quit_crossover

# ------------------------------------------------------------- back up ----
# One pristine copy per CrossOver version, kept outside the app bundle so a
# CrossOver reinstall cannot take it with it. Written to .partial first so an
# interrupted copy is never mistaken for a good one.
if ! backup_ok; then
    [ "$CURRENT" != "none" ] || die "apple_gptk has no D3DMetal and there is no backup - reinstall CrossOver"
    step "Backing up stock apple_gptk (D3DMetal $CURRENT)"
    rm -rf "$BACKUP" "$BACKUP.partial"
    ditto "$GPTK" "$BACKUP.partial"
    rm -rf "$BACKUP.partial/external.old" "$BACKUP.partial/wine.old"
    mv "$BACKUP.partial" "$BACKUP"
    backup_ok || die "backup did not verify: $BACKUP"
    info "-> $(basename "$BACKUP")"
fi

# ---------------------------------------------------------------- swap ----
step "Installing D3DMetal $WANT"
cd "$GPTK"
rm -rf external.old wine.old   # safe: a verified backup exists
if [ -e external ]; then mv external external.old; fi
if [ -e wine ];     then mv wine     wine.old;     fi
# ditto, not cp: preserves the x86_64-unix/*.so symlinks into libd3dshared.dylib
ditto "$PAYLOAD/" .
info "swapped (previous kept in place as external.old / wine.old)"

# Apple's Read Me: enable the experimental DLSS -> MetalFX bridge.
# Note: does not actually engage for Satisfactory -- see README.md limitations.
if [ -e wine/x86_64-unix/nvngx-on-metalfx.so ]; then
    mv wine/x86_64-unix/nvngx-on-metalfx.so wine/x86_64-unix/nvngx.so
fi
if [ -e wine/x86_64-windows/nvngx-on-metalfx.dll ]; then
    mv wine/x86_64-windows/nvngx-on-metalfx.dll wine/x86_64-windows/nvngx.dll
fi
info "nvngx bridge enabled"

if [ -d "$SYS32" ]; then
    for f in "${BOTTLE_DLLS[@]}"; do
        # Keep whatever was there unless it is already our copy (a re-apply).
        if [ -e "$SYS32/$f" ] && [ ! -e "$SYS32/$f$SAVED_SUFFIX" ] \
            && ! cmp -s "$SYS32/$f" "wine/x86_64-windows/$f"; then
            mv "$SYS32/$f" "$SYS32/$f$SAVED_SUFFIX"
            info "kept existing $f as $f$SAVED_SUFFIX"
        fi
        cp "wine/x86_64-windows/$f" "$SYS32/$f"
    done
    info "installed ${BOTTLE_DLLS[*]} into bottle $BOTTLE_NAME"
else
    warn "bottle not found at $BOTTLE - skipped system32 copy (set BOTTLE_NAME?)"
fi

# --------------------------------------------------------------- verify ----
step "Verifying"
NOW="$(d3dmetal_version_at "$GPTK")"
[ "$NOW" = "$WANT" ] || die "D3DMetal reports '$NOW', expected '$WANT'"
codesign -v "$GPTK/external/D3DMetal.framework" 2>/dev/null \
    || die "D3DMetal signature invalid"
info "D3DMetal $NOW active, signature valid."

cat <<EOF

Done. Before launching:
  - bottle graphics engine must be D3DMetal (not DXVK/DXMT)
  - Steam launch options: -dx12 -NOTEXTURESTREAMING
First launch rebuilds the shader cache and will be slow. Use FSR or XeSS for
upscaling; DLSS does not work under D3DMetal. See README.md.
EOF
