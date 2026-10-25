// goosezstd: a Zstandard decompressor (RFC 8878) in pure Goose. See
// README.md for what it supports and how the files fit together.
import cli;
import zstd.frame;

fn main() { run_cli(zstd_decompress); }
