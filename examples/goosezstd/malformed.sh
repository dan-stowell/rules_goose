#!/bin/bash
# Writes hand-made malformed zstd frames to OUTDIR, one decoder check each.
# Every frame but the first two starts with HDR: the magic number, a frame
# header with no content size, checksum or dictionary, and a 1 KiB window.
# Block headers are 3 bytes little-endian: last (bit 0), type (bits 1-2,
# 0 raw, 2 compressed), size (bits 3-23).
# usage: malformed.sh OUTDIR
set -euo pipefail
out=$1

# Writes the bytes spelled by a string of hex digits.
hex() { printf "$(sed 's/../\\x&/g' <<< "$1")"; }
HDR=28b52ffd0000

: > "$out/empty.zst"

# Huffman weights stored with FSE, whose stream has no bits left after its
# end marker, so nothing to initialize the two 5-bit states from.
hex 28b52ffd00005500001280010410f801010300 > "$out/huf_fse_init_truncated.zst"

# Sequences with the predefined tables (6 + 5 + 6 state bits) and a stream
# of no bits.
hex ${HDR}250000''00010001 > "$out/seq_fse_init_truncated.zst"

# Huffman literals with directly stored weights 1 and 3: a sum of 5 that no
# last weight completes to a power of two.
hex ${HDR}3d0000''42c000''8113''01''00 > "$out/huf_bad_weights.zst"

# A literal-length FSE table with accuracy log 10 (the limit is 9).
hex ${HDR}350000''00''0180''050001 > "$out/fse_log_too_large.zst"

# An offset FSE table whose counts do not fill its 32 states: one symbol of
# probability 0, then runs of zeros past the last symbol.
hex ${HDR}450000''00''0120''10feffff''01 > "$out/fse_bad_counts.zst"

# After a 100-byte raw block: 127 sequences (RLE tables, one offset bit
# each) in a stream of no bits.
{ hex ${HDR}200300; head -c 100 /dev/zero
  hex 3d0000''00''7f54''000100''01; } > "$out/seq_count_too_large.zst"

# One sequence whose match (length code 52, 16 extra bits: 65539 bytes)
# runs past the 1 KiB block limit.
hex ${HDR}4d0000''00''0154''000034''000001 > "$out/seq_past_block.zst"

# Two 1 KiB raw blocks, then a match 1500 bytes back: inside the frame's
# output, but beyond its 1 KiB window. (Offset code 10 with extra bits 479:
# offset value 1503.)
{ hex ${HDR}002000; head -c 1024 /dev/zero
  hex 002000; head -c 1024 /dev/zero
  hex 450000''00''0154''000a00''df05; } > "$out/offset_beyond_window.zst"
