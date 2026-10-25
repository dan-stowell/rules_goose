#!/usr/bin/env bash
# Usage: expect_failure.sh <program> <text>
# Passes when the program exits non-zero and its stderr contains <text>.
set -uo pipefail
stderr="$("$1" 2>&1 >/dev/null)"
status=$?
if [[ "$status" == 0 ]]; then
  echo "FAIL: $1 exited 0" >&2
  exit 1
fi
if [[ "$stderr" != *"$2"* ]]; then
  echo "FAIL: stderr of $1 does not contain: $2" >&2
  echo "$stderr" >&2
  exit 1
fi
