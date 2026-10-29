#!/usr/bin/env bash
# Package the project for another machine (no venv, node_modules, local data or build caches).
#   bash scripts/pack.sh  →  ../thuetab-deploy.tar.gz
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="../thuetab-deploy.tar.gz"
tar czf "$OUT" --exclude=.venv --exclude=web/node_modules --exclude=.godot --exclude=data --exclude=.staging \
  --exclude=exports --exclude=.pytest_cache --exclude='__pycache__' --exclude=docs --exclude=addons \
  --exclude=.antigravitycli -C .. "$(basename "$PWD")"
ls -lh "$OUT"
