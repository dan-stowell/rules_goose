#!/usr/bin/env bash
# Usage: c_has_no_build_paths.sh <generated .c>...
# The C that goose_binary writes must be the same on every machine and in every
# sandbox: it may not name the execroot, a sandbox, the output tree, or the
# staging directory.
set -euo pipefail
status=0
for c in "$@"; do
  text="$(< "$c")"
  for bad in execroot sandbox bazel-out /_goose/ .goose-home /home/ /tmp/ /private/var/; do
    if [[ "$text" == *"$bad"* ]]; then
      echo "FAIL: $c contains \"$bad\"" >&2
      while IFS= read -r line; do
        [[ "$line" == *"$bad"* ]] && echo "  $line" >&2
      done <<< "$text"
      status=1
    fi
  done
done
[[ "$status" == 0 ]] && echo "PASS: no build-specific paths in $*"
exit "$status"
