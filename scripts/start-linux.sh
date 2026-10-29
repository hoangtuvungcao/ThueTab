#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -x ".venv/bin/python3" ]; then
    .venv/bin/python3 scripts/local.py --setup
else
    python3 scripts/local.py --setup
fi
