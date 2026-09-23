#!/usr/bin/env bash
# Build the WASM runtime layer (SPEC §5.1 runtime, D-001).
#
# v86 (BSDL-2, copy.sh) published on npm: pins libv86.js + v86.wasm + BIOS.
# Outputs (gitignored):
#   runtime/wasm/{libv86.js,v86.wasm,v86.d.ts,LICENSE.v86}
#   runtime/wasm/src/          (TypeScript wrapper, lands P1)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WASM="$ROOT/runtime/wasm"
BIOS="$ROOT/runtime/alpine/bios"
mkdir -p "$WASM/src" "$BIOS"

V86_VERSION="0.5.462"
V86_RAW="https://raw.githubusercontent.com/copy/v86/master/bios"

PIN_SEABIOS="73e3f359102e3a9982c35fce98eb7cd08f18303ac7f1ba6ebfbe6cdc1c244d98"
PIN_VGABIOS="a4bc0d80cc3ca028c73dafa8fee396b8d054ce87ebd8abfbd31b06b437607880"
verify() { echo "$1  $2" | sha256sum -c -; }

# BIOS
[ -f "$BIOS/seabios.bin" ] || curl -fsSL --max-time 120 "$V86_RAW/seabios.bin" -o "$BIOS/seabios.bin"
verify "$PIN_SEABIOS" "$BIOS/seabios.bin"
[ -f "$BIOS/vgabios.bin" ] || curl -fsSL --max-time 120 "$V86_RAW/vgabios.bin" -o "$BIOS/vgabios.bin"
verify "$PIN_VGABIOS" "$BIOS/vgabios.bin"

# v86 runtime (official npm package, published from copy/v86 via CI --provenance)
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
( cd "$TMP" && npm pack "v86@$V86_VERSION" --silent >/dev/null )
tar -xzf "$TMP"/v86-*.tgz -C "$TMP"
cp "$TMP/package/build/libv86.js" "$WASM/libv86.js"
cp "$TMP/package/build/v86.wasm"   "$WASM/v86.wasm"
cp "$TMP/package/v86.d.ts"         "$WASM/v86.d.ts"
cp "$TMP/package/LICENSE"          "$WASM/LICENSE.v86"
cp "$TMP/package/build/libv86.mjs" "$WASM/libv86.mjs"

echo "✓ v86 runtime vendored: $(du -sh "$WASM" | cut -f1)"
echo "  $WASM (libv86.js, v86.wasm, LICENSE.v86)"