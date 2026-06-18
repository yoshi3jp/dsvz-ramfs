#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ARCH=
URL=
OUTPUT=

usage() {
    cat <<USAGE
usage: $0 --arch <arm64|x86_64> --url <artifact-url> --output <directory>
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --url) URL="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$ARCH" in
    arm64|x86_64) ;;
    *) echo "unsupported ARCH: $ARCH" >&2; exit 2 ;;
esac

[ -n "$URL" ] || { echo "--url is required" >&2; exit 2; }
[ -n "$OUTPUT" ] || { echo "--output is required" >&2; exit 2; }

mkdir -p "$OUTPUT"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT INT TERM

ARCHIVE="$TMPDIR/kernel.tar.zst"

echo "fetching vz-kernel artifact for $ARCH"
echo "url: $URL"
case "$URL" in
    file://*) cp "${URL#file://}" "$ARCHIVE" ;;
    *) curl -fsSL "$URL" -o "$ARCHIVE" ;;
esac

mkdir -p "$TMPDIR/extract"
tar -C "$TMPDIR/extract" -xf "$ARCHIVE"

if [ -f "$TMPDIR/extract/SHA256SUMS" ]; then
    echo "verifying SHA256SUMS"
    (cd "$TMPDIR/extract" && sha256sum -c SHA256SUMS)
fi

if [ ! -f "$TMPDIR/extract/kernel" ]; then
    echo "kernel artifact does not contain canonical ./kernel" >&2
    find "$TMPDIR/extract" -maxdepth 2 -type f -print >&2
    exit 1
fi

cp "$TMPDIR/extract/kernel" "$OUTPUT/kernel"
chmod 0644 "$OUTPUT/kernel"

for extra in bzImage Image config System.map kernel-info.plist SHA256SUMS; do
    if [ -e "$TMPDIR/extract/$extra" ]; then
        cp "$TMPDIR/extract/$extra" "$OUTPUT/$extra"
    fi
done

file "$OUTPUT/kernel" || true
echo "created $OUTPUT/kernel"
