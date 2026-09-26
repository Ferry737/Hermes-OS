#!/bin/sh
# Runs the Orchestra backend tests. Green before the suite exists; red when it exists and
# fails, or when it exists but cannot run (a suite that silently skips is not a pass).
set -eu
cd "$(dirname "$0")/../../.."
T=orchestra/backend/tests
[ -d "$T" ] || { echo "no orchestra test suite yet (gate green by design)"; exit 0; }

PY=""
for c in orchestra/backend/.venv/bin/python /opt/data/orchestra/.venv/bin/python python3; do
  if [ -x "$c" ] || command -v "$c" >/dev/null 2>&1; then
    if "$c" -c 'import pytest, fastapi, httpx' >/dev/null 2>&1; then PY=$c; break; fi
  fi
done
[ -n "$PY" ] || {
  echo "TESTS CANNOT RUN: no python with pytest+fastapi+httpx."
  echo "Fix: python3 -m venv orchestra/backend/.venv && orchestra/backend/.venv/bin/pip install -e 'orchestra/backend[dev]'"
  exit 1; }

case "$PY" in /*|python3) ;; *) PY="$(pwd)/$PY" ;; esac   # absolute path before cd
echo "--- pytest ($PY) ---"
(cd orchestra/backend && "$PY" -m pytest -q) || { echo "TESTS FAILING"; exit 1; }
echo "tests gate clean"
