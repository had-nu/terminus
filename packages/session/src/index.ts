// @terminus/session — placeholder (P1).
// Session lifecycle (SPEC §4): create → run → destroy; all state in the
// Web Worker's memory; nothing persists (D-005 ephemeral).
export interface SessionHandle {
  id: string;
  createdAt: number;
}