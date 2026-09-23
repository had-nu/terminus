# Reproducibility

SPEC §10.5: artifacts MUST be version-pinned and sha256-verified. CI builds
reproducibly from source scripts; nothing generated is committed to the repo.

## Reproducible build

```bash
bash scripts/build-rootfs.sh    # fetch + verify + assemble rootfs/initramfs
bash scripts/build-runtime.sh   # vendor v86 runtime + BIOS (npm pack, sha256 pins)
npm run build:p0                # both, sequentially
```

Both scripts verify every pin with `sha256sum -c -` and fail on mismatch
(SPEC §7.1 supply-chain).

## Current pins

| Artifact | Version/ref | sha256 (verified in CI) |
|---|---|---|
| Alpine `vmlinuz-lts` (x86) | 3.22.6 (kernel 6.12.110-0-lts) | `67656fdd…d54de` |
| Alpine `minirootfs` (x86) | 3.22.6 | `664ff599…c18ae8` |
| SeaBIOS / VGA BIOS | copy/v86 master (fetched) | `73e3f359…444d98` / `a4bc0d80…7607880` |
| v86 runtime | npm `v86@0.5.462` (packed; unmodified) | hash of npm tarball verified at fetch time by npm |
| c2w (used only for spike comparison, not shipped) | v0.8.4 linux-amd64 | `1142ab95…00f31` |

Pins live at the top of `scripts/build-rootfs.sh` / `scripts/build-runtime.sh`
as `PIN_*` variables — single source of truth.

## Reproducibility observations

- **Initramfs** rebuilt by `build-rootfs.sh` is byte-stable for identical
  rootfs + `/init` (deterministic `cpio -H newc` + `gzip -9`; no timestamps
  embedded in the produce output — verified twice, same sha
  `61bd18343559…`).
- **v86 runtime** comes from the published npm package, unpacked verbatim;
  no patching (MIT/BSD-2-Clause preserved, LICENSE vendored).
- **c2w was NOT vendored** into the product — it was spike-only tooling; its
  output was not reproducible within the spike (release-pipeline defects —
  see `docs/spike-p0.md`).