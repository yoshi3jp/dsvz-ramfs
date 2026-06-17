#!/bin/sh
set -eu

HOST="${1:-/mnt/host}"
CONFIG="${2:-$HOST/Config/desired-state.conf}"

log() {
    echo "[dsimage] $*" >/dev/console
    echo "[dsimage] $*" >> "$HOST/Logs/boot.log" 2>/dev/null || true
}

# This is intentionally conservative for the first Project 2 milestone.
# It validates the storage primitives but does not yet try to understand every Droidspaces profile option.

[ -f "$CONFIG" ] || exit 0

# Minimal line-oriented format for early testing:
# image.<name>.tar=RootfsTarballs/foo.tar.xz
# image.<name>.path=Images/foo.img
# image.<name>.size=8G
# image.<name>.fs=ext4

names=$(sed -n 's/^image\.\([^.]\+\)\.tar=.*/\1/p' "$CONFIG" | sort -u)

for name in $names; do
    tar_rel=$(sed -n "s/^image\.$name\.tar=//p" "$CONFIG" | tail -n 1)
    img_rel=$(sed -n "s/^image\.$name\.path=//p" "$CONFIG" | tail -n 1)
    size=$(sed -n "s/^image\.$name\.size=//p" "$CONFIG" | tail -n 1)
    fs=$(sed -n "s/^image\.$name\.fs=//p" "$CONFIG" | tail -n 1)

    [ -n "$tar_rel" ] || { log "image $name has no tar path"; continue; }
    [ -n "$img_rel" ] || img_rel="Images/$name.img"
    [ -n "$size" ] || size="8G"
    [ -n "$fs" ] || fs="ext4"

    tar_path="$HOST/$tar_rel"
    img_path="$HOST/$img_rel"
    meta_path="$img_path.meta"

    if [ -f "$meta_path" ] && grep -q '^state=initialized$' "$meta_path" 2>/dev/null; then
        log "image $name already initialized"
        continue
    fi

    [ -f "$tar_path" ] || { log "missing tarball for $name: $tar_path"; continue; }

    log "creating sparse image $img_path size=$size fs=$fs"
    mkdir -p "$(dirname "$img_path")"
    truncate -s "$size" "$img_path"

    loopdev=$(losetup -f)
    losetup "$loopdev" "$img_path"

    cleanup_loop() {
        umount /mnt/containers/"$name" 2>/dev/null || true
        losetup -d "$loopdev" 2>/dev/null || true
    }
    trap cleanup_loop EXIT INT TERM

    case "$fs" in
        ext4)
            mkfs.ext4 -F "$loopdev" >/dev/console
            ;;
        ext2)
            mkfs.ext2 -F "$loopdev" >/dev/console
            ;;
        *)
            log "unsupported filesystem for $name: $fs"
            exit 1
            ;;
    esac

    mkdir -p /mnt/containers/"$name"
    mount "$loopdev" /mnt/containers/"$name"

    case "$tar_path" in
        *.tar.zst)
            if command -v zstd >/dev/null 2>&1; then
                zstd -dc "$tar_path" | tar -C /mnt/containers/"$name" -xpf -
            else
                log "zstd binary missing; cannot import $tar_path"
                exit 1
            fi
            ;;
        *.tar.xz|*.txz)
            xzcat "$tar_path" | tar -C /mnt/containers/"$name" -xpf -
            ;;
        *.tar.gz|*.tgz)
            gzip -dc "$tar_path" | tar -C /mnt/containers/"$name" -xpf -
            ;;
        *.tar)
            tar -C /mnt/containers/"$name" -xpf "$tar_path"
            ;;
        *)
            log "unsupported tarball extension: $tar_path"
            exit 1
            ;;
    esac

    sync
    umount /mnt/containers/"$name"
    losetup -d "$loopdev"
    trap - EXIT INT TERM

    {
        echo "name=$name"
        echo "source_tarball=$tar_rel"
        echo "image=$img_rel"
        echo "size=$size"
        echo "fs=$fs"
        echo "state=initialized"
    } > "$meta_path"

    log "initialized image $name"
done

exit 0
