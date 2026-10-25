// Unit tests for the search module: pattern building, -w, binary detection
// and the output format. A goose_test passes when it exits 0.
import std;
import regex;
import search;

fn compiled(pattern: u8[:], o: search::Options) -> regex::Regex {
    var source: u8[>..] = [];
    search::build_pattern(source, pattern, o);
    return regex::compile(source);
}

fn main() {
    // -F: punctuation is escaped, letters, digits, '_' and spaces are not.
    var esc: u8[>..] = [];
    search::escape(esc, "a.b (c)* d_1");
    assert(esc == "a\\.b \\(c\\)\\* d_1");

    let plain = search::Options { .. };
    let fixed = search::Options { fixed: true, .. };
    let dot = compiled("a.c", plain);
    assert(search::matches(dot, "xabcx", false));
    let lit = compiled("a.c", fixed);
    assert(!search::matches(lit, "xabcx", false));
    assert(search::matches(lit, "xa.cx", false));

    // -i.
    let fold = compiled("goose", search::Options { ignore_case: true, .. });
    assert(search::matches(fold, "A GoOsE", false));

    // -w: a match touching a word byte does not count, and the search goes on.
    let goose = compiled("goose", plain);
    assert(search::matches(goose, "mongoose", false));
    assert(!search::matches(goose, "mongoose", true));
    assert(!search::matches(goose, "gooses", true));
    assert(search::matches(goose, "goose", true));
    assert(search::matches(goose, "mongoose, goose!", true));
    assert(search::matches(goose, "(goose)", true));

    // Binary files have a NUL byte.
    let bin: u8[3] = ['a', 0, 'b'];
    assert(search::is_binary(bin));
    assert(!search::is_binary("text\n"));

    // Output: path:line:text for many files, and a final line without '\n'.
    var out: u8[>..] = [];
    let many = search::Options { line_numbers: true, with_filename: true, .. };
    let n = search::search_text(goose, many, "f.txt", "a goose\nno\nmongoose", out);
    assert(n == 2);
    assert(out == "f.txt:1:a goose\nf.txt:3:mongoose\n");

    // -v selects the others; -c prints nothing itself; -l stops at the first.
    var inv: u8[>..] = [];
    assert(search::search_text(goose, search::Options { invert: true, .. }, "f", "goose\nduck\n", inv) == 1);
    assert(inv == "duck\n");
    var none: u8[>..] = [];
    assert(search::search_text(goose, search::Options { count: true, .. }, "f", "goose\ngoose\n", none) == 2);
    assert(search::search_text(goose, search::Options { files_only: true, .. }, "f", "goose\ngoose\n", none) == 1);
    assert(none.len == 0);
    print("ok");
}
