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

case "$TRIPLET" in
    aarch64-linux-musl)
        BB_ARCH=aarch64
        MAKE_ARCH=arm64
        ;;
    x86_64-linux-musl)
        BB_ARCH=x86_64
        MAKE_ARCH=x86_64
        ;;
    arm-linux-musleabihf)
        BB_ARCH=armhf
        MAKE_ARCH=arm
        ;;
    i686-linux-musl)
        BB_ARCH=x86
        MAKE_ARCH=x86
        ;;
    *)
        echo "unsupported BusyBox musl triplet: $TRIPLET" >&2
        exit 2
        ;;
esac

SCRIPT_DIR="$(cd "$REPO" && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/build-bb.sh"

if [ ! -f "$BUILD_SCRIPT" ]; then
    echo "BusyBox build script not found: $BUILD_SCRIPT" >&2
    exit 1
fi

# Keep this wrapper aligned with busybox-droidspaces/build-bb.sh.
#
# We intentionally do not call build-bb.sh verbatim here because the current
# script is developer-interactive: it checks for every supported compiler,
# runs menuconfig, and then builds every architecture.  The CI matrix installs
# one musl toolchain per job and needs one deterministic artifact.
#
# The important part is that we consume the same in-tree droidspaces.config
# and use the same build flags as build-bb.sh's build_arch() function.
TC_BIN="$(dirname "$(command -v "$TRIPLET-gcc")")"

if [ -f "$SCRIPT_DIR/$CONFIG" ]; then
    CONFIG_PATH="$SCRIPT_DIR/$CONFIG"
elif [ -f "$SCRIPT_DIR/configs/$CONFIG" ]; then
    CONFIG_PATH="$SCRIPT_DIR/configs/$CONFIG"
elif [ -f "$CONFIG" ]; then
    CONFIG_PATH="$CONFIG"
else
    echo "BusyBox config not found: $CONFIG" >&2
    echo "Expected the in-house BusyBox config, normally droidspaces.config." >&2
    exit 1
fi

echo "BusyBox repo:      $SCRIPT_DIR"
echo "BusyBox script:    $BUILD_SCRIPT"
echo "BusyBox config:    $CONFIG_PATH"
echo "BusyBox arch:      $BB_ARCH"
echo "BusyBox make ARCH: $MAKE_ARCH"
echo "BusyBox triplet:   $TRIPLET"
echo "BusyBox tc bin:    $TC_BIN"

cd "$SCRIPT_DIR"

make clean >/dev/null 2>&1 || true

echo "using droidspaces BusyBox config as the base config"
cp "$CONFIG_PATH" .config

# The initramfs must not depend on a dynamic loader.  build-bb.sh also passes
# CONFIG_STATIC=y on the make command line; keep the copied config honest too
# so diagnostics are less surprising.
if grep -q '^# CONFIG_STATIC is not set' .config; then
    sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
elif ! grep -q '^CONFIG_STATIC=y' .config; then
    printf '\nCONFIG_STATIC=y\n' >> .config
fi

OPT_CFLAGS="-flto -Os -ffunction-sections -fdata-sections"
OPT_LDFLAGS="-flto -Wl,--gc-sections"

echo "building BusyBox with droidspaces build-bb.sh flags"
make \
    ARCH="$MAKE_ARCH" \
    CROSS_COMPILE="$TC_BIN/$TRIPLET-" \
    AR="$TC_BIN/$TRIPLET-gcc-ar" \
    NM="$TC_BIN/$TRIPLET-gcc-nm" \
    CONFIG_STATIC=y \
    CONFIG_STRIP_STRIPPED=y \
    EXTRA_CFLAGS="$OPT_CFLAGS" \
    EXTRA_LDFLAGS="$OPT_LDFLAGS" \
    -j"$(nproc)"

test -x busybox || { echo "BusyBox build did not produce ./busybox" >&2; exit 1; }
mkdir -p "$(dirname "$OUTPUT")"
cp busybox "$OUTPUT"
chmod 0755 "$OUTPUT"

"$TRIPLET-strip" -s "$OUTPUT" 2>/dev/null || true
file "$OUTPUT"

echo "BusyBox applet sanity check"
"$OUTPUT" --list | grep -x sh >/dev/null
"$OUTPUT" --list | grep -x mount >/dev/null
"$OUTPUT" --list | grep -x tar >/dev/null
"$OUTPUT" --list | grep -x losetup >/dev/null || {
    echo "warning: losetup applet is not enabled; sparse image import may require it later" >&2
