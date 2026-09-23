"use strict";
// TERMINUS P0 spike worker (SPEC §5: Web Worker owns the Linux runtime).
// Loads v86 (x86 -> WASM JIT), boots Alpine kernel + session initramfs,
// bridges serial console I/O to the main thread via postMessage.

importScripts("/runtime/wasm/libv86.js");

let emulator = null;
let boot_started_at = 0;

function post(msg) { self.postMessage(msg); }

self.onmessage = async event => {
  const msg = event.data;
  if (!msg || typeof msg !== "object") return;

  if (msg.type === "boot") {
    if (emulator) return;
    boot_started_at = performance.now();
    post({ type: "status", phase: "initializing" });

    emulator = new V86({
      wasm_path: "/runtime/wasm/v86.wasm",
      bios: { url: "/runtime/alpine/bios/seabios.bin" },
      vga_bios: { url: "/runtime/alpine/bios/vgabios.bin" },
      // 32-bit Alpine kernel: v86 does not emulate x86_64 (see docs/spike-p0.md)
      bzimage: { url: "/runtime/alpine/out/vmlinuz-lts" },
      initrd: { url: "/runtime/alpine/out/initramfs-p0.cpio.gz" },
      cmdline: "console=ttyS0",
      memory_size: 256 * 1024 * 1024,
      fastboot: true,
      autostart: true,
      disable_keyboard: true,
      disable_mouse: true,
      disable_speaker: true,
    });

    emulator.add_listener("download-progress", e => {
      post({
        type: "download",
        file: e.file_name,
        loaded: e.loaded,
        total: e.total,
      });
    });

    emulator.add_listener("emulator-started", () => {
      post({ type: "status", phase: "booting" });
    });

    // Serial output -> main thread. Buffered to avoid one message per byte.
    let buf = [];
    let flush_scheduled = false;
    let saw_banner = false;

    const flush = () => {
      flush_scheduled = false;
      if (!buf.length) return;
      post({ type: "output", data: new TextDecoder().decode(Uint8Array.from(buf)) });
      buf = [];
    };

    emulator.add_listener("serial0-output-byte", byte => {
      buf.push(byte);
      if (buf.length >= 4096 || !flush_scheduled) {
        flush_scheduled = true;
        setTimeout(flush, 16);
      }
      if (!saw_banner && byte === 0x0a) {
        const text = new TextDecoder().decode(Uint8Array.from(buf));
        if (text.includes("browser -> runtime -> Alpine -> /bin/sh")) {
          saw_banner = true;
          post({
            type: "ready",
            boot_ms: Math.round(performance.now() - boot_started_at),
          });
        }
      }
    });

    emulator.add_listener("download-error", e => {
      post({ type: "error", message: "failed to load " + e.file_name });
    });

  } else if (msg.type === "input") {
    if (emulator) emulator.serial0_send(msg.data);

  } else if (msg.type === "destroy") {
    if (emulator) {
      const e = emulator;
      emulator = null;
      await e.destroy().catch(() => {});
      post({ type: "status", phase: "destroyed" });
    }
  }
};
