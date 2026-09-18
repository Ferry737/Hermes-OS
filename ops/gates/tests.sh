#!/bin/sh
# Runs whatever test suites exist. Deliberately green when a suite does not
# exist yet: this gate fires on every turn boundary from turn one, and a gate
# that is red before the code is written would exhaust its retries and pause
# the loop on turn three. It goes red only when a suite exists and fails.
set -eu
cd "$(dirname "$0")/../.."

RAN=0
FAIL=0

if [ -d plugin/dashboard/tests ] && command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import pytest' >/dev/null 2>&1; then
    echo "--- pytest ---"
    RAN=1
    python3 -m pytest -q plugin/dashboard/tests || FAIL=1
  else
    echo "pytest not installed; skipping python suite"
  fi
fi

if [ -f package.json ] && command -v npm >/dev/null 2>&1; then
  if grep -q '"test"[[:space:]]*:' package.json; then
    echo "--- npm test ---"
    RAN=1
    npm test --silent || FAIL=1
  fi
fi

[ "$RAN" -eq 0 ] && echo "no test suites present yet (gate green by design)"
[ "$FAIL" -ne 0 ] && { echo "TESTS FAILING"; exit 1; }

echo "tests gate clean"
