# Architecture

*Status: P0 snapshot — see [spike-p0.md](spike-p0.md) for measured evidence.*

TERMINUS runs a disposable Alpine Linux userspace in the browser. The
architecture is deliberately small (SPEC §3):

```
┌─────────────────────────────── Main thread (UI) ──────────────────────────────┐
│  React / xterm.js (P1)  ↔  packages/protocol  ↔  Session controller (§4.3)   │
└─────────────────────────────────────────┬─────────────────────────────────────┘
                                          postMessage / MessageChannel
┌─────────────────────────────── Web Worker (runtime) ─────────────────────────┐
│  v86 (x86 → WASM JIT)  ↔  Alpine kernel + initramfs  ↔  serial console bridge │
│  All session state lives here; destroy = terminate, nothing persists (§8.4)   │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Layers

| Layer | Where | Responsibility |
|---|---|---|
| UI shell | main thread (`apps/web`) | Landing, session chrome, input/upload/download/destroy |
| Terminal | main thread (P1: xterm.js) | Output rendering, input capture, resize |
| Speech protocol | `packages/protocol` | Typed worker ↔ UI messages (§5.1) |
| Session | `packages/session` | Lifecycle NEW → DESTROYED; single owner of the worker |
| Runtime | Web Worker (`runtime/wasm`, v86) | CPU emulation, guest memory, BIOS |
| Userspace | `runtime/alpine` (initramfs) | `/init` → `/bin/sh` on `console=ttyS0`; base image (§4.2) |
| Filesystem | `runtime/filesystem` (P2) | Immutable base + writable overlay, CoW |

## Data flow (P0, measured)

1. Page load → worker `boot` → v86 fetches kernel/initramfs/wasm (13.7 MiB,
   sha256-pinned, cached by the browser) → boots Alpine x86 (32-bit).
2. `serial0-output-byte` events are buffered and forwarded as `output` messages;
   the banner line signals `ready` (boot_ms recorded, ~31 s cold in software
   emulation).
3. Keystrokes → `input` message → `serial0_send()` → guest stdin; stdout echoes
   back the same path (§3.3 step 2).
4. destroy → `emulator.destroy()` → worker terminated → session gone.

## Key decisions locked

- **v86** selected at D-001 (comparative spike; c2w blocked by upstream
  release-pipeline defects — see spike-p0.md Arm B).
- **Alpine `x86` (32-bit)** — v86 does not emulate x86_64 (OQ-003).
- **No backend** (D-005) — everything below is client-side.

## Out of scope at P0

React/xterm (P1), overlay FS (P2), `apk`/mirror (P3), file transfer (P4),
resource limits (P5), security review (P6). See SPEC §10.