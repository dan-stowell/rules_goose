// goosezstd: a Zstandard decompressor (RFC 8878) in pure Goose.
//
//   goosezstd -d IN [-o OUT]   decompress IN (- for stdin) to OUT or stdout
//   goosezstd -t IN            decompress and check, writing nothing
//
// Frames, skippable frames, raw/RLE/compressed blocks, Huffman literals,
// FSE sequences with repeat offsets, and the XXH64 content checksum. No
// dictionaries. The whole input and output are held in memory; the output
// buffer doubles as the match window.
//
//   zstd/bits.goose      forward and backward bit readers
//   zstd/fse.goose       FSE table descriptions and decoding tables
//   zstd/huffman.goose   Huffman tree descriptions and literal streams
//   zstd/blocks.goose    literals and sequences sections, match copying
//   zstd/xxhash.goose    XXH64, for the content checksum
//   zstd/frame.goose     frames and blocks: zstd_decompress
import cli;
import zstd.frame;

fn main() { run_cli(zstd_decompress); }
