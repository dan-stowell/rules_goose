#!/bin/bash
# Checks that DECODER rejects each damaged FILE for the expected reason: -t
# and -d exit with status 1 (a decoding error: not a crash, a usage error or
# a missing program), and -t's message on stderr contains MESSAGE.
# usage: reject_test.sh DECODER (FILE MESSAGE)...
set -uo pipefail
decoder=$1
shift
status=0
while (( $# )); do
    f=$1 want=$2
    shift 2
    [[ -x $decoder && -e $f ]] || { echo "FAIL: missing $decoder or $f"; exit 1; }
    "$decoder" -t "$f" 2> "$TEST_TMPDIR/err"
    code=$?
    err=$(< "$TEST_TMPDIR/err")
    if (( code != 1 )); then
        echo "FAIL: -t exited $code on $f: $err"
        status=1
    elif [[ $err != *"$want"* ]]; then
        echo "FAIL: -t rejected $f with \"$err\", not \"$want\""
        status=1
    else
        echo "ok: $err"
    fi
    "$decoder" -d "$f" -o "$TEST_TMPDIR/out" 2> /dev/null
    code=$?
    if (( code != 1 )); then
        echo "FAIL: -d exited $code on $f"
        status=1
    fi
done
exit $status
