#!/bin/bash
# Decompresses COMPRESSED with DECODER (goosezstd's command line) to a file,
# to stdout and from stdin, and checks each result byte for byte against
# ORIGINAL; then checks that -t accepts it.
# usage: decompress_test.sh DECODER COMPRESSED ORIGINAL
set -euo pipefail
decoder=$1 compressed=$2 original=$3
out=$TEST_TMPDIR/out

"$decoder" -d "$compressed" -o "$out"
cmp "$out" "$original"
"$decoder" -d "$compressed" > "$out.stdout"
cmp "$out.stdout" "$original"
"$decoder" -d - < "$compressed" > "$out.stdin"
cmp "$out.stdin" "$original"
"$decoder" -t "$compressed"
