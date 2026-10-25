#!/usr/bin/env bash
# Usage: c_has_no_build_paths.sh <generated .c>...
# The C that goose_binary writes must be the same on every machine and in every
# sandbox: it may not name the execroot, a sandbox, the output tree, or the
# staging directory.
set -uo pipefail
# grep exits 1 when nothing matches, 0 on a match and 2 on an error.
grep -HnE 'execroot|sandbox|bazel-out|/_goose/|\.goose-home|/home/|/tmp/|/private/var/' "$@"
[[ $? == 1 ]]
