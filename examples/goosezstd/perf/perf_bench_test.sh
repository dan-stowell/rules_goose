#!/bin/bash
# Throughput of several decoders on the same inputs, decoding to /dev/null,
# each run RUNS times; prints min and median MB/s per decoder and input.
# usage: perf_bench_test.sh RUNS ZSTD (NAME=DECODER)... -- (ORIGINAL COMPRESSED)...
set -euo pipefail
runs=$1 zstd=$2
shift 2
names=() decs=()
while [[ $1 != -- ]]; do names+=("${1%%=*}"); decs+=("${1#*=}"); shift; done
shift
now() { local t=${EPOCHREALTIME/[.,]/}; echo "$t"; }
echo "host: $(nproc) cpus; $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null || true)"
echo "perf: $(command -v perf || echo none)"
while (( $# )); do
    orig=$1 comp=$2
    shift 2
    size=$(stat -L -c %s "$orig")
    echo "== $(basename "$comp"): $size -> $(stat -L -c %s "$comp") bytes"
    for i in "${!decs[@]}"; do
        d=${decs[$i]} n=${names[$i]}
        if [[ $n == zstd_t ]]; then cmd=("$d" -q -f -t "$comp")
        elif [[ $n == zstd* ]]; then cmd=("$d" -q -f -d -c "$comp")
        elif [[ $n == *_t ]]; then cmd=("$d" -t "$comp")
        else cmd=("$d" -d "$comp"); fi
        if [[ $n != *_t ]]; then
            "${cmd[@]}" > "$TEST_TMPDIR/out"
            cmp "$TEST_TMPDIR/out" "$orig"
        fi
        ts=()
        for ((r = 0; r < runs; r++)); do
            t0=$(now); "${cmd[@]}" > /dev/null 2>&1; t1=$(now)
            ts+=($(( t1 - t0 )))
        done
        sorted=($(printf '%s\n' "${ts[@]}" | sort -n))
        min=${sorted[0]} med=${sorted[$(( runs / 2 ))]} max=${sorted[$(( runs - 1 ))]}
        printf '  %-14s best %5d MB/s  median %5d MB/s  worst %5d MB/s\n' "$n" $(( size / min )) $(( size / med )) $(( size / max ))
    done
done
