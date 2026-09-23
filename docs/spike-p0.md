# Spike P0 — Runtime Feasibility

**Status:** completed — **v86 selected** (D-006)
**Date:** 2026-09-23
**Branch:** `feat/p0-runtime-spike`
**Relates to:** [SPEC.md](../SPEC.md) D-001, D-005, D-006, OQ-001, OQ-003, milestone P0

## Objective

Prove SPEC P0: `browser → runtime → Alpine → /bin/sh`, and produce the
comparative evidence (D-001) to select the WASM runtime: **v86** vs
**container2wasm (c2w)**.

## Method

Both candidates are exercised the same way: a headless Chromium (Playwright)
opens the spike page, the runtime boots an Alpine Linux userspace, the page
waits for a shell prompt, sends a command over the (virtual) serial console,
and the echoed output is captured as evidence.

## Arm A — v86 (in a Web Worker)

### Provenance (SPEC §10.5 pins)

| Artifact | Version | sha256 |
|---|---|---|
| `vmlinuz-lts` (Alpine x86) | 3.22.6 (6.12.110-0-lts) | `67656fdd…d54de` |
| `alpine-minirootfs-3.22.6-x86.tar.gz` | 3.22.6 x86 | `664ff599…c18ae8` |
| `seabios.bin` / `vgabios.bin` | copy/v86 master | `73e3f359…444d98` / `a4bc0d80…7607880` |
| `libv86.js` + `v86.wasm` | v86 `0.5.462` (npm) | pinned via `scripts/build-runtime.sh` |

All artifacts fetched and sha256-verified reproducibly by
`scripts/build-rootfs.sh` (Alpine kernel/rootfs/initramfs) and
`scripts/build-runtime.sh` (v86 + BIOS).

### Architecture used (matches SPEC §5)

```
apps/web/index.html  (UI only, no runtime knowledge)
   └─ Web Worker p0-worker.js
        ├─ libv86.js  (x86 → WASM JIT, v86)
        ├─ vmlinuz-lts + initramfs-p0.cpio.gz  (Alpine x86)
        └─ serial0 I/O bridge ↔ postMessage
```

- Runtime runs **inside a Web Worker** (SPEC §5 requires the runtime to live in
  a worker; main thread stays free for UI).
- Serial console (`console=ttyS0`) is the stdin/stdout channel — the same
  design P1 will bridge into xterm.js.
- No VGA emulation used; headless.

### Key decision re-verified: 32-bit Alpine x86

v86 emulates a 32-bit x86 (Pentium 4-class, no x86_64). Alpine still ships the
32-bit `x86` port; we pin `v3.22.6` `x86` releases (not `x86_64`). This is the
single most important constraint driving the whole runtime choice.

### Evidence (headless Chromium, `docs/../apps/web`, boot 1)

```
[environment ready in 30698 ms]
TERMINUS P0 - Alpine Linux 3.22.6 (x86)
browser -> runtime -> Alpine -> /bin/sh
/bin/sh: can't access tty; job control turned off
terminus:~# echo TERMINUS_P0_OK; cat /etc/alpine-release; uname -m
TERMINUS_P0_OK
3.22.6
i686
terminus:~# [session destroyed — all processes and files discarded]
```

- Shell prompt `terminus:~#` reached after full kernel boot.
- Command round-trip works (stdin via serial0, stdout back to page).
- `uname -m = i686` confirms the Alpine x86 (32-bit) port.
- Session destroy tears down and discards all state; page reports
  "session destroyed — all processes and files discarded" (SPEC §13 framing).
- Zero page errors, zero console errors during the run.

### Measurements

| Metric | Value |
|---|---|
| Time page-load → shell prompt | **≈ 31 s** (first cold run; warm ~25 s) |
| Payload served (kernel + initramfs + wasm + bios) | **13.7 MiB** (8.2 kernel + 3.5 initramfs + 2.1 v86.wasm + 0.36 libv86.js + 0.16 bios) — under §6.1 25 MB budget |
| Guest memory | 256 MB (v86 `memory_size`) |
| Host memory headroom | ~1.4 GB free during run |
| Web worker usage | yes (runtime lives in worker) |
| 64-bit guests | unsupported (constraint) |

Raw evidence: `docs/evidence/p0-v86-evidence.json` (boot_ms 30698, echo
round-trip `TERMINUS_P0_OK`, `3.22.6`, `i686`, destroy, zero errors) and
`docs/evidence/p0-v86-terminal.png` (screenshot).

## Arm B — container2wasm (c2w)

**Result: does NOT complete within the P0 timebox. Rejected for D-001 (see
table below).**

- `c2w` v0.8.4 downloaded and sha256-verified
  (`1142ab95…00f31`).
- Attempted: `c2w --to-js --dockerfile <patched> alpine:3.22 <dir>/`
  (amd64 → Bochs emulation) with the upstream `examples/wasi-browser` harness
  (browser_wasi_shim + xterm-pty) pinned from the `container2wasm` repo at
  tag `v0.8.4`.
- **Outcome:** conversion build aborted at the 30-minute timeout with **no
  wasm artifact produced** (last progress: qemu-system-x86_64 at 1503/1522
  objects compiled; glib from source still building). The pipeline compiles a
  full Linux kernel, busybox, qemu **and** Bochs from source on every
  conversion.

### Upstream defects found while exercising c2w (evidence for D-001)

These are reproducible defects in the v0.8.4 *release pipeline toolchain*, not
environment problems:

1. **Broken embedded Dockerfile.** The `--show-dockerfile` output pins
   `SOURCE_REPO=https://github.com/ktock/container2wasm` with
   `SOURCE_REPO_VERSION=v0.8.4`, but the project moved to
   `container2wasm/container2wasm` and the `ktock` repo no longer carries
   that tag. `git clone -b v0.8.4 …/ktock/container2wasm` fails →
   `assets-base` build step aborts. Workaround used here: dump
   `--show-dockerfile`, fix the two `ARG`s, pass `--dockerfile`.
2. **CLI ignores flags after positional args** (`urfave/cli`). Passing
   `c2w alpine:3.22 out --to-js --dockerfile …` silently drops **all**
   trailing flags (no `--target=js`, embedded Dockerfile used instead).
   Flags MUST precede the image-name positional.
3. **`--to-js` requires a slash-terminated directory** as the output
   argument (error: "output destination must be a slash-terminated
   directory path when using to-js option").

### Build cost (measured on this host)

Converting `alpine:3.22` with `--to-js` (Docker buildx):
separate stage builds **a Linux kernel from source, busybox, qemu, Bochs,
grub, glibc-based toolchains** (~10+ focused image layers, tens of GB of
layer cache). The image conversion alone took **> 10 minutes** of compiler
time on this host, plus a ~200 MB multi-stage pull. CI cost (SPEC §9.4) and
reproducibility (SPEC §10.5) implications are material.

These are candidate-killing friction points for CI (SPEC §9.4) and for
reproducible artifact builds (SPEC §10.5): the current release cannot
convert `alpine:3.22` out of the box.

## Decision inputs (final — D-001 → D-006)

| Criterion | v86 | c2w (v0.8.4) |
|---|---|---|
| Runs in Web Worker | **yes — proven** (classic worker) | via browser_wasi_shim worker |
| Alpine in browser (proven locally) | **yes** (boot ≈31 s, echo round-trip, destroy) | **no — no artifact produced** |
| x86_64 support | no (32-bit only — decisive port choice) | yes (Bochs x86_64) |
| Payload (cold cache, measured) | **13.7 MiB** | unknown (build never finished) |
| Initramfs/kernel control | full (pin kernel + custom `/init`) | whole-image convert |
| Build for reproducible CI (§9.4, §10.5) | fetch + verify ≈ seconds | > 30 min compiler pipeline, 3 upstream defects fixed locally |
| Ecosystem maturity | v86 (10+ years, permissive) | experimental (self-described) |
| License | BSD-2-Clause | Apache-2.0 |

## How to reproduce

```bash
bash scripts/build-rootfs.sh   # fetch + sha256-verify + assemble initramfs
bash scripts/build-runtime.sh  # vendor v86 runtime + BIOS (npm pack, pinned)
bash scripts/dev.sh 8000       # static host
# open http://127.0.0.1:8000/apps/web/index.html
# headless evidence: /tmp/opencode/p0test/collect-evidence.js (Playwright)
```

## Outcome

**D-006: runtime = v86.** P0 success criterion `browser → runtime → Alpine →
`/bin/sh` in a Web Worker **was met and evidenced** with v86 (zero errors,
boot ≈31 s, payload 13.7 MiB). The c2w arm could not produce a runnable
artifact within the timebox: its v0.8.4 release pipeline has three reproducible
upstream defects and the conversion build exceeds 30 minutes. See [SPEC.md](../SPEC.md)
§12 (D-006) and `docs/benchmarks.md`.