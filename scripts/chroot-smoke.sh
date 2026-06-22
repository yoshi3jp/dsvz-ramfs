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
test -x "$ROOT/usr/lib/droidspaces-initramfs/supervise-droidspaces.sh" || { echo "missing supervise-droidspaces.sh" >&2; exit 1; }
if grep -q '^[[:space:]]*exec[[:space:]]\+/sbin/droidspaces' "$ROOT/init"; then
    echo "/init must not exec Droidspaces as host PID 1" >&2
    exit 1
fi

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

mkdir -p "$ROOT/tmp"
cat > "$ROOT/tmp/chroot-smoke.sh" <<'EOF_CHROOT_SMOKE'
#!/bin/sh
set -eu

/bin/busybox --install -s /bin
/bin/busybox --install -s /sbin
/bin/sh -n /init
test -x /init
test -x /sbin/droidspaces
test -x /usr/lib/droidspaces-initramfs/prepare-host-share.sh
test -x /usr/lib/droidspaces-initramfs/import-images.sh
test -x /usr/lib/droidspaces-initramfs/supervise-droidspaces.sh
for applet in sh ash cat chmod grep mount mv umount tar gzip gunzip xz xzcat unxz losetup truncate mke2fs mkfs.ext2 ip udhcpc mdev mknod kill sleep true; do
    /bin/busybox --list | grep -x "$applet" >/dev/null || { echo "missing applet: $applet"; exit 1; }
done
/sbin/droidspaces --help >/dev/null 2>&1 || true

mv /sbin/droidspaces /sbin/droidspaces.real
cat > /sbin/droidspaces <<'EOF_DROIDSPACES_STUB'
#!/bin/sh
case "${1:-}" in
    --exit)
        exit "${2:-0}"
        ;;
    --wait-term)
        trap 'echo TERM > /tmp/droidspaces-term; exit 42' TERM
        echo ready > /tmp/droidspaces-ready
        while :; do
            sleep 1
        done
        ;;
    *)
        exit 0
        ;;
esac
EOF_DROIDSPACES_STUB
chmod 0755 /sbin/droidspaces

log() { :; }
. /usr/lib/droidspaces-initramfs/supervise-droidspaces.sh

droidspaces_start --exit 23
test -n "$DS_SUPERVISOR_PID"
set +e
droidspaces_wait
status=$?
set -e
test "$status" -eq 23
test -z "$DS_SUPERVISOR_PID"

cat > /tmp/dsinit-signal-test.sh <<'EOF_SIGNAL_TEST'
#!/bin/sh
set -eu

log() { :; }
. /usr/lib/droidspaces-initramfs/supervise-droidspaces.sh

handle_droidspaces_signal() {
    droidspaces_forward_signal "$1"
}

trap 'handle_droidspaces_signal TERM' TERM

droidspaces_start --wait-term
echo "$DS_SUPERVISOR_PID" > /tmp/supervisor-child-pid
set +e
droidspaces_wait
status=$?
set -e
echo "$status" > /tmp/supervisor-status
EOF_SIGNAL_TEST
chmod 0755 /tmp/dsinit-signal-test.sh
rm -f /tmp/droidspaces-ready /tmp/droidspaces-term /tmp/supervisor-child-pid /tmp/supervisor-status
/bin/sh /tmp/dsinit-signal-test.sh &
supervisor_pid=$!
for attempt in 1 2 3 4 5; do
    test -f /tmp/droidspaces-ready && break
    sleep 1
done
test -f /tmp/droidspaces-ready
kill -TERM "$supervisor_pid"
wait "$supervisor_pid"
test "$(cat /tmp/supervisor-status)" -eq 42
test "$(cat /tmp/droidspaces-term)" = TERM

echo DSVZ_RAMFS_CHROOT_OK
EOF_CHROOT_SMOKE
chmod 0755 "$ROOT/tmp/chroot-smoke.sh"
chroot "$ROOT" /bin/busybox sh /tmp/chroot-smoke.sh
