#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

REPO=
TARGET=
TRIPLET=
ENABLE_SOCKETD_BACKEND=0
OUTPUT=

usage() {
    cat <<USAGE
usage: $0 --repo <path> --target <aarch64|x86_64> --triplet <triplet> --enable-socketd-backend <0|1> --output <path>
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo) REPO="$2"; shift 2 ;;
        --target) TARGET="$2"; shift 2 ;;
        --triplet) TRIPLET="$2"; shift 2 ;;
        --enable-socketd-backend) ENABLE_SOCKETD_BACKEND="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$REPO" ] || { echo "--repo is required" >&2; exit 2; }
[ -n "$TARGET" ] || { echo "--target is required" >&2; exit 2; }
[ -n "$TRIPLET" ] || { echo "--triplet is required" >&2; exit 2; }
[ -n "$OUTPUT" ] || { echo "--output is required" >&2; exit 2; }
[ -d "$REPO" ] || { echo "repo not found: $REPO" >&2; exit 1; }
command -v "$TRIPLET-gcc" >/dev/null 2>&1 || { echo "$TRIPLET-gcc not found in PATH" >&2; exit 1; }

case "$ENABLE_SOCKETD_BACKEND" in
    0|1) ;;
    *) echo "--enable-socketd-backend must be 0 or 1" >&2; exit 2 ;;
esac

cd "$REPO"
make clean || true
MUSL_CROSS="$(dirname "$(command -v "$TRIPLET-gcc")")" \
    make "$TARGET" ENABLE_SOCKETD_BACKEND="$ENABLE_SOCKETD_BACKEND"

test -x output/droidspaces || { echo "Droidspaces build did not produce output/droidspaces" >&2; exit 1; }
mkdir -p "$(dirname "$OUTPUT")"
cp output/droidspaces "$OUTPUT"
chmod 0755 "$OUTPUT"

"$TRIPLET-strip" -s "$OUTPUT" 2>/dev/null || true
file "$OUTPUT"
