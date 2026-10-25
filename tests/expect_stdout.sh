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
if [[ "$got" != "$want" ]]; then
  echo "FAIL: stdout of $prog differs from $expected" >&2
  mapfile -t w <<< "$want"
  mapfile -t g <<< "$got"
  for ((i = 0; i < ${#w[@]} || i < ${#g[@]}; i++)); do
    if [[ "${w[i]-<missing>}" != "${g[i]-<missing>}" ]]; then
      echo "first difference at line $((i + 1)):" >&2
      echo "  want: ${w[i]-<missing>}" >&2
      echo "  got:  ${g[i]-<missing>}" >&2
      break
    fi
  done
  echo "--- got:" >&2
  printf '%s\n' "$got" >&2
  exit 1
fi
echo "PASS: stdout of $prog matches $expected"
