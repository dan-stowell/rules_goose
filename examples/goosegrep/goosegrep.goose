// goosegrep: a small ripgrep in Goose.
//
//   goosegrep [flags] PATTERN [PATH...]
//
// Searches the files under each PATH (the current directory by default) for
// lines matching PATTERN, a regex in the syntax of Rust's regex crate (no
// anchors or \b). Directories are walked recursively; hidden files and
// directories, and binary files (those with a NUL byte), are skipped. Files
// are searched in path order, so the output is the same on every run.
//
// Exit status: 0 if a line was selected, 1 if none was, 2 on an error.

import std;
import os;
import regex;
import walk;
import search;

let USAGE = """
    usage: goosegrep [flags] PATTERN [PATH...]
      -i, --ignore-case         match letters of either case
      -F, --fixed-strings       PATTERN is a literal string, not a regex
      -w, --word-regexp         only match whole words
      -v, --invert-match        select the lines that do not match
      -c, --count               print the number of selected lines per file
      -l, --files-with-matches  print only the names of files with a selected line
      -n, --line-number         print line numbers (the default for many files)
      -N, --no-line-number      do not print line numbers
      -h, --help                print this help

    """;

fn usage_error(what: u8[:]) {
    write_stderr(str("goosegrep: ", what, "\n", USAGE));
    exit(2);
}

// Sets the option a short flag letter names; false if there is none.
fn short_flag(o: search::Options&, numbers: i64&, c: u8) -> bool {
    match c {
        'i' => { o.ignore_case = true; },
        'F' => { o.fixed = true; },
        'w' => { o.word = true; },
        'v' => { o.invert = true; },
        'c' => { o.count = true; },
        'l' => { o.files_only = true; },
        'n' => { numbers = 1; },
        'N' => { numbers = -1; },
        _ => { return false; },
    }
    return true;
}

// The short flag a long one stands for, or 0.
fn long_flag(name: u8[:]) -> u8 {
    if name == "ignore-case" { return 'i'; }
    if name == "fixed-strings" { return 'F'; }
    if name == "word-regexp" { return 'w'; }
    if name == "invert-match" { return 'v'; }
    if name == "count" { return 'c'; }
    if name == "files-with-matches" { return 'l'; }
    if name == "line-number" { return 'n'; }
    if name == "no-line-number" { return 'N'; }
    return 0;
}

fn main() {
    let argv = args();
    var o = search::Options { .. };
    var numbers = 0;                    // -n: 1, -N: -1, neither: 0
    var pattern: u8[>..] = [];
    var have_pattern = false;
    var paths: u8[:][>..] = [];
    var flags_done = false;
    for i in 1..argv.len {
        let a = argv[i];
        if !flags_done && a.len > 1 && a[0] == '-' {
            if a == "--" { flags_done = true; continue; }
            if a == "-h" || a == "--help" { write_stdout(USAGE); exit(0); }
            if a[1] == '-' {
                let c = long_flag(a[2..]);
                if c == 0 || !short_flag(o, numbers, c) { usage_error(str("unknown flag ", a)); }
            } else {
                for c in a[1..] {
                    if !short_flag(o, numbers, c) { usage_error(str("unknown flag -", a[1..])); }
                }
            }
            continue;
        }
        if have_pattern { paths.push(a); } else { pattern.append(a); have_pattern = true; }
    }
    if !have_pattern { usage_error("no pattern given"); }

    var source: u8[>..] = [];
    search::build_pattern(source, pattern, o);
    var err: u8[>..] = [];
    // The pattern must parse on its own too: -w's wrapping could make a
    // malformed one, ")|x|(?:", well-formed.
    if o.word && !o.fixed { regex::compile(pattern, err); }
    let re = regex::compile(source, err);
    if err.len > 0 {
        write_stderr(str("goosegrep: bad pattern: ", err, "\n"));
        exit(2);
    }

    // Every file to search, as spans of `text`.
    var text: u8[>..] = [];
    var files: walk::Span[>..] = [];
    var errors = false;
    var many = paths.len > 1;
    if paths.len == 0 {
        many = true;
        if !walk::collect(text, files, walk::Span { start: 0, end: 0 }) { errors = true; }
    }
    for p in paths {
        let start = text.len;
        text.append(p);
        let span = walk::Span { start: start, end: text.len };
        if is_dir(p) {
            many = true;
            if !walk::collect(text, files, span) { errors = true; }
        } else if file_exists(p) {
            files.push(span);
        } else {
            walk::warn(p, "No such file or directory");
            errors = true;
        }
    }
    sort(files) { a, b => compare(text[a.start..a.end], text[b.start..b.end]) < 0 };

    o.with_filename = many;
    o.line_numbers = numbers > 0 || (numbers == 0 && many);
    var matched = false;
    for f in files {
        let path = text[f.start..f.end];
        var out: u8[>..] = [];
        let n, ok = search::search_file(re, o, path, out);
        if !ok {
            walk::warn(path, "cannot read file");
            errors = true;
            continue;
        }
        if n == 0 { continue; }
        matched = true;
        if o.files_only {
            format(out, path, "\n");
        } else if o.count {
            if many { format(out, path, ":"); }
            format(out, n, "\n");
        }
        write_stdout(out);
    }
    if errors { exit(2); }
    exit(if matched { 0 } else { 1 });
}
