// Searching one file: which lines match, and how they are printed.

import std;
import os;
import regex;

namespace search;

struct Options {
    ignore_case: bool,          // -i
    fixed: bool,                // -F: the pattern is a literal string
    count: bool,                // -c: one count per file
    files_only: bool,           // -l: the names of the files that match
    invert: bool,               // -v: select the lines that do not match
    word: bool,                 // -w: a match must be a whole word
    line_numbers: bool,         // -n, or the default when searching many files
    with_filename: bool,        // the default when searching many files
}

fn is_word_byte(c: u8) -> bool {
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'
}

// Appends `s` to `out` as a regex that matches it literally: every ASCII
// punctuation byte gets a backslash, which the engine reads as that byte.
fn escape(out: u8[>..]&, s: u8[:]) {
    for c in s {
        if c >= 0x21 && c < 0x7f && !is_word_byte(c) { out.push('\\'); }
        out.push(c);
    }
}

// The regex the options make of a pattern. The engine has no anchors or
// \b, so -w is checked by `matches` instead.
fn build_pattern(out: u8[>..]&, pattern: u8[:], o: Options) {
    if o.ignore_case { out.append("(?i)"); }
    if o.fixed { escape(out, pattern); } else { out.append(pattern); }
}

// Whether `line` holds a match (a whole-word one, for -w). For -w a match
// that touches a word byte on either side does not count, and the search
// goes on from the byte after where that match started.
fn matches(re: regex::Regex&, line: u8[:], word: bool) -> bool {
    if !word { return regex::matches(re, line); }
    var pos = 0;
    while pos <= line.len {
        let s, e = regex::find(re, line[pos..]);
        if s < 0 { return false; }
        let a = pos + s;
        let b = pos + e;
        let left = a == 0 || !is_word_byte(line[a - 1]);
        let right = b == line.len || !is_word_byte(line[b]);
        if left && right { return true; }
        pos = a + 1;
    }
    return false;
}

// Whether the text looks binary: rg's test, a NUL byte.
fn is_binary(text: u8[:]) -> bool { position(text, 0) >= 0 }

// Searches `text`, the contents of the file `path`, appending the selected
// lines to `out` as `path:line:text` (each part as the options ask), unless
// the options ask for a count or file names only. Returns how many lines it
// selected; for -l it stops at the first.
fn search_text(re: regex::Regex&, o: Options, path: u8[:], text: u8[:], out: u8[>..]&) -> i64 {
    let print_lines = !o.count && !o.files_only;
    var selected = 0;
    var lineno = 0;
    var i = 0;
    while i < text.len {
        let k = position(text[i..], '\n');
        let end = if k < 0 { text.len } else { i + k };
        let line = text[i..end];
        lineno++;
        i = end + 1;
        guard matches(re, line, o.word) != o.invert else { continue; }
        selected++;
        if o.files_only { break; }
        if print_lines {
            if o.with_filename { format(out, path, ":"); }
            if o.line_numbers { format(out, lineno, ":"); }
            out.append(line);
            out.push('\n');
        }
    }
    return selected;
}

// Reads and searches one file. Returns the number of selected lines, and
// false if the file could not be read. A binary file is skipped: 0, true.
fn search_file(re: regex::Regex&, o: Options, path: u8[:], out: u8[>..]&) -> i64, bool {
    var text: u8[>..] = [];
    guard read_file(path, text) else { return 0, false; }
    if is_binary(text) { return 0, true; }
    return search_text(re, o, path, text, out), true;
}
