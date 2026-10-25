#!/usr/bin/env bash
# Usage: cli_test.sh <goosegrep> <a file in testdata/> <expected stdout> <expected exit code> [args...]
# Runs goosegrep with the args from inside the testdata tree and checks its
# exit code and its stdout.
set -uo pipefail
prog="$PWD/$1"
tree="$(dirname "$2")"
expected="$PWD/$3"
want_code="$4"
shift 4
got="$TEST_TMPDIR/got"
cd "$tree" || exit 1
"$prog" "$@" > "$got"
code=$?
fail=0
if [[ "$code" != "$want_code" ]]; then
  echo "FAIL: goosegrep $* exited $code, want $want_code" >&2
  fail=1
fi
if ! diff -u "$expected" "$got" >&2; then
  echo "FAIL: stdout of goosegrep $* differs from $3" >&2
  fail=1
fi
if [[ "$fail" == 0 ]]; then echo "PASS: goosegrep $*"; fi
exit "$fail"
