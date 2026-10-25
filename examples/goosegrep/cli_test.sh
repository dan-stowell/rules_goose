#!/usr/bin/env bash
# Usage: cli_test.sh <goosegrep> <a file in testdata/> <expected stdout> <expected exit code> [args...]
# Copies the testdata tree (runfiles may be symlinks, which goosegrep's walk
# skips), runs $SETUP in the copy, then goosegrep with the args, and checks
# its exit code and its stdout.
set -uo pipefail
prog="$PWD/$1"
tree="$(dirname "$2")"
expected_rel="$3"
expected="$PWD/$3"
want_code="$4"
shift 4
got="$TEST_TMPDIR/got"
copy="$TEST_TMPDIR/tree"
mkdir -p "$copy" && cp -RL "$tree/." "$copy" || exit 1
cd "$copy" || exit 1
if [[ -n "${SETUP:-}" ]]; then
  eval "$SETUP" || { echo "FAIL: setup failed: $SETUP" >&2; exit 1; }
fi
"$prog" "$@" > "$got"
code=$?
fail=0
if [[ "$code" != "$want_code" ]]; then
  echo "FAIL: goosegrep $* exited $code, want $want_code" >&2
  fail=1
fi
if ! diff -u "$expected" "$got" >&2; then
  echo "FAIL: stdout of goosegrep $* differs from $expected_rel" >&2
  fail=1
fi
if [[ "$fail" == 0 ]]; then echo "PASS: goosegrep $*"; fi
exit "$fail"
