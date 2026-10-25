// The command line shared by goosezstd and libzstd_demo:
//
//   PROG -d IN [-o OUT]   decompress IN (- for stdin) to OUT (default stdout)
//   PROG -t IN            decompress and check, writing nothing
//
// Each program passes its decoder as a compile-time function value:
// Decode(src, out) appends the content to out and returns an error
// message, empty on success.
import std;
import os;

fn usage(prog: const u8[:]) {
    write_stderr(str("usage: ", prog, " -d IN [-o OUT]   decompress IN (- for stdin) to OUT (default stdout)\n",
                     "       ", prog, " -t IN            test that IN decompresses\n"));
    exit(2);
}

fn run_cli<Decode>() {
    let a = args();
    let prog = if a.len > 0 { a[0] } else { "goosezstd" };
    var mode = 0;                       // 1: -d, 2: -t
    var input: const u8[:] = "";
    var output: const u8[:] = "";
    var i = 1;
    while i < a.len {
        let s = a[i];
        if s == "-d" {
            mode = 1;
        } else if s == "-t" {
            mode = 2;
        } else if s == "-o" {
            i++;
            if i >= a.len { usage(prog); }
            output = a[i];
        } else if s.len > 1 && s[0] == '-' {
            usage(prog);
        } else {
            if input.len > 0 { usage(prog); }
            input = s;
        }
        i++;
    }
    if mode == 0 || input.len == 0 { usage(prog); }

    var src: u8[>..] = [];
    if input == "-" {
        read_stdin(src);
    } else if !read_file(input, src) {
        write_stderr(str(prog, ": cannot read ", input, "\n"));
        exit(1);
    }
    var out: u8[>..] = [];
    let err = Decode(src, out);
    if err.len > 0 {
        write_stderr(str(prog, ": ", input, ": ", err, "\n"));
        exit(1);
    }
    if mode == 2 {
        write_stderr(str(input, ": OK (", src.len, " -> ", out.len, " bytes)\n"));
        return;
    }
    if output.len > 0 {
        if !write_file(output, out) {
            write_stderr(str(prog, ": cannot write ", output, "\n"));
            exit(1);
        }
    } else {
        write_stdout(out);
        flush_stdout();
    }
}
