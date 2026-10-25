#!/usr/bin/env bash
# Usage: c_has_no_build_paths.sh <generated .c>...
# The C that goose_binary writes must be the same on every machine: it may not
# name the execroot, a sandbox, the output tree, or the staging directory.
set -euo pipefail
status=0
for c in "$@"; do
  if grep -n -E 'execroot|sandbox|bazel-out|/_goose/|\.goose-home' "$c" >&2; then
    echo "FAIL: $c names a build-specific path (lines above)" >&2
    status=1
  fi
done
[ "$status" = 0 ] && echo "PASS: no build-specific paths in $*"
exit "$status"
