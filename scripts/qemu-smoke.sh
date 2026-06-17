#!/bin/sh
set -eu

ARCH=
KERNEL=
INITRAMFS=
APPEND_EXTRA=

usage() {
    cat <<USAGE
usage: $0 --arch <arm64|x86_64> --kernel <path> --initramfs <path> [--append-extra <args>]
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --kernel) KERNEL="$2"; shift 2 ;;
        --initramfs) INITRAMFS="$2"; shift 2 ;;
        --append-extra) APPEND_EXTRA="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -f "$KERNEL" ] || { echo "kernel not found: $KERNEL" >&2; exit 1; }
[ -f "$INITRAMFS" ] || { echo "initramfs not found: $INITRAMFS" >&2; exit 1; }

COMMON_APPEND="console=ttyS0 init=/init panic=-1 droidspaces.mode=shell $APPEND_EXTRA"

case "$ARCH" in
    arm64)
        exec qemu-system-aarch64 \
            -M virt \
            -cpu cortex-a57 \
            -m 512M \
            -nographic \
            -kernel "$KERNEL" \
            -initrd "$INITRAMFS" \
            -append "$COMMON_APPEND"
        ;;
    x86_64)
        exec qemu-system-x86_64 \
            -m 512M \
            -nographic \
            -kernel "$KERNEL" \
            -initrd "$INITRAMFS" \
            -append "$COMMON_APPEND"
        ;;
    *)
        echo "unsupported ARCH: $ARCH" >&2
        exit 2
        ;;
esac
