# Benchmarks

*Measured during the P0 spike (2026-09-23) on the spike host — see
[spike-p0.md](spike-p0.md) for method and evidence. SPEC §9.4 requires boot
benchmarks to be recorded here; regressions reviewed at each milestone.*

## v86 (chosen runtime, D-001)

| Metric | Result | Notes |
|---|---|---|
| Time page-load → interactive prompt (cold) | **≈ 31 s** (24669–31236 ms across runs) | Full software emulation of a 32-bit x86 guest; no VGA |
| Payload served, cold cache | **13.7 MiB** served | kernel 8.2 MiB + initramfs 3.5 MiB + v86.wasm 2.1 MiB + libv86.js 0.36 MiB + BIOS 0.16 MiB |
| Guest memory | 256 MB | v86 `memory_size` |
| Commands while booted | echo, cat, uname work | round-trip via serial console |

### vs SPEC §6.1 target

- Payload ≤ 25 MB: **passes** (13.7 MiB).
- Cold prompt ≤ 10 s: **not met** (≈31 s in software emulation). Honest note
  recorded in §6.2; mitigation is HTTP caching (repeat load uses warm cache).
- Guest RAM 256 MB default: **matches**.

## container2wasm (c2w, rejected in D-001)

Image conversion did **not complete within the spike window**; upstream release
pipeline blocked first attempts (3 reproducible defects — see spike-p0.md Arm
B). Partial measurement: conversion build compiled a Linux kernel, busybox,
qemu and Bochs from source (multi-stage Docker build, **> 10 min** of compiler
time, tens of GB of layer cache); the expected browser payload is the emulator
+ `/out.wasm` (~tens of MiB, unmeasured).

## How to re-measure (v86)

```bash
bash scripts/build-rootfs.sh && bash scripts/build-runtime.sh
bash scripts/dev.sh 5173           # then open /apps/web/index.html
# P0 harness: /tmp/opencode/p0test/collect-evidence.js (headless Chromium)
```