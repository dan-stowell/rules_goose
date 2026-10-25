#!/bin/bash
# Checks that DECODER rejects each damaged FILE: -t and -d exit with status
# 1 (a decoding error: not a crash, a usage error or a missing program),
# -t with a message on stderr.
# usage: reject_test.sh DECODER FILE...
set -uo pipefail
decoder=$1
shift
status=0
for f in "$@"; do
    [[ -x $decoder && -s $f ]] || { echo "FAIL: missing $decoder or $f"; exit 1; }
    "$decoder" -t "$f" 2> "$TEST_TMPDIR/err"
    code=$?
    if (( code != 1 )); then
        echo "FAIL: -t exited $code on $f: $(< "$TEST_TMPDIR/err")"
        status=1
    elif [[ ! -s $TEST_TMPDIR/err ]]; then
        echo "FAIL: -t rejected $f without a message"
        status=1
    else
        echo "ok: $(< "$TEST_TMPDIR/err")"
    fi
    "$decoder" -d "$f" -o "$TEST_TMPDIR/out" 2> /dev/null
    code=$?
    if (( code != 1 )); then
        echo "FAIL: -d exited $code on $f"
        status=1
    fi
done
exit $status
