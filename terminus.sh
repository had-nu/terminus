#!/usr/bin/env bash
# TERMINUS - One-command launcher
# Usage: curl -fsSL https://raw.githubusercontent.com/had-nu/terminus/main/terminus.sh | bash
#        or: ./terminus.sh [build|dev|test|clean]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[TERMINUS]${NC} $*"; }
ok() { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err() { echo -e "${RED}[✗]${NC} $*"; }

check_deps() {
    local missing=()
    command -v node >/dev/null || missing+=("node")
    command -v npm >/dev/null || missing+=("npm")
    command -v curl >/dev/null || missing+=("curl")
    command -v sha256sum >/dev/null || missing+=("sha256sum")
    command -v tar >/dev/null || missing+=("tar")
    command -v gzip >/dev/null || missing+=("gzip")
    command -v cpio >/dev/null || missing+=("cpio")
    if [ ${#missing[@]} -gt 0 ]; then
        err "Missing dependencies: ${missing[*]}"
        echo "Install with: sudo apt-get install nodejs npm curl coreutils tar gzip cpio"
        exit 1
    fi
}

build_runtime() {
    log "Building WASM runtime (v86 + BIOS)..."
    bash scripts/build-runtime.sh
    ok "Runtime built"
}

build_rootfs() {
    log "Building Alpine rootfs + initramfs..."
    bash scripts/build-rootfs.sh
    ok "Rootfs built"
}

build_all() {
    log "Building TERMINUS (runtime + rootfs)..."
    build_runtime
    build_rootfs
    ok "Build complete"
}

start_dev() {
    log "Starting dev server on http://localhost:5173/apps/web/index.html"
    log "Press Ctrl+C to stop"
    # Keep script alive while server runs
    npx http-server -p 5173 -a 127.0.0.1 . &
    SERVER_PID=$!
    trap "kill $SERVER_PID 2>/dev/null; exit 0" INT TERM EXIT
    wait $SERVER_PID
}

run_tests() {
    log "Running prompt tests..."
    if [ ! -f "prompt-tests.js" ]; then
        err "prompt-tests.js not found"
        exit 1
    fi
    # Start server in background
    npx http-server -p 5173 -a 127.0.0.1 . > /tmp/terminus-server.log 2>&1 &
    SERVER_PID=$!
    trap "kill $SERVER_PID 2>/dev/null" EXIT
    sleep 3
    node prompt-tests.js
}

clean_all() {
    log "Cleaning build artifacts..."
    rm -rf runtime/alpine/out runtime/alpine/rootfs runtime/wasm/*.js runtime/wasm/*.wasm runtime/wasm/*.d.ts runtime/wasm/LICENSE.v86 runtime/wasm/src
    ok "Cleaned"
}

install_github() {
    log "Installing TERMINUS from GitHub..."
    local tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT
    cd "$tmpdir"
    log "Downloading..."
    curl -fsSL https://github.com/had-nu/terminus/archive/refs/heads/main.tar.gz | tar -xz
    cd terminus-main
    log "Building..."
    bash scripts/build-runtime.sh
    bash scripts/build-rootfs.sh
    log "Starting server..."
    npx http-server -p 5173 -a 127.0.0.1 . 2>/dev/null &
    SERVER_PID=$!
    sleep 3
    log "TERMINUS running at http://localhost:5173/apps/web/index.html"
    log "Press Ctrl+C to stop"
    wait $SERVER_PID
}

case "${1:-dev}" in
    build)
        check_deps
        build_all
        ;;
    dev)
        check_deps
        if [ ! -f "runtime/wasm/v86.wasm" ] || [ ! -f "runtime/alpine/out/initramfs-p0.cpio.gz" ]; then
            warn "Artifacts not found, building first..."
            build_all
        fi
        start_dev
        ;;
    test)
        check_deps
        if [ ! -f "runtime/wasm/v86.wasm" ] || [ ! -f "runtime/alpine/out/initramfs-p0.cpio.gz" ]; then
            warn "Artifacts not found, building first..."
            build_all
        fi
        run_tests
        ;;
    clean)
        clean_all
        ;;
    install)
        check_deps
        install_github
        ;;
    *)
        echo "TERMINUS - Disposable Alpine Linux in the browser"
        echo ""
        echo "Usage: $0 {build|dev|test|clean|install}"
        echo ""
        echo "Commands:"
        echo "  build    - Build runtime + rootfs (reproducible, sha256 verified)"
        echo "  dev      - Build if needed, then start dev server (default)"
        echo "  test     - Build if needed, run prompt tests"
        echo "  clean    - Remove all build artifacts"
        echo "  install  - Download from GitHub, build, and run (no clone needed)"
        echo ""
        echo "Quick start (no clone):"
        echo "  curl -fsSL https://raw.githubusercontent.com/had-nu/terminus/main/terminus.sh | bash -s install"
        exit 1
        ;;
esac