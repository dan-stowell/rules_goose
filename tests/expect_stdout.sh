#!/usr/bin/env bash
# Usage: expect_stdout.sh <program> <expected stdout> [program args...]
# Runs the program and compares what it writes to stdout, byte for byte, with
# the expected file (as upstream's samples/run_samples.py does; stderr, where
# the samples put timings, is not compared).
set -euo pipefail
prog="$1"
expected="$2"
shift 2
actual="${TEST_TMPDIR:-$(mktemp -d)}/stdout"
"$prog" "$@" > "$actual"
if ! cmp -s "$expected" "$actual"; then
  echo "stdout of $prog differs from $expected" >&2
  diff -u "$expected" "$actual" >&2 || true
  exit 1
fi
echo "PASS: stdout of $prog matches $expected"
