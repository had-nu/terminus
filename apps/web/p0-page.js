"use strict";
// TERMINUS P0 spike page: thin presentation layer over the runtime worker
// (SPEC §5 main thread = UI only; §13 terminal is the product).

const term = document.getElementById("term");
const statusEl = document.getElementById("status");
const input = document.getElementById("input");
const bootBtn = document.getElementById("boot-btn");
const destroyBtn = document.getElementById("destroy-btn");
const sessionEl = document.getElementById("session-id");

let worker = null;
let session_id = null;

function setStatus(text, cls) {
  statusEl.textContent = text;
  statusEl.className = cls || "";
}

function append(data) {
  term.textContent += data.replace(/\r/g, "");
  term.scrollTop = term.scrollHeight;
}

function new_session_id() {
  return Math.random().toString(16).slice(2, 8);
}

function boot() {
  if (worker) return;
  session_id = new_session_id();
  sessionEl.textContent = "Session: " + session_id;
  setStatus("initializing environment…");
  bootBtn.disabled = true;

  worker = new Worker("./p0-worker.js");
  worker.onmessage = event => {
    const msg = event.data;
    switch (msg.type) {
      case "status":
        if (msg.phase === "booting") setStatus("starting runtime…");
        if (msg.phase === "destroyed") setStatus("session destroyed");
        break;
      case "download":
        setStatus(
          "downloading " + msg.file + " " +
          Math.round((msg.loaded / msg.total) * 100) + "%"
        );
        break;
      case "output":
        append(msg.data);
        break;
      case "ready":
        setStatus("environment ready — " + msg.boot_ms + " ms", "ready");
        destroyBtn.disabled = false;
        input.focus();
        append("\n[environment ready in " + msg.boot_ms + " ms]\n");
        break;
      case "error":
        setStatus(msg.message, "error");
        break;
    }
  };
  worker.onerror = e => {
    setStatus("worker error: " + e.message, "error");
  };
  worker.postMessage({ type: "boot" });
}

function destroy() {
  if (!worker) return;
  worker.postMessage({ type: "destroy" });
  setTimeout(() => {
    worker.terminate();
    worker = null;
    bootBtn.disabled = false;
    destroyBtn.disabled = true;
    setStatus("session destroyed");
    append("\n[session destroyed — all processes and files discarded]\n");
  }, 300);
}

input.addEventListener("keydown", e => {
  if (e.key !== "Enter") return;
  if (!worker) return;
  worker.postMessage({ type: "input", data: input.value + "\n" });
  input.value = "";
});

bootBtn.addEventListener("click", boot);
destroyBtn.addEventListener("click", destroy);

// SPEC §3.3: opening the page starts the session (OPEN TERMINAL).
boot();
