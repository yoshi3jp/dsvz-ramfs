#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ARCH=
INITRAMFS=
WORKDIR=

usage() {
    cat <<USAGE
usage: $0 --arch <arm64|x86_64> --initramfs <path> [--workdir <path>]
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --initramfs) INITRAMFS="$2"; shift 2 ;;
        --workdir) WORKDIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$ARCH" in
    arm64|x86_64) ;;
    *) echo "unsupported ARCH: $ARCH" >&2; exit 2 ;;
esac

[ -f "$INITRAMFS" ] || { echo "initramfs not found: $INITRAMFS" >&2; exit 1; }

if [ -z "$WORKDIR" ]; then
    WORKDIR=$(mktemp -d)
    CLEAN_WORKDIR=1
else
    mkdir -p "$WORKDIR"
    CLEAN_WORKDIR=0
fi
trap 'if [ "${CLEAN_WORKDIR:-0}" = 1 ]; then rm -rf "$WORKDIR"; fi' EXIT INT TERM

ROOT="$WORKDIR/root"
rm -rf "$ROOT"
mkdir -p "$ROOT"

(
    cd "$ROOT"
    gzip -dc "$INITRAMFS" | cpio -idmu --no-absolute-filenames >/dev/null
)

test -x "$ROOT/init" || { echo "missing executable /init" >&2; exit 1; }
test -x "$ROOT/bin/busybox" || { echo "missing executable /bin/busybox" >&2; exit 1; }
test -x "$ROOT/sbin/droidspaces" || { echo "missing executable /sbin/droidspaces" >&2; exit 1; }
test -x "$ROOT/usr/lib/droidspaces-initramfs/prepare-host-share.sh" || { echo "missing prepare-host-share.sh" >&2; exit 1; }
test -x "$ROOT/usr/lib/droidspaces-initramfs/import-images.sh" || { echo "missing import-images.sh" >&2; exit 1; }

HOST_ARCH=$(uname -m)
case "$HOST_ARCH" in
    x86_64|amd64) HOST_DSVZ_ARCH=x86_64 ;;
    aarch64|arm64) HOST_DSVZ_ARCH=arm64 ;;
    *) HOST_DSVZ_ARCH=unknown ;;
esac

if [ "$HOST_DSVZ_ARCH" != "$ARCH" ]; then
    echo "target $ARCH is not native on runner $HOST_ARCH; chroot execution skipped"
    echo "DSVZ_RAMFS_CHROOT_SKIPPED"
    exit 0
fi

chroot "$ROOT" /bin/busybox sh -c '
set -eu
/bin/busybox --install -s /bin
/bin/busybox --install -s /sbin
/bin/sh -n /init
test -x /init
test -x /sbin/droidspaces
test -x /usr/lib/droidspaces-initramfs/prepare-host-share.sh
test -x /usr/lib/droidspaces-initramfs/import-images.sh
for applet in sh ash mount umount tar gzip gunzip xz xzcat unxz losetup truncate mke2fs mkfs.ext2 ip udhcpc mdev mknod true; do
    /bin/busybox --list | grep -x "$applet" >/dev/null || { echo "missing applet: $applet"; exit 1; }
done
/sbin/droidspaces --help >/dev/null 2>&1 || true
echo DSVZ_RAMFS_CHROOT_OK
'
