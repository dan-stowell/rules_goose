#!/usr/bin/env bash
# Usage: expect_stdout.sh <program> <expected stdout> [program args...]
# Runs the program and compares its stdout with the expected file, ignoring
# trailing newlines, as upstream's samples/run_samples.py does. stderr, where
# the samples put timings, is not compared.
set -euo pipefail
prog="$1"
expected="$2"
shift 2
want="$(< "$expected")"
got="$("$prog" "$@")"
diff -u <(printf '%s\n' "$want") <(printf '%s\n' "$got")
