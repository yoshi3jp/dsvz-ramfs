# droidspaces-initramfs-vz

Build a tiny Droidspaces appliance initramfs for Linux kernels booted under Apple Virtualization.framework.

This repository is Project 2 of the Droidspaces macOS VM stack:

1. `vz-kernel` provides the Linux kernel.
2. `droidspaces-initramfs-vz` provides the initramfs userspace.
3. The macOS app packages and boots both with Virtualization.framework.

The initramfs is intentionally not a Debian, Alpine, or generic distribution rootfs. It is the VM userspace: BusyBox, Droidspaces, and a small set of boot/import/runtime scripts.

## Outputs

The canonical app-facing output path is:

```text
dist/<arch>/initramfs.cpio.gz
```

Supported architecture names:

```text
arm64
x86_64
```

## Inputs

Set these paths when building:

```sh
BUSYBOX=/path/to/busybox \
DROIDSPACES=/path/to/droidspaces \
ARCH=arm64 \
make
```

Optional:

```sh
ZSTD=/path/to/zstd make
```

`zstd` is optional but recommended if official rootfs tarballs use `.tar.zst`.

## Boot contract

Expected kernel command line:

```text
console=hvc0 init=/init droidspaces.share_tag=dsdata droidspaces.config=/mnt/host/Config/desired-state.conf
```

The macOS app should attach a `VZSingleDirectoryShare` through `VZVirtioFileSystemDeviceConfiguration` using tag `dsdata` by default. The guest mounts it at `/mnt/host`.

## Host share layout

```text
/mnt/host/
  RootfsTarballs/
  Images/
  Containers/
  Config/
  Cache/
  Logs/
```

## First milestone

The first milestone is a bootable initramfs that:

1. mounts proc/sys/dev/devpts,
2. mounts the host VirtIO-FS share,
3. creates the expected host directories,
4. starts a Droidspaces-oriented boot path, or falls back to an emergency shell with useful diagnostics.

## Build

```sh
make ARCH=arm64 BUSYBOX=/abs/path/busybox-aarch64 DROIDSPACES=/abs/path/droidspaces-aarch64
make ARCH=x86_64 BUSYBOX=/abs/path/busybox-x86_64 DROIDSPACES=/abs/path/droidspaces-x86_64
```

Artifacts:

```text
dist/arm64/initramfs.cpio.gz
dist/arm64/manifest.txt
dist/x86_64/initramfs.cpio.gz
dist/x86_64/manifest.txt
```

## QEMU smoke test

This is not a substitute for Apple Virtualization.framework testing, but it catches early initramfs mistakes:

```sh
KERNEL=/path/to/kernel ARCH=arm64 make smoke
KERNEL=/path/to/kernel ARCH=x86_64 make smoke
```

For the first smoke test, use:

```text
droidspaces.mode=shell
```

or pass `QEMU_APPEND_EXTRA=droidspaces.mode=shell`.
