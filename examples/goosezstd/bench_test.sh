#!/bin/bash
# A rough throughput comparison, printed to the test log: decompresses each
# COMPRESSED file (to /dev/null) with goosezstd and with the real zstd,
# best of three runs each. Passes as long as both decode it correctly.
# Build with -c opt for meaningful numbers.
# usage: bench_test.sh GOOSEZSTD ZSTD ORIGINAL COMPRESSED...
set -euo pipefail
goosezstd=$1 zstd=$2 original=$3
shift 3

# Microseconds since the epoch, from bash's EPOCHREALTIME.
now() { local t=${EPOCHREALTIME/[.,]/}; echo "$t"; }

best() {
    local best=0 i t0 t1
    for i in 1 2 3; do
        t0=$(now)
        if ! "$@" > /dev/null; then echo "failed: $*" >&2; exit 1; fi
        t1=$(now)
        if (( best == 0 || t1 - t0 < best )); then best=$(( t1 - t0 )); fi
    done
    echo "$best"
}

size=$(stat -L -c %s "$original")
for f in "$@"; do
    "$goosezstd" -d "$f" -o "$TEST_TMPDIR/out"
    cmp "$TEST_TMPDIR/out" "$original"
    g=$(best "$goosezstd" -d "$f")
    z=$(best "$zstd" -q -f -d -c "$f")   # -f: the input is a runfiles symlink
    echo "$(basename "$f"): $size bytes; goosezstd $(( size / g )) MB/s, zstd $(( size / z )) MB/s, zstd is $(( g / z )).$(( g * 10 / z % 10 ))x faster"
done
