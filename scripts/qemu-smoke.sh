#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ARCH=
KERNEL=
INITRAMFS=
APPEND_EXTRA=
LOG=
TIMEOUT=30
SENTINEL=DSVZ_RAMFS_SMOKE_OK

usage() {
    cat <<USAGE
usage: $0 --arch <arm64|x86_64> --kernel <path> --initramfs <path> [--log <path>] [--timeout <seconds>] [--append-extra <args>]
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --kernel) KERNEL="$2"; shift 2 ;;
        --initramfs) INITRAMFS="$2"; shift 2 ;;
        --append-extra) APPEND_EXTRA="$2"; shift 2 ;;
        --log) LOG="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -f "$KERNEL" ] || { echo "kernel not found: $KERNEL" >&2; exit 1; }
[ -f "$INITRAMFS" ] || { echo "initramfs not found: $INITRAMFS" >&2; exit 1; }
if [ -z "$LOG" ]; then
    LOG="qemu-$ARCH-smoke.log"
fi
mkdir -p "$(dirname -- "$LOG")"
rm -f "$LOG"

case "$ARCH" in
    arm64)
        CONSOLE=ttyAMA0
        QEMU=qemu-system-aarch64
        set -- \
            -M virt \
            -cpu cortex-a57 \
            -m 512M \
            -nographic \
            -no-reboot \
            -kernel "$KERNEL" \
            -initrd "$INITRAMFS"
        ;;
    x86_64)
        CONSOLE=ttyS0
        QEMU=qemu-system-x86_64
        set -- \
            -m 512M \
            -nographic \
            -no-reboot \
            -kernel "$KERNEL" \
            -initrd "$INITRAMFS"
        ;;
    *)
        echo "unsupported ARCH: $ARCH" >&2
        exit 2
        ;;
esac

command -v "$QEMU" >/dev/null 2>&1 || { echo "$QEMU not found" >&2; exit 1; }

APPEND="console=$CONSOLE init=/init panic=-1 droidspaces.mode=smoke $APPEND_EXTRA"

echo "QEMU: $QEMU"
echo "append: $APPEND"
echo "log: $LOG"

RC=0
timeout "$TIMEOUT" "$QEMU" "$@" -append "$APPEND" >"$LOG" 2>&1 || RC=$?

if grep -q "$SENTINEL" "$LOG"; then
    echo "QEMU smoke passed: found $SENTINEL"
    exit 0
fi

echo "QEMU smoke failed: sentinel not found ($SENTINEL)" >&2
echo "QEMU exit code: $RC" >&2
echo "--- QEMU log ---" >&2
cat "$LOG" >&2
exit 1
