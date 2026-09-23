#!/usr/bin/env bash
# Local dev server (SPEC §8.1 static hosting — no backend).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${1:-5173}"
echo "TERMINUS dev server → http://localhost:$PORT/apps/web/index.html"
exec python3 -m http.server "$PORT" --directory "$ROOT" --bind 127.0.0.1