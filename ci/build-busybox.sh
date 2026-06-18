#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

REPO=
TRIPLET=
CONFIG=droidspaces.config
OUTPUT=

usage() {
    cat <<USAGE
usage: $0 --repo <path> --triplet <triplet> --config <config-path> --output <path>
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo) REPO="$2"; shift 2 ;;
        --triplet) TRIPLET="$2"; shift 2 ;;
        --config) CONFIG="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$REPO" ] || { echo "--repo is required" >&2; exit 2; }
[ -n "$TRIPLET" ] || { echo "--triplet is required" >&2; exit 2; }
[ -n "$OUTPUT" ] || { echo "--output is required" >&2; exit 2; }
[ -d "$REPO" ] || { echo "repo not found: $REPO" >&2; exit 1; }
command -v "$TRIPLET-gcc" >/dev/null 2>&1 || { echo "$TRIPLET-gcc not found in PATH" >&2; exit 1; }

cd "$REPO"

make distclean >/dev/null 2>&1 || true

if [ -f "$CONFIG" ]; then
    cp "$CONFIG" .config
elif [ -f "configs/$CONFIG" ]; then
    cp "configs/$CONFIG" .config
else
    echo "BusyBox config not found: $CONFIG" >&2
    echo "Set BUSYBOX_CONFIG in the workflow if the in-house config has a different path." >&2
    exit 1
fi

# The initramfs must not depend on a dynamic loader.
if grep -q '^# CONFIG_STATIC is not set' .config; then
    sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
elif ! grep -q '^CONFIG_STATIC=y' .config; then
    printf '\nCONFIG_STATIC=y\n' >> .config
fi

make olddefconfig
make -j"$(nproc)" CROSS_COMPILE="$TRIPLET-" CC="$TRIPLET-gcc"

test -x busybox || { echo "BusyBox build did not produce ./busybox" >&2; exit 1; }
mkdir -p "$(dirname "$OUTPUT")"
cp busybox "$OUTPUT"
chmod 0755 "$OUTPUT"

"$TRIPLET-strip" -s "$OUTPUT" 2>/dev/null || true
file "$OUTPUT"
