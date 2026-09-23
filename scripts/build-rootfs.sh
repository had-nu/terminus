#!/usr/bin/env bash
# Build the TERMINUS session rootfs (SPEC §9 filesystem model seed).
#
# Steps:
#   1. Fetch + sha256-verify pinned Alpine x86 artifacts (SPEC §10.5, D-001 OQ-003:
#      v86 emulates 32-bit x86 only, so use the Alpine `x86` port).
#   2. Assemble an initramfs: Alpine minirootfs 3.22.6 + TERMINUS /init
#      that drops to /bin/sh on the serial console (console=ttyS0).
#
# Outputs (gitignored):
#   runtime/alpine/out/vmlinuz-lts
#   runtime/alpine/out/alpine-minirootfs-3.22.6-x86.tar.gz
#   runtime/alpine/out/initramfs-p0.cpio.gz
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/runtime/alpine/out"
BIOS="$ROOT/runtime/alpine/bios"
mkdir -p "$OUT" "$BIOS"

# --- Pins -------------------------------------------------------------------
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86"
ALPINE_VERSION="3.22.6"

PIN_VMLINUZ="67656fdddd9a55719a92ae190003b761263953b221a9a6f5e770ca9dc04d54de"
PIN_MINIROOTFS="664ff599815a9dd0a181495776ef388e73eccbc1d5b4a165b485347879c18ae8"
PIN_SEABIOS="73e3f359102e3a9982c35fce98eb7cd08f18303ac7f1ba6ebfbe6cdc1c244d98"
PIN_VGABIOS="a4bc0d80cc3ca028c73dafa8fee396b8d054ce87ebd8abfbd31b06b437607880"

verify() { echo "$1  $2" | sha256sum -c -; }
fetch() { [ -f "$2" ] || curl -fsSL --max-time 120 "$1" -o "$2"; }

fetch "$ALPINE_MIRROR/netboot/vmlinuz-lts" "$OUT/vmlinuz-lts"
verify "$PIN_VMLINUZ" "$OUT/vmlinuz-lts"

fetch "$ALPINE_MIRROR/alpine-minirootfs-$ALPINE_VERSION-x86.tar.gz" \
      "$OUT/alpine-minirootfs-$ALPINE_VERSION-x86.tar.gz"
verify "$PIN_MINIROOTFS" "$OUT/alpine-minirootfs-$ALPINE_VERSION-x86.tar.gz"

# --- Assemble initramfs -----------------------------------------------------
STAGE="$ROOT/runtime/alpine/rootfs"
rm -rf "$STAGE"
mkdir -p "$STAGE"
tar -xzf "$OUT/alpine-minirootfs-$ALPINE_VERSION-x86.tar.gz" -C "$STAGE"

# Minimal init: mount virtual filesystems, drop to a login shell on console.
# console=ttyS0 (kernel cmdline) makes this the serial console. The kernel
# already wired console fds to PID 1, so no settings/cttyhack is required.
cat > "$STAGE/init" <<'EOF'
#!/bin/sh
# TERMINUS P0 init - drop to /bin/sh on serial console
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
mount -t devtmpfs devtmpfs /dev 2>/dev/null || mount -t tmpfs tmpfs /dev
mkdir -p /dev/pts /dev/shm /tmp /run
mount -t devpts devpts /dev/pts 2>/dev/null
mount -t tmpfs tmpfs /dev/shm 2>/dev/null
mount -t tmpfs tmpfs /tmp 2>/dev/null
mount -t tmpfs tmpfs /run 2>/dev/null
hostname terminus
echo ""
echo "TERMINUS P0 - Alpine Linux $(cat /etc/alpine-release 2>/dev/null || echo '?') (x86)"
echo "browser -> runtime -> Alpine -> /bin/sh"
exec /bin/sh -l
EOF
chmod +x "$STAGE/init"

( cd "$STAGE" && find . | cpio -o -H newc --quiet | gzip -9 ) > "$OUT/initramfs-p0.cpio.gz"

echo "✓ rootfs + initramfs built (tiny shell at $(du -h "$OUT/initramfs-p0.cpio.gz" | cut -f1))"
echo "  $OUT/initramfs-p0.cpio.gz"