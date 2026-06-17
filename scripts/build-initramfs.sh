#!/bin/sh
set -eu

ARCH=
BUSYBOX=
DROIDSPACES=
ZSTD=

usage() {
    cat <<USAGE
usage: $0 --arch <arm64|x86_64> --busybox <path> --droidspaces <path> [--zstd <path>]
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --busybox) BUSYBOX="$2"; shift 2 ;;
        --droidspaces) DROIDSPACES="$2"; shift 2 ;;
        --zstd) ZSTD="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$ARCH" in
    arm64|x86_64) ;;
    *) echo "unsupported ARCH: $ARCH" >&2; exit 2 ;;
esac

[ -x "$BUSYBOX" ] || { echo "busybox not executable: $BUSYBOX" >&2; exit 1; }
[ -x "$DROIDSPACES" ] || { echo "droidspaces not executable: $DROIDSPACES" >&2; exit 1; }
if [ -n "$ZSTD" ]; then
    [ -x "$ZSTD" ] || { echo "zstd not executable: $ZSTD" >&2; exit 1; }
fi

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/out/$ARCH"
STAGE="$OUT/stage"
DIST="$ROOT/dist/$ARCH"

rm -rf "$STAGE" "$DIST"
mkdir -p "$STAGE" "$DIST"

mkdir -p \
    "$STAGE/bin" \
    "$STAGE/sbin" \
    "$STAGE/etc/droidspaces" \
    "$STAGE/usr/lib/droidspaces-initramfs" \
    "$STAGE/proc" \
    "$STAGE/sys" \
    "$STAGE/dev/pts" \
    "$STAGE/run" \
    "$STAGE/tmp" \
    "$STAGE/mnt/host" \
    "$STAGE/mnt/containers" \
    "$STAGE/var/log" \
    "$STAGE/www"

cp "$BUSYBOX" "$STAGE/bin/busybox"
chmod 0755 "$STAGE/bin/busybox"

cp "$DROIDSPACES" "$STAGE/sbin/droidspaces"
chmod 0755 "$STAGE/sbin/droidspaces"
ln -s droidspaces "$STAGE/sbin/droidspacesd"

if [ -n "$ZSTD" ]; then
    cp "$ZSTD" "$STAGE/bin/zstd"
    chmod 0755 "$STAGE/bin/zstd"
fi

cp "$ROOT/initramfs/init" "$STAGE/init"
chmod 0755 "$STAGE/init"
cp "$ROOT/initramfs/usr/lib/droidspaces-initramfs/"*.sh "$STAGE/usr/lib/droidspaces-initramfs/"
chmod 0755 "$STAGE/usr/lib/droidspaces-initramfs/"*.sh
cp "$ROOT/initramfs/etc/droidspaces/defaults.conf" "$STAGE/etc/droidspaces/defaults.conf"

cat > "$STAGE/etc/passwd" <<'PASSWD'
root:x:0:0:root:/root:/bin/sh
nobody:x:65534:65534:nobody:/nonexistent:/bin/false
PASSWD

cat > "$STAGE/etc/group" <<'GROUP'
root:x:0:
tty:x:5:
nobody:x:65534:
GROUP

mkdir -p "$STAGE/root"
chmod 0700 "$STAGE/root"
chmod 1777 "$STAGE/tmp"

(
    cd "$STAGE"
    find . -print0 | cpio --null -ov --format=newc
) | gzip -9 > "$DIST/initramfs.cpio.gz"

(
    cd "$DIST"
    sha256sum initramfs.cpio.gz > manifest.txt
    printf 'arch=%s\n' "$ARCH" >> manifest.txt
    printf 'busybox_source=%s\n' "$BUSYBOX" >> manifest.txt
    printf 'droidspaces_source=%s\n' "$DROIDSPACES" >> manifest.txt
    if [ -n "$ZSTD" ]; then printf 'zstd_source=%s\n' "$ZSTD" >> manifest.txt; fi
)

printf 'created %s\n' "$DIST/initramfs.cpio.gz"
printf 'created %s\n' "$DIST/manifest.txt"
