#!/bin/sh
set -eu

HOST="${1:-/mnt/host}"

for dir in RootfsTarballs Images Containers Config Cache Logs; do
    mkdir -p "$HOST/$dir"
done

# Create a minimal desired-state file for first boot. The macOS app should replace this.
if [ ! -f "$HOST/Config/desired-state.conf" ]; then
    cat > "$HOST/Config/desired-state.conf" <<'CONF'
# Droidspaces VM desired state.
# The macOS app should generate this file from its plist.
# Example:
# container.debian13.rootfs_tarball=RootfsTarballs/debian13-aarch64.tar.zst
# container.debian13.image=Images/debian13-aarch64.img
# container.debian13.size=8G
# container.debian13.fs=ext4
# container.debian13.autostart=0
CONF
fi

exit 0
