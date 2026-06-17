ARCH ?= $(shell uname -m)
DIST := dist/$(ARCH)
INITRAMFS := $(DIST)/initramfs.cpio.gz

.PHONY: all initramfs clean smoke check-inputs

all: initramfs

initramfs: check-inputs
	./scripts/build-initramfs.sh \
		--arch "$(ARCH)" \
		--busybox "$(BUSYBOX)" \
		--droidspaces "$(DROIDSPACES)" \
		$$(test -n "$(ZSTD)" && printf -- '--zstd %s' "$(ZSTD)" || true)

check-inputs:
	@test -n "$(BUSYBOX)" || { echo "BUSYBOX=/path/to/busybox is required"; exit 1; }
	@test -x "$(BUSYBOX)" || { echo "BUSYBOX is not executable: $(BUSYBOX)"; exit 1; }
	@test -n "$(DROIDSPACES)" || { echo "DROIDSPACES=/path/to/droidspaces is required"; exit 1; }
	@test -x "$(DROIDSPACES)" || { echo "DROIDSPACES is not executable: $(DROIDSPACES)"; exit 1; }
	@if test -n "$(ZSTD)"; then test -x "$(ZSTD)" || { echo "ZSTD is not executable: $(ZSTD)"; exit 1; }; fi

smoke: $(INITRAMFS)
	@test -n "$(KERNEL)" || { echo "KERNEL=/path/to/kernel is required"; exit 1; }
	./scripts/qemu-smoke.sh --arch "$(ARCH)" --kernel "$(KERNEL)" --initramfs "$(INITRAMFS)" $${QEMU_APPEND_EXTRA:+--append-extra "$$QEMU_APPEND_EXTRA"}

clean:
	rm -rf out dist
