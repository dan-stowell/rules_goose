// goosezstd: a Zstandard decompressor (RFC 8878) in pure Goose.
//
//   goosezstd -d IN [-o OUT]   decompress IN (- for stdin) to OUT or stdout
//   goosezstd -t IN            decompress and check, writing nothing
//
// Frames, skippable frames, raw/RLE/compressed blocks, Huffman literals,
// FSE sequences with repeat offsets, and the XXH64 content checksum. No
// dictionaries. The whole input and output are held in memory; the output
// buffer doubles as the match window.
import std;
import os;
import zstd.frame;

fn usage() {
    write_stderr("""
        usage: goosezstd -d IN [-o OUT]   decompress IN (- for stdin) to OUT (default stdout)
               goosezstd -t IN            test that IN decompresses
        """);
    exit(2);
}

fn main() {
    let a = args();
    var mode = 0;                       // 1: -d, 2: -t
    var input: const u8[:] = "";
    var output: const u8[:] = "";
    var have_in = false;
    var have_out = false;
    var i = 1;
    while i < a.len {
        let s = a[i];
        if s == "-d" {
            mode = 1;
        } else if s == "-t" {
            mode = 2;
        } else if s == "-o" {
            i++;
            if i >= a.len { usage(); }
            output = a[i];
            have_out = true;
        } else if s.len > 1 && s[0] == '-' {
            usage();
        } else {
            if have_in { usage(); }
            input = s;
            have_in = true;
        }
        i++;
    }
    if mode == 0 || !have_in { usage(); }

    var src: u8[>..] = [];
    if input == "-" {
        read_stdin(src);
    } else if !read_file(input, src) {
        write_stderr(str("goosezstd: cannot read ", input, "\n"));
        exit(1);
    }
    var out: u8[>..] = [];
    let err = zstd_decompress(src, out);
    if err.len > 0 {
        write_stderr(str("goosezstd: ", input, ": ", err, "\n"));
        exit(1);
    }
    if mode == 2 {
        write_stderr(str(input, ": OK (", src.len, " -> ", out.len, " bytes)\n"));
        return;
    }
    if have_out {
        if !write_file(output, out) {
            write_stderr(str("goosezstd: cannot write ", output, "\n"));
            exit(1);
        }
    } else {
        write_stdout(out);
        flush_stdout();
    }
}
