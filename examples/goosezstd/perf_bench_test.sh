#!/bin/bash
# Throughput of several decoders on the same inputs, printed to the test
# log: each decodes each COMPRESSED file to /dev/null RUNS times, after one
# checked run, and the best, median and worst MB/s are printed. A decoder
# that fails or gets the output wrong is reported, and fails the test at
# the end. Build with -c opt for meaningful numbers.
# usage: perf_bench_test.sh RUNS (NAME=DECODER)... -- (ORIGINAL COMPRESSED)...
# A decoder named zstd is the zstd CLI; the others take goosezstd's flags.
set -euo pipefail
runs=$1
shift
names=() decs=()
while [[ $1 != -- ]]; do names+=("${1%%=*}"); decs+=("${1#*=}"); shift; done
shift

# Microseconds since the epoch, from bash's EPOCHREALTIME.
now() { local t=${EPOCHREALTIME/[.,]/}; echo "$t"; }

echo "host: $(nproc) cpus; $(grep -m1 'model name' /proc/cpuinfo || true)"
failed=0
while (( $# )); do
    orig=$1 comp=$2
    shift 2
    size=$(stat -L -c %s "$orig")
    echo "== $(basename "$comp"): $(stat -L -c %s "$comp") -> $size bytes"
    for i in "${!decs[@]}"; do
        n=${names[$i]}
        if [[ $n == zstd ]]; then cmd=("${decs[$i]}" -q -f -d -c "$comp")   # -f: a runfiles symlink
        else cmd=("${decs[$i]}" -d "$comp"); fi
        if ! "${cmd[@]}" > "$TEST_TMPDIR/out" || ! cmp -s "$TEST_TMPDIR/out" "$orig"; then
            printf '  %-14s FAILED\n' "$n"
            failed=1
            continue
        fi
        ts=()
        for ((r = 0; r < runs; r++)); do
            t0=$(now); "${cmd[@]}" > /dev/null; t1=$(now)
            ts+=($(( t1 - t0 )))
        done
        sorted=($(printf '%s\n' "${ts[@]}" | sort -n))
        best=${sorted[0]} med=${sorted[$(( runs / 2 ))]} worst=${sorted[$(( runs - 1 ))]}
        printf '  %-14s best %5d MB/s  median %5d MB/s  worst %5d MB/s\n' \
            "$n" $(( size / best )) $(( size / med )) $(( size / worst ))
    done
done
exit $failed
