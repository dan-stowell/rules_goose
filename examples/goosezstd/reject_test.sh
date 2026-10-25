#!/bin/bash
# Checks that DECODER rejects each damaged FILE: -t and -d exit non-zero
# with a message on stderr.
# usage: reject_test.sh DECODER FILE...
set -uo pipefail
decoder=$1
shift
status=0
for f in "$@"; do
    if "$decoder" -t "$f" 2> "$TEST_TMPDIR/err"; then
        echo "FAIL: -t accepted $f"
        status=1
    elif [[ ! -s $TEST_TMPDIR/err ]]; then
        echo "FAIL: -t rejected $f without a message"
        status=1
    else
        echo "ok: $(< "$TEST_TMPDIR/err")"
    fi
    if "$decoder" -d "$f" -o "$TEST_TMPDIR/out" 2> /dev/null; then
        echo "FAIL: -d accepted $f"
        status=1
    fi
done
exit $status
