#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ARCH=
TRIPLET=
BINARIES=

usage() {
    cat <<USAGE
usage: $0 --arch <arm64|x86_64> --triplet <triplet> --binary <path> [--binary <path> ...]
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --triplet) TRIPLET="$2"; shift 2 ;;
        --binary) BINARIES="$BINARIES $2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$ARCH" ] || { echo "--arch is required" >&2; exit 2; }
[ -n "$TRIPLET" ] || { echo "--triplet is required" >&2; exit 2; }
[ -n "$BINARIES" ] || { echo "at least one --binary is required" >&2; exit 2; }

command -v readelf >/dev/null 2>&1 || { echo "readelf is required" >&2; exit 1; }
command -v strings >/dev/null 2>&1 || { echo "strings is required" >&2; exit 1; }
command -v "$TRIPLET-gcc" >/dev/null 2>&1 || { echo "$TRIPLET-gcc not found in PATH" >&2; exit 1; }

"$TRIPLET-gcc" -dumpmachine | grep -qx "$TRIPLET" || {
    echo "compiler does not report expected triplet $TRIPLET" >&2
    "$TRIPLET-gcc" -dumpmachine >&2
    exit 1
}

case "$ARCH" in
    arm64) expected_machine='AArch64' ;;
    x86_64) expected_machine='Advanced Micro Devices X86-64' ;;
    *) echo "unsupported arch: $ARCH" >&2; exit 2 ;;
esac

for bin in $BINARIES; do
    echo "== verifying $bin =="
    test -x "$bin" || { echo "not executable: $bin" >&2; exit 1; }
    file "$bin"

    readelf -h "$bin" | grep -q "Machine:[[:space:]]*$expected_machine" || {
        echo "unexpected ELF machine for $bin" >&2
        readelf -h "$bin" >&2
        exit 1
    }

    if readelf -l "$bin" | grep -q 'INTERP'; then
        echo "error: $bin has PT_INTERP and is dynamically linked" >&2
        exit 1
    fi

    if readelf -d "$bin" >/tmp/dsvz-readelf-dynamic.$$ 2>/dev/null; then
        if grep -q 'NEEDED' /tmp/dsvz-readelf-dynamic.$$; then
            echo "error: $bin has DT_NEEDED dynamic dependencies" >&2
            cat /tmp/dsvz-readelf-dynamic.$$ >&2
            rm -f /tmp/dsvz-readelf-dynamic.$$
            exit 1
        fi
    fi
    rm -f /tmp/dsvz-readelf-dynamic.$$

    if strings "$bin" | grep -q 'GLIBC_'; then
        echo "error: $bin contains GLIBC symbol-version references" >&2
        exit 1
    fi

done

printf 'static libc verification passed for triplet=%s arch=%s\n' "$TRIPLET" "$ARCH"
