// @terminus/protocol — worker ↔ UI message types (SPEC §5.1).
// P0 worker already implements this shape ad hoc; P1 moves it here so the
// runtime worker + UI share one contract.

export type WorkerToUI =
  | { type: "status"; phase: "initializing" | "booting" | "ready" | "destroyed" }
  | { type: "download"; file: string; loaded: number; total: number }
  | { type: "output"; data: string }
  | { type: "ready"; boot_ms: number }
  | { type: "error"; message: string };

export type UIToWorker =
  | { type: "boot" }
  | { type: "input"; data: string }
  | { type: "destroy" };