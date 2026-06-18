#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

TRIPLET=
ARCH=
RELEASE_API=
DEST="${RUNNER_TEMP:-/tmp}/dsvz-musl-toolchain"

usage() {
    cat <<USAGE
usage: $0 --triplet <triplet> --arch <arm64|x86_64> --release-api <url> [--dest <dir>]
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --triplet) TRIPLET="$2"; shift 2 ;;
        --arch) ARCH="$2"; shift 2 ;;
        --release-api) RELEASE_API="$2"; shift 2 ;;
        --dest) DEST="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$TRIPLET" ] || { echo "--triplet is required" >&2; exit 2; }
[ -n "$ARCH" ] || { echo "--arch is required" >&2; exit 2; }
[ -n "$RELEASE_API" ] || { echo "--release-api is required" >&2; exit 2; }

case "$ARCH" in
    arm64|x86_64) ;;
    *) echo "unsupported arch: $ARCH" >&2; exit 2 ;;
esac

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST"

release_json="$DEST/release.json"
archive="$DEST/toolchain.archive"

curl_args="-fsSL"
if [ -n "${GITHUB_TOKEN:-}" ]; then
    # shellcheck disable=SC2086
    curl $curl_args \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "$RELEASE_API" > "$release_json"
else
    # shellcheck disable=SC2086
    curl $curl_args \
        -H "Accept: application/vnd.github+json" \
        "$RELEASE_API" > "$release_json"
fi

asset_url=$(jq -r --arg triplet "$TRIPLET" --arg arch "$ARCH" '
    .assets[]
    | select(.name | test("\\.(tar\\.gz|tgz|tar\\.xz|txz|tar\\.zst|zip)$"; "i"))
    | select(.name | test($triplet; "i") or test($arch; "i"))
    | .browser_download_url
' "$release_json" | head -n 1)

if [ -z "$asset_url" ] || [ "$asset_url" = "null" ]; then
    echo "no compiler asset found for triplet=$TRIPLET arch=$ARCH" >&2
    echo "available assets:" >&2
    jq -r '.assets[].name' "$release_json" >&2
    exit 1
fi

echo "downloading toolchain asset: $asset_url"
# shellcheck disable=SC2086
curl $curl_args -L "$asset_url" -o "$archive"

checksum_url=$(jq -r --arg url "$asset_url" --arg triplet "$TRIPLET" --arg arch "$ARCH" '
    .assets[]
    | select(.browser_download_url != $url)
    | select(.name | test("(sha256|sha256sum|checksums?)"; "i"))
    | select(.name | test($triplet; "i") or test($arch; "i"))
    | .browser_download_url
' "$release_json" | head -n 1)

if [ -n "$checksum_url" ] && [ "$checksum_url" != "null" ]; then
    echo "downloading checksum asset: $checksum_url"
    # shellcheck disable=SC2086
    curl $curl_args -L "$checksum_url" -o "$DEST/checksums.txt"
    archive_name=$(basename "$asset_url")
    if grep -q "$archive_name" "$DEST/checksums.txt"; then
        (cd "$DEST" && sha256sum -c --ignore-missing checksums.txt)
    else
        expected=$(awk '{print $1; exit}' "$DEST/checksums.txt")
        actual=$(sha256sum "$archive" | awk '{print $1}')
        [ "$expected" = "$actual" ] || {
            echo "toolchain checksum mismatch" >&2
            echo "expected: $expected" >&2
            echo "actual:   $actual" >&2
            exit 1
        }
    fi
else
    echo "warning: no checksum asset found for $TRIPLET; release tag is pinned but asset hash is not" >&2
fi

mkdir -p "$DEST/extract"
case "$asset_url" in
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$DEST/extract" ;;
    *.tar.xz|*.txz) tar -xJf "$archive" -C "$DEST/extract" ;;
    *.tar.zst) tar --use-compress-program=zstd -xf "$archive" -C "$DEST/extract" ;;
    *.zip) unzip -q "$archive" -d "$DEST/extract" ;;
    *) echo "unsupported toolchain archive format: $asset_url" >&2; exit 1 ;;
esac

gcc_path=$(find "$DEST/extract" -type f -name "$TRIPLET-gcc" -perm /111 | head -n 1)
if [ -z "$gcc_path" ]; then
    echo "could not find $TRIPLET-gcc in extracted compiler asset" >&2
    find "$DEST/extract" -maxdepth 4 -type f | sort >&2
    exit 1
fi

bin_dir=$(dirname "$gcc_path")

"$gcc_path" -dumpmachine | grep -qx "$TRIPLET" || {
    echo "unexpected compiler dumpmachine:" >&2
    "$gcc_path" -dumpmachine >&2
    exit 1
}

printf '%s\n' "$bin_dir" >> "$GITHUB_PATH"
printf 'MUSL_CROSS=%s\n' "$bin_dir" >> "$GITHUB_ENV"
printf 'MUSL_TRIPLET=%s\n' "$TRIPLET" >> "$GITHUB_ENV"

echo "installed musl toolchain: $bin_dir"
"$gcc_path" --version | head -n 1
