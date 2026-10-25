// The same command line as goosezstd, with the real libzstd behind it:
// a demo of `extern fn` and cc_deps. libzstd_shim.h adapts libzstd's
// streaming API to what can cross the boundary (slices and a builder).
import std;
import cli;

extern fn c_zstd_decompress(src: const u8[:], out: u8[>..]&, err: u8[>..]&) -> i32;

fn libzstd_decompress(src: const u8[:], out: u8[>..]&) -> u8[>..] {
    var err: u8[>..] = [];
    if c_zstd_decompress(src, out, err) != 0 { return []; }
    return copy(err);
}

fn main() { run_cli(libzstd_decompress); }
