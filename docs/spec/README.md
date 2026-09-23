# TERMINUS — Specificação Amigável

> A versão técnica completa (decisions log, open questions, Appendix A–C) vive em
> [`docs/SPEC.md`](../SPEC.md) — este ficheiro é um resumo legível para humanos.

---

## O que é o TERMINUS?

**Ambientes Alpine Linux descartáveis no browser.**
- Sem instalação. Sem backend. Sem conta.
- Abres a página → tens um shell root → fechas o separador → tudo desaparece.

---

## Como funciona (visão geral)

```
┌─────────────────────────────────────────────────────────────┐
│                    O TEU BROWSER                             │
│  ┌──────────────────┐         ┌──────────────────────────┐  │
│  │  Main Thread     │         │  Web Worker (isolado)    │  │
│  │  (UI / xterm.js) │ ←──→    │  v86 (x86 → WASM JIT)    │  │
│  │                  │ postMsg │  Alpine kernel + initrd  │  │
│  └──────────────────┘         │  serial console (ttyS0)  │  │
│                               └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

- **Main thread** = só UI (xterm.js, botões, estado de sessão).
- **Web Worker** = runtime Linux completo (kernel 32-bit, userspace Alpine).
- **Comunicação** = `postMessage` / `MessageChannel` (protótipo tipado em `packages/protocol`).
- **Persistência** = zero. O worker morre → a sessão morre → nada fica no disco.

---

## Receitas (environments prontos)

| Receita | Para quê | Pacotes chave |
|---------|----------|---------------|
| `network-research` | Reconhecimento de rede | nmap, masscan, zmap, traceroute |
| `web-security` | Auditoria de apps web | nikto, sqlmap, gobuster, ffuf, wafw00f |
| `malware-analysis` | Análise estática/dinâmica | yara, binwalk, volatility3, radare2, ghidra |
| `digital-forensics` | Forense de disco/memória | sleuthkit, autopsy, volatility3, bulk-extractor |
| `osint` | Inteligência de fontes abertas | theharvester, sherlock, social-analyzer, photon |
| `linux-fundamentals` | Aprender Linux | vim, htop, man, bash-completion, lsof, strace |

Cada receita = `environment.yaml` declarativo (base image + lista de pacotes `apk`).

---

## Decisões-chave (resumo)

| ID | Decisão | Porquê |
|----|---------|--------|
| **D-006** | Runtime = **v86** (32-bit x86) | Spike P0 provou `browser → v86 → Alpine → /bin/sh` em ~31 s, 13.7 MiB; container2wasm falhou (build >30 min, defeitos upstream). |
| **D-005** | **Sem backend** obrigatório | Hosting estático; privacidade por design. |
| **D-007** | Licença = **AGPL-3.0** | Copyleft com cláusula de uso em rede; binários vendored mantêm as suas licenças. |
| **OQ-003** | Alpine **x86 (i686)** | v86 não emula x86_64. |

---

## Métricas P0 (medidas)

| Métrica | Valor | Target §6.1 |
|---------|-------|-------------|
| Payload cold cache | **13.7 MiB** | ≤ 25 MiB ✓ |
| Boot cold → prompt | **≈ 31 s** | re-baselined (era 10 s) |
| Guest RAM | 256 MiB | 256 MiB ✓ |
| Erros durante boot | 0 | — |

Evidência bruta: `docs/evidence/p0-v86-evidence.json` + `p0-v86-terminal.png`.

---

## Como correr (P0 spike)

```bash
# 1) Clona e entra
git clone <repo> && cd terminus

# 2) Constrói artefactos (fetch + sha256 + initramfs + vendor v86)
npm run build:p0

# 3) Servidor estático
npm run dev
# → abre http://localhost:5173/apps/web/index.html
```

Os scripts (`scripts/build-rootfs.sh`, `scripts/build-runtime.sh`) são **reprodutíveis**: pins com sha256, falham se o hash não bater.

---

## Estrutura do repositório

Ver [App. C da spec](../SPEC.md#c-target-repository-structure) ou `docs/architecture.md`.

---

## Roadmap (milestones)

| Fase | Entregável | Estado |
|------|------------|--------|
| **P0** | Runtime feasibility (v86 → Alpine → shell) | done |
| **P1** | Terminal (React + xterm.js + worker stdin/stdout) | próximo |
| **P2** | Filesystem (base imutável + overlay CoW + reset) | planeado |
| **P3** | Package management (`apk` via mirror/local repo) | planeado |
| **P4** | File transfer (upload/download) | planeado |
| **P5** | Resource controls (memória, processos, timeout) | planeado |
| **P6** | Security review + threat model | planeado |
| **P7** | Public beta (site, docs, exemplos) | planeado |

---

## Contribuir

1. Lê a [spec técnica completa](../SPEC.md) — é a fonte de verdade.
2. Branches: `develop` = integração; `main` = releases; `feat/*` por feature (git-flow).
3. Commits: **Conventional Commits** (`feat:`, `fix:`, `docs:`, `chore:`).
4. CI: `.github/workflows/build.yml` reconstrói artefactos e corre smoke test.
5. PRs contra `develop`; merge `--no-ff`.

---

## Licença

**AGPL-3.0** — ver [LICENSE](../../LICENSE) e decisão [D-007](../SPEC.md#d-007).
Binários vendored: v86 (BSD-2-Clause), Alpine kernel (GPL-2.0).