#!/usr/bin/env bash
# Usage: cli_test.sh <goosegrep> <a file in testdata/> <expected stdout> <expected exit code> [args...]
# Runs goosegrep with the args from inside the testdata tree and checks its
# exit code and its stdout (ignoring trailing newlines). Bash builtins only,
# so that it runs on executors without coreutils (actiond).
set -uo pipefail
prog="$PWD/$1"
tree="${2%/*}"
expected="$3"
want="$(< "$expected")"
want_code="$4"
shift 4
cd "$tree" || exit 1
got="$("$prog" "$@")"
code=$?
fail=0
if [[ "$code" != "$want_code" ]]; then
  echo "FAIL: goosegrep $* exited $code, want $want_code" >&2
  fail=1
fi
if [[ "$got" != "$want" ]]; then
  echo "FAIL: stdout of goosegrep $* differs from $expected" >&2
  echo "--- want:" >&2
  printf '%s\n' "$want" >&2
  echo "--- got:" >&2
  printf '%s\n' "$got" >&2
  fail=1
fi
if [[ "$fail" == 0 ]]; then echo "PASS: goosegrep $*"; fi
exit "$fail"
