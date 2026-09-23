# TERMINUS

Disposable **Alpine Linux** environments in the browser — ephemeral, client-side,
no account, no backend. Point a browser at the page, get a root shell, close the
tab and everything is gone (SPEC §1, §2).

> **Nothing to install. Nothing to maintain. Nothing to clean up.**

> **Status: P0 spike** — runtime feasibility proven with **v86**:
> `browser → runtime → Alpine → /bin/sh` inside a Web Worker.
> Details: [docs/spike-p0.md](docs/spike-p0.md). The spec:
> [SPEC.md](SPEC.md).

## Run the P0 spike

```bash
npm run build:p0     # fetch + verify + assemble rootfs/initramfs + vendor v86 (sha256-pinned)
npm run dev          # static server on http://localhost:8000
# open http://localhost:8000/apps/web/index.html → Alpine boots to a shell
```

## Repository layout

Canonical tree per [SPEC.md](SPEC.md) **App. C — Target Repository Structure**.
As of the P0 spike, `apps/web/` and `docs/` also carry the spike files below.

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

> P0 notes: `apps/web/` currently has the vanilla spike page (`index.html`,
> `p0-page.js`, `p0-worker.js`) until P1 (React + xterm.js); `runtime/alpine/build.sh`
> is implemented as `scripts/build-rootfs.sh` + `scripts/build-runtime.sh`, and
> `docs/security.md` / `docs/threat-model.md` land at P6. See
> [docs/architecture.md](docs/architecture.md).

## Deliberate choices (recorded in SPEC Decision Log)

- **Runtime roads tested** — v86 vs container2wasm (D-001); P0 picks v86.
- **32-bit Alpine x86** — v86 does not emulate x86_64; USE the Alpine `x86`
  port, not `x86_64` (OQ-003).
- **No backend required** (D-005) — MVP static-hostable.
- **Ephemeral by construction** — all state lives in the worker's memory.

## License

**AGPL-3.0** (see [LICENSE](LICENSE); recorded as decision D-007 in
[SPEC.md](SPEC.md)). Binaries vendored under their own licenses:
v86 © copy.sh, BSD-2-Clause (`runtime/wasm/LICENSE.v86`);
Alpine Linux © Alpine contributors, GPL-2.0 (kernel) / MIT-ish (userland).