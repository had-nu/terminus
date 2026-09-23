# TERMINUS — Ephemeral Linux — Technical Specification
<!-- Version: 0.2 | Status: Draft | Author: hadnu | Date: 2026-09-23 -->

> **RFC 2119 Convention:** The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHOULD", "SHOULD NOT", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Overview

### 1.1 Problem Statement

Researchers, students, developers, and cybersecurity practitioners regularly need a temporary Linux command-line environment for a single task: run a script, test a command, analyse a file, teach a concept. Every existing path imposes friction:

- **Local VMs and containers** require installation, image maintenance, host risk, and manual cleanup.
- **Cloud VMs and web terminals** require accounts and payment, persist data beyond the user's intent, and involve remote execution with opaque retention.
- **Browser demos** are either slow, uncontrolled full-OS emulators or Node-flavoured sandboxes that are not Linux.

No option today offers: *public URL → real Linux shell → destroy*, with no install, no account, and no residue. both the cleanup burden and the trust burden ("what happens to my files?") remain unsolved for small, one-off tasks.

### 1.2 Proposed Solution

TERMINUS is a browser-native, disposable Linux environment. It runs locally in the browser with **no mandatory backend**: it loads an immutable Alpine Linux base into an isolated Web Worker runtime, presents an interactive terminal, optionally transfers files in or out, and destroys all runtime state on demand.

Core promise:

> **Nothing to install. Nothing to maintain. Nothing to clean up.**

### 1.3 Scope

This spec defines the product principles, architecture, session/filesystem/security/privacy models, MVP acceptance criteria, prototype milestones P0–P7, and the deployment and testing strategy for an MVP delivered as a static web application with browser-local execution.

Out of scope for MVP (details in §2.2): user accounts, persistent storage, cloud workspaces, multi-user collaboration, persistent background jobs, Kubernetes, full cloud IDE functionality, guaranteed support for arbitrary Linux kernel features, unrestricted network access, production hosting workloads.

A future remote execution mode is sketched only (§3.5); no backend ships in MVP (D-005).

### 1.4 Product Principles

1. **Ephemeral by design.** A session is a disposable unit: no persistent home directory, no persistent package installation, no shell history, no account for the core experience. Destroying a session destroys its runtime state.
2. **Zero-install experience.** From public URL to Linux shell without installing software, creating an account, or configuring a VM, Docker, or SSH.
3. **Clean-state reproducibility.** Every new session starts from the same immutable base image. Experiments are reproducible by documenting the Alpine version, runtime version, installed packages, commands, scripts, input files, and relevant environment configuration.
4. **Minimalism.** The interface exposes a terminal first and everything else second. The product should feel closer to opening a shell than opening a cloud IDE.
5. **Research-oriented.** The project supports legitimate experimentation, education, analysis, and research. It is not intended to provide unrestricted persistent infrastructure or long-running anonymous compute.

### 1.5 Product Identity

**TERMINUS.** Linux. Disposable. Browser-native.

> **A disposable Linux environment for research and experimentation.**

Short version:

> **Linux. One session. Then it's gone.**

Positioning used at discovery:

> A disposable Alpine Linux environment in your browser. No VM. No Docker. No installation.

---

## 2. Goals & Non-Goals

### 2.1 Goals

1. A new user MUST go from the public URL to an interactive Alpine shell without installing software or creating an account, within the time budgets of §6.1.
2. The terminal MUST support normal interactive shell usage to the extent permitted by the runtime (pipes, redirection, job basics, tab completion where the shell provides it).
3. The environment MUST support installing a defined subset of Alpine packages via `apk`, under the distribution model decided in D-004 / OQ-002.
4. Users MUST be able to create and manipulate files, upload a file into the session, and download a result; downloads MUST reflect session content byte-for-byte, and uploads MUST be discarded with the session.
5. Users MUST be able to destroy a session explicitly; a subsequent session MUST start from a clean filesystem with no residue (verified by TC-10).
6. The exact Alpine and runtime versions MUST be exposed so that results are verifiable (§5.3).
7. Documented resource limits (§6.1) MUST be enforced: memory, filesystem size, process count, and execution time.
8. Security and privacy documentation MUST be clear, and local versus remote execution MUST be truthfully disclosed (§7.2).

### 2.2 Non-Goals

TERMINUS is not intended to become:

1. A general-purpose cloud VPS.
2. An anonymous hosting service.
3. A persistent development environment.
4. A replacement for a local Linux installation.
5. A general-purpose malware execution platform.
6. A cloud storage service.

Explicitly out of scope for MVP: user accounts; persistent storage; cloud workspaces; multi-user collaboration; persistent background jobs; Kubernetes; full cloud IDE functionality; guaranteed support for arbitrary Linux kernel features; unrestricted network access; production hosting workloads.

Its defining property is **controlled ephemerality**.

---

## 3. Architecture

### 3.1 System Diagram

``` text
                         Browser
                            |
             +--------------+--------------+
             |                             |
        Main Thread                    Web Worker
             |                             |
        React / UI                      Runtime
             |                             |
         xterm.js                 WASM / Linux userspace
                                           |
                                      Alpine rootfs
                                           |
                                      Virtual FS
```

The main thread owns presentation and user interaction. The Web Worker owns the Linux runtime and session state. Communication occurs through browser messaging primitives (`postMessage` / `MessageChannel`).

### 3.2 Component Inventory

| Component | Responsibility | Technology | Notes |
|-----------|---------------|------------|-------|
| Web UI shell | Landing page, session chrome, upload/download/destroy controls | React + TypeScript, Vite | Main thread; no access to runtime internals |
| Terminal frontend | Render output, capture input, resize, paste | xterm.js | Main thread |
| Session controller | Owns lifecycle NEW → DESTROYED (§4.3); spawns/terminates worker | TypeScript (`packages/session`) | Single owner of session state |
| Runtime worker | Hosts execution engine, guest filesystem, processes | Web Worker | Isolation boundary for untrusted code (§7.1) |
| Linux userspace | Shell, core utilities, `apk` | Alpine Linux (version-pinned) | Base image immutable (§4.2) |
| Execution engine | Emulates CPU/filesystem for the userspace | **v86** (32-bit x86 → WASM JIT), pinned in `runtime/wasm` | Decided by spike P0 (D-001); Alpine **x86** port (OQ-003) |
| Virtual filesystem | Immutable base + writable session overlay | In-memory / OPFS-backed | Copy-on-write preferred (§4.2, OQ-005) |
| Protocol | Typed messages main thread ↔ worker | `postMessage` / `MessageChannel` (`packages/protocol`) | Defined in §5.1 |
| Terminal package | xterm wiring, fit/resize, input flow control | TypeScript (`packages/terminal`) | Shared UI glue |

### 3.3 Data Flow

1. **Startup:** user activates OPEN TERMINAL → session controller spawns the worker → runtime loads the pinned base image (HTTP cache) → mounts the session overlay → starts the shell → status and output events flow to xterm.js.
2. **Interaction:** keystroke → xterm.js → protocol `term.input` message → worker → runtime stdin → program output → protocol `term.output` message → xterm.js.
3. **File transfer:** upload bytes → protocol `fs.upload` → worker writes to an overlay path; download request → worker reads path → protocol `fs.download.result` → browser download.
4. **Destruction:** destroy command → terminate processes → discard overlay → terminate worker → release runtime resources. No recovery path exists (§4.3).

### 3.4 External Dependencies

| Dependency | Version | Purpose | Risk if Unavailable |
|-----------|---------|---------|---------------------|
| React / TypeScript / Vite | Pinned via lockfile | UI and build | Build breaks; already-deployed app shell keeps working via cache |
| xterm.js | Pinned via lockfile | Terminal rendering | No terminal UI |
| Alpine base image | Pinned 3.x + published hash | Userspace | Sessions cannot start; mitigated by CI-built, integrity-verified artifacts (§7.1) |
| WASM runtime | **v86** (npm `0.5.462`, BSD-2-Clause), vendored + sha-verified | Execution engine | P0 blocker resolved at D-001; artifact vendored in repo (`runtime/wasm`), still needs CI-side verification (§10.5) |
| First-party Alpine package mirror | Pinned APKINDEX + package hashes | `apk` package installation (D-004) | Package install unavailable; shell still works |
| Static hosting (GitHub Pages or Cloudflare Pages) | n/a | Delivery | Site unreachable; no backend state to lose (§8.4) |

---

## 4. Data Model

### 4.1 Core Entities

``` typescript
interface Session {
  id: string;
  createdAt: number;
  status:
    | "starting"
    | "running"
    | "destroying"
    | "destroyed";
}
```

Supporting entities: a **recipe** (declarative environment preset, §5.2) and an **environment manifest** (`environment.yaml`, §5.2) — both share the same schema.

### 4.2 Storage

There is **no database**. All state is client-side: runtime state lives in the worker, and the session filesystem follows a two-layer model:

``` text
Immutable Alpine Base
        |
        v
   Session Overlay
        |
        +-- /home
        +-- /tmp
        +-- installed packages
        +-- user-created files
        |
        v
     destroy()
        |
        X
```

- The implementation MUST prefer copy-on-write or equivalent mechanisms where available.
- The base image MUST NOT be modified by an individual session.
- The base image is a static, content-hashed artifact served over HTTP; browser cache handles reuse between sessions. The base image is downloaded only once per cache lifetime (§3.3, §6.1).

### 4.3 Data Lifecycle

``` text
NEW
 |
 v
STARTING
 |
 v
RUNNING
 |
 v
DESTROYING
 |
 +--> terminate processes
 +--> discard filesystem
 +--> terminate worker
 +--> release runtime resources
 |
 v
DESTROYED
```

A destroyed session MUST NOT be recoverable through the application. Closing the browser tab is an implicit destroy (§8.4). Nothing is retained outside the tab except optional error telemetry that MUST NOT contain command or file content (§8.3).

---

## 5. Interfaces

### 5.1 API Surface

There is no user-facing CLI or server API in MVP. The interface surfaces are the interactive terminal (§5.4) and the internal worker protocol:

``` typescript
type MainToWorker =
  | { type: "session.start"; image: ImageRef; limits: ResourceLimits }
  | { type: "term.input"; data: string }
  | { type: "fs.upload"; path: string; data: ArrayBuffer }
  | { type: "fs.download"; path: string; reqId: string }
  | { type: "session.destroy" };

type WorkerToMain =
  | { type: "session.status"; status: Session["status"] }
  | { type: "term.output"; data: string }
  | { type: "fs.download.result"; reqId: string; data: ArrayBuffer }
  | { type: "runtime.error"; code: string; message: string };
```

All messages MUST be validated on receipt; the worker MUST NOT accept messages outside this schema.

### 5.2 Configuration

Two artifacts share a single schema — `base` + `packages`:

``` yaml
base: alpine:3.x

packages:
  - python3
  - curl
  - jq
  - openssl
```

- **Recipes** are version-controlled presets shipped with the project. Initial recipe set (D-003): Network Research, Web Security, Malware Analysis, Digital Forensics, OSINT, Linux Fundamentals. Recipes MUST remain declarative and version-controlled; they provide preconfigured environments without turning the product into a cloud IDE.
- **`environment.yaml`** is the same schema exported from a running session so another researcher can start an equivalent clean environment (§5.3).

### 5.3 Output Formats

The session metadata panel exposes enough information to reproduce an experiment:

``` text
Environment
------------
OS: Alpine Linux
Version: 3.x
Architecture: x86_64
Runtime: <version>

Packages
--------
python3
curl
jq
openssl

Session
-------
Created: 2026-09-23
```

Version information MUST be verifiable both in the panel and inside the guest (e.g. `/etc/os-release`), satisfying Goal 6.

### 5.4 Interactive Interface (UX)

**Landing page** explains: what the environment is; that it is ephemeral; whether execution is local or remote; what data persists; the resource limits. Primary action: **OPEN TERMINAL**.

**Startup transcript:**

``` text
Initializing environment...
Downloading Alpine base image      100%
Initializing filesystem            100%
Starting runtime                   100%

Environment ready.

/ #
```

**Destruction** requires explicit confirmation:

> All processes and files created during this session will be permanently discarded.

``` text
Stopping processes...
Discarding filesystem...
Terminating runtime...

Session destroyed.
```

The user may immediately create a new clean session.

**Primary UI:**

``` text
+-------------------------------------------------------+
| TERMINUS                          Session: a81c2f      |
|-------------------------------------------------------|
|                                                       |
| / # apk add python3                                   |
| / # python3                                           |
| >>>                                                   |
|                                                       |
|                                                       |
+-------------------------------------------------------+
| Files | Upload | Download | Destroy Session           |
+-------------------------------------------------------+
```

The terminal is the product. Additional UI MUST NOT turn the application into a dashboard-heavy cloud IDE.

---

## 6. Performance & Capacity

### 6.1 Targets

> Refined with spike P0 measurements (2026-09-23, `docs/benchmarks.md`).
> Targets marked ⚠ were NOT met by the measured run and are re-baselined
> honestly (SPEC §6.2) before P1.

| Metric | Target | Boundary Condition |
|--------|--------|--------------------|
| Initial payload (app + runtime + base image, cold cache) | ≤ 25 MB compressed | Broadband, first visit, empty HTTP cache — **measured 13.7 MiB ✓** |
| Repeat load (warm cache) | ≤ 5 MB | App shell only; base image served from HTTP cache |
| Time to interactive prompt (cold) | ⚠ ≤ 10 s → **re-baselined ≈ 35 s** | Includes image fetch + runtime init — measured ≈31 s in software emulation |
| Time to interactive prompt (warm) | ⚠ ≤ 3 s → **re-baselined ≈ 8 s** | Cached assets |
| Keystroke → echo latency | ≤ 50 ms p95 | Local execution; main thread not blocked |
| Guest RAM | 256 MB default, 512 MB hard cap | Worker + WASM memory |
| Writable overlay size | ≤ 512 MB | Exhaustion surfaces ENOSPC, not a crash (§8.4) |
| Max processes (guest) | 256 | `fork` rejected beyond limit |
| Idle session timeout | 60 min → destroy | No stdin/stdout activity |
| Concurrent sessions | 1 per tab (MVP) | Tabs get independent sessions |

### 6.2 Bottlenecks & Limits

- **Emulation throughput** (measured, D-001): heavy compilation is slow — cold
  boot ≈31 s in software emulation (v86). Acceptable per §1.4, documented
  honestly in `docs/benchmarks.md`.
- **Cold-start image fetch** (OQ-004): mitigations are compression, HTTP
  caching, and lazy package fetch (P3).
- **Browser memory:** 32-bit WASM memory and browser tab budgets apply; OOM follows §8.4 — clear messaging, no false impression of persistence.
- **No kernel guarantees:** arbitrary Linux kernel features are out of scope (§2.2).
- **Network egress:** restricted to first-party static assets (§7.1); no raw sockets, no unrestricted outbound connections.

### 6.3 Scaling Strategy

Execution is client-side: capacity scales with static hosting bandwidth only, not server compute. There is no server-side scaling to manage for MVP. A future remote mode (§3.5) reintroduces server capacity planning and is out of MVP scope.

---

## 7. Security & Compliance

### 7.1 Threat Model

The user MUST be considered capable of executing arbitrary, intentionally hostile code inside the session (§1.4). Attack surfaces and controls:

- **Browser boundary.** The runtime MUST NOT obtain unrestricted access to DOM APIs, cookies, local storage belonging to unrelated components, browser credentials, arbitrary host filesystem paths, or privileged browser APIs. Enforced by Web Worker isolation (no DOM by construction), no privileged capability passing, and a strict CSP.
- **Runtime isolation.** Session code executes only inside the worker-scoped runtime; the UI thread stays separate; protocol messages are typed and validated (§5.1).
- **Filesystem isolation.** Only the session overlay is writable (§4.2); the base is immutable; a destroyed session is unrecoverable (§4.3).
- **Network.** Network access MUST be explicitly designed, never implicitly inherited. MVP prefers restricted or disabled egress except first-party static assets (base image, pinned package mirror). A safe runtime network mechanism, if any, must be validated before enabling egress (P3).
- **Resource exhaustion.** Limits on memory, CPU (worker termination), filesystem size, process count, execution time, and network activity (§6.1). A limit breach MUST terminate or reject gracefully, never hang the tab.
- **Supply chain.** The Alpine base image and runtime binaries MUST be version-pinned, integrity-verified, reproducibly built where feasible, and generated through CI (§8.2).
- **Abuse.** Not a malware-execution platform (§2.2); with no egress by default, a weaponised session has limited blast radius. An acceptable-use note ships with `docs/security.md` at P6.

### 7.2 Data Handling & Privacy

- **Local execution (MVP):** commands do not traverse a project server; session files remain in browser memory/runtime storage; destroying the runtime destroys session state.
- **Remote execution (future):** if a backend is introduced (§3.5), it MUST be clearly disclosed, session data handling MUST be documented, retention MUST be explicit, and the backend MUST destroy sessions according to the documented lifecycle.
- **The product MUST NEVER imply local execution if computation is actually performed remotely.**
- Uploaded files live ephemerally in the session and leave the browser only when the user downloads them; they are discarded on destroy.
- Optional telemetry (§8.3) MUST NOT include command contents, file names, or session filesystem content.

### 7.3 Compliance

- No accounts and no collection of user content by the operator; only standard static-hosting access logs exist (hoster's responsibility).
- No compliance certifications are targeted for MVP (no ISO/SOC2 scope).
- GDPR posture: no processing of user session data by the operator; users are responsible for the lawfulness of what they run (documented acceptable use).
- If a remote mode ships later (§3.5), data-processing obligations MUST be reassessed before launch.

---

## 8. Deployment & Operations

### 8.1 Infrastructure

- **Static hosting only** for MVP (GitHub Pages or Cloudflare Pages): SPA assets, base image, and optional package mirror are static files.
- If the chosen runtime requires `SharedArrayBuffer` (OQ-003), the host MUST serve COOP/COEP headers and keep assets same-origin/CORP-friendly.
- Feature detection runs at load; an unsupported browser MUST get a clear landing-page message (§8.4), never a broken terminal.

### 8.2 Build & Release

- **GitHub Actions** (`build.yml`): lint, unit tests, e2e tests, artifact build.
- Base image and runtime artifacts are built/pinned in CI with published hashes (§7.1 supply chain).
- Releases follow Semantic Versioning with `v0.x.y` while the API/schema is unstable, using the portfolio's Conventional Commits and git-flow conventions (`CONTRIBUTING_gitflow.md`).

### 8.3 Monitoring & Observability

- MVP has no server-side runtime to monitor.
- Optional client-side error reports: aggregated, without command or filesystem content (§7.2).
- Health: startup failures surface as session status plus a human-readable message (§8.4).

### 8.4 Failure Modes & Recovery

The application MUST handle: runtime initialization failure; unsupported browser; insufficient memory; runtime crash; filesystem exhaustion; package installation failure; worker termination; session timeout; browser tab closure.

A failed runtime MUST NEVER leave the user with the impression that a persistent environment still exists — the UI returns to a clean "start new session" state with an explanation. Tab closure is an implicit destroy with no recovery path (§4.3).

---

## 9. Testing Strategy

### 9.1 Unit Tests

Framework: **Vitest**.

- Session state machine (§4.3): legal/illegal transitions, destroy idempotence.
- Protocol validation (§5.1): malformed messages rejected.
- Overlay logic (§4.2): base stays read-only, ENOSPC behaviour.
- Recipe/manifest parsing (§5.2).

### 9.2 Integration Tests

- Worker boot harness: runtime loads the pinned image → `/bin/sh` responds (automates the P0 success criterion).
- stdin/stdout bridge round-trip.
- Upload → overlay path visible to the shell; download returns identical bytes.

### 9.3 End-to-End / Acceptance

Framework: **Playwright**. The MVP acceptance criteria are test cases:

| ID | Criterion |
|----|-----------|
| TC-01 | Open the public website |
| TC-02 | Start an Alpine session without an account |
| TC-03 | Obtain an interactive shell |
| TC-04 | Execute standard shell commands (echo, pipes, redirection) |
| TC-05 | Install a defined subset of packages (per OQ-002 model) |
| TC-06 | Create and manipulate files |
| TC-07 | Upload a file |
| TC-08 | Download a result (byte-identical) |
| TC-09 | Destroy the session: destroy transcript shown, clean state reached |
| TC-10 | Start a second session with a clean filesystem (no residue) |
| TC-11 | Documented Alpine/runtime version matches panel and `/etc/os-release` |
| TC-12 | Landing page accurately states persistence, limits, and local-vs-remote execution |

The MVP is successful when TC-01 … TC-12 are all green.

### 9.4 Performance Tests

- Payload budget check in CI against §6.1 (artifact size).
- Boot-time benchmark (warm vs cold) recorded in `docs/benchmarks.md`; regressions reviewed at each milestone.

---

## 10. Milestones & Deliverables

| Phase | Deliverable | Success Criteria | Target Date |
|-------|------------|------------------|-------------|
| **P0 — Runtime feasibility** ✅ done | Comparative spike: v86 vs container2wasm (D-001) | `browser → runtime → Alpine → /bin/sh` in a Web Worker — **met (v86)**; evidence in `docs/spike-p0.md` + `docs/benchmarks.md` | 2026-09-23 |
| **P1 — Terminal** | React, xterm.js, Web Worker, stdin/stdout bridge | `/ # echo hello` → `hello` | TBD |
| **P2 — Filesystem** | Immutable base, writable overlay, session reset | TC-10 passes: destroy → next session clean | TBD |
| **P3 — Package management** | Feasible model for `apk`, repositories, network (OQ-002) | TC-05 passes under restricted egress | TBD |
| **P4 — File transfer** | Upload/download | TC-07 and TC-08 pass | TBD |
| **P5 — Resource controls** | Memory, storage, process, lifetime limits (§6.1) | Limits enforced; breach → controlled failure (§8.4) | TBD |
| **P6 — Security review** | Threat model review: malicious shell code, runtime escape, browser escape, DoS, malicious package, supply-chain compromise, network abuse | Findings triaged; `docs/threat-model.md` published | TBD |
| **P7 — Public beta** | Site, documentation, examples, research recipes | All §9.3 test cases green; docs complete | TBD |

---

## 11. Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Selected runtime too slow or infeasible | High | Medium | Timeboxed comparative spike at P0 (D-001); dual candidates; document performance expectations honestly (§6.2) |
| Base image payload exceeds budget (§6.1) | Medium | Medium | Minimal rootfs, compression, HTTP caching, lazy package fetch (P3) |
| Browser matrix gaps (Safari; SharedArrayBuffer/COOP-COEP) | Medium | High | Feature detection, documented support matrix (OQ-003), graceful landing-page message |
| `apk` distribution model unresolved | High | Medium | Direction set by D-004 (first-party static mirror / `file://` repo); decision gated at P3 (OQ-002) |
| Scope creep toward cloud IDE / dashboard | Medium | High | UX constraint in §5.4 and non-goals in §2.2 enforced at review |
| Supply-chain compromise (image, runtime, mirror) | High | Low | Version pins, published hashes, CI-generated artifacts (§7.1, §8.2) |
| Perceived as a malware sandbox | Medium | Medium | Explicit non-goal (§2.2), no-egress default, acceptable-use docs at P6 |
| Upstream runtime abandoned or license change | High | Low | Two candidates retained (D-001), permissive license preferred, artifacts vendored in CI |
| Tab OOM/crash mistaken for data loss | Low | Medium | Failure-mode messaging (§8.4): sessions are disposable by design |

---

## 12. Decision Log

| ID | Decision | Rationale | Date | Status |
|----|----------|-----------|------|--------|
| D-001 | Defer runtime selection (v86 vs container2wasm/qemu-wasm) to a comparative spike at P0; this spec states required properties, not technology | §6 of v0.1 already required validation; avoids speculative lock-in | 2026-09-23 | Accepted |
| D-002 | Product and repository named **TERMINUS** (repo `terminus/`); "ephemeral Linux" is a descriptor, not the name | Single identity across repo, UI, and docs; resolves v0.1 mismatch (`spec_TERMINUS_*.md` vs "Ephemeral Linux") | 2026-09-23 | Accepted |
| D-003 | Initial recipe set = the six listed in §5.2; repository tree aligned | v0.1 listed 4 recipes in §7 and 6 in §12 | 2026-09-23 | Accepted |
| D-004 | Package distribution via a first-party static mirror (same origin) or a local `file://` repository; no open egress for `apk` | Reconciles Goal 3 (`apk`) with the network restriction in §7.1 | 2026-09-23 | Proposed (confirm at P3 / OQ-002) |
| D-005 | MVP MUST NOT require a backend, and the product MUST truthfully disclose local vs remote execution | Core promise (§1.2) and privacy model (§7.2) | 2026-09-23 | Accepted |
| **D-006** | **Runtime = v86** (32-bit x86 → WASM); Alpine **x86** port (`alpine-minirootfs-3.22.6-x86` + `vmlinuz-lts`); classic Web Worker + serial bridge (`console=ttyS0`) | Comparative spike P0 proved `browser → runtime → Alpine → /bin/sh` in a worker on v86 (boot ≈31 s, payload 13.7 MiB, zero errors — `docs/spike-p0.md`); c2w v0.8.4 blocked by upstream defects + 30-min build timeout without an artifact | 2026-09-23 | Accepted (supersedes D-001 deferral) |
| **D-007** | Project license = **AGPL-3.0** (`LICENSE`, `package.json`, README) | Open-source, copyleft, network-use clause matches a software-as-a-service-style web product; vendored binaries keep their own licenses (v86 BSD-2-Clause, Alpine kernel GPL-2.0) | 2026-09-23 | Accepted |

---

## 13. Open Questions

- [x] **OQ-001** — Runtime choice: **v86**, resolved by spike P0 (D-006; `docs/spike-p0.md`). c2w v0.8.4 rejected: upstream release-pipeline defects + timeboxed build exceeded without artifact.
- [ ] **OQ-002** — `apk` distribution model: static first-party mirror vs local `file://` repository vs disabled. Resolved at P3.
- [x] **OQ-003** — Runtime portability: v86 emulates **32-bit x86 only** → Alpine `x86` (i686) is the base port; x86_64 userspace out of scope until a 64-bit engine is viable. Remaining matrix (Safari, SharedArrayBuffer/COOP-COEP) still open at P1.
- [ ] **OQ-004** — Final numbers for the §6.1 budgets (payload, boot time, RAM, overlay size, idle timeout).
- [ ] **OQ-005** — Upload/session storage: in-memory filesystem vs OPFS-backed overlay.

---

## Appendices

### A. Glossary

- **Session** — The disposable lifecycle unit (§4.1): one worker + one runtime + one overlay.
- **Base image** — Immutable, version-pinned, integrity-verified Alpine rootfs artifact.
- **Overlay** — Per-session writable copy-on-write layer over the base (§4.2).
- **Runtime** — WASM execution engine hosting the Linux userspace; **v86** (D-006).
- **Recipe** — Declarative, version-controlled environment preset (`base` + `packages`, §5.2).
- **`environment.yaml`** — Manifest exported from a running session; same schema as a recipe.
- **Ephemeral / controlled ephemerality** — No state survives `destroy()`; the defining property of the product (§2.2).
- **Egress** — Outbound network traffic from the runtime; first-party static assets only in MVP (§7.1).

### B. References

- v86 — x86 emulator in WebAssembly — <https://github.com/copy/v86>
- container2wasm — Container images compiled to WASM — <https://github.com/container2wasm/container2wasm>
- qemu-wasm — QEMU compiled to WASM/WASI — <https://github.com/ktock/qemu-wasm>
- WebVM / CheerpX — Prior art (commercial base) — <https://webvm.io>
- WebContainers — Prior art (Node-style userspace, not Linux) — <https://webcontainers.io>
- Alpine Linux — <https://alpinelinux.org>
- xterm.js — <https://xtermjs.org>
- WASI — <https://wasi.dev>
- Cross-Origin Isolation / SharedArrayBuffer — <https://web.dev/articles/coop-coep>
- RFC 2119 — <https://www.ietf.org/rfc/rfc2119.txt>

### C. Target Repository Structure

``` text
terminus/
│
├── apps/
│   └── web/
│       └── src/
│           ├── components/
│           ├── terminal/
│           ├── session/
│           └── app/
│
├── runtime/
│   ├── alpine/
│   │   ├── rootfs/
│   │   └── build.sh
│   │
│   ├── wasm/
│   │   └── src/
│   │
│   └── filesystem/
│       ├── base/
│       └── overlay/
│
├── packages/
│   ├── terminal/
│   ├── protocol/
│   └── session/
│
├── recipes/
│   ├── network-research.yaml
│   ├── web-security.yaml
│   ├── malware-analysis.yaml
│   ├── digital-forensics.yaml
│   ├── osint.yaml
│   └── linux-fundamentals.yaml
│
├── docs/
│   ├── architecture.md
│   ├── security.md
│   ├── threat-model.md
│   ├── benchmarks.md
│   └── reproducibility.md
│
├── scripts/
│   ├── build-rootfs.sh
│   ├── build-runtime.sh
│   └── dev.sh
│
├── .github/
│   └── workflows/
│       └── build.yml
│
├── package.json
├── README.md
├── SPEC.md
└── LICENSE
```
