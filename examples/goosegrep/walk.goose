// Finding the files to search: a recursive directory walk that skips hidden
// entries, and, as rg does without -L, symlinks and anything else that is
// not a regular file or a directory (FIFOs, sockets, devices). Every path lives in one text buffer the caller owns, and the walk
// hands back spans into it, so the list of files is an array of fixed-size
// values that sorts without moving any text.

import std;
import os;

namespace walk;

// From dir_shim.h: appends each entry of `dir` as a type byte ('d', 'f' or
// 'o'), its name and a NUL; 0 if the directory could not be read.
extern fn c_list_dir(dir: const u8[:], out: u8[>..]&) -> i32;

// Where a path sits in the text buffer: text[start..end].
struct Span { start: i64, end: i64 }

fn is_hidden(name: u8[:]) -> bool { name.len > 0 && name[0] == '.' }

// Appends dir/name to out. An empty dir is the current directory, whose
// files are named without a "./" in front, as rg names them.
fn join_path(out: u8[>..]&, dir: u8[:], name: u8[:]) {
    if dir.len > 0 {
        out.append(dir);
        if dir[dir.len - 1] != '/' { out.push('/'); }
    }
    out.append(name);
}

fn warn(path: u8[:], what: u8[:]) {
    write_stderr(str("goosegrep: ", path, ": ", what, "\n"));
}

// Walks the directory text[root.start..root.end] (the current directory if
// the span is empty), appending every non-hidden file below it to `files`
// and its path to `text`, in path order. The walk keeps its own stack of directories rather
// than recursing. Returns false if some directory could not be read.
fn collect(text: u8[>..]&, files: Span[>..]&, root: Span) -> bool {
    let first = files.len;
    var ok = true;
    var pending: Span[>..<] = [];
    pending.push(root);
    while pending.len > 0 {
        let d = pending.pop();
        var dir: u8[>..] = [];
        dir.append(text[d.start..d.end]);
        var listing: u8[>..] = [];
        let where = if dir.len > 0 { dir[..] } else { "." };
        guard c_list_dir(where, listing) != 0 else {
            warn(where, "cannot read directory");
            ok = false;
            continue;
        }
        for entry in split(listing, 0) {
            guard entry.len > 1 && entry[0] != 'o' && !is_hidden(entry[1..]) else { continue; }
            let start = text.len;
            join_path(text, dir, entry[1..]);
            let span = Span { start: start, end: text.len };
            if entry[0] == 'd' { pending.push(span); } else { files.push(span); }
        }
    }
    sort(files[first..]) { a, b => compare(text[a.start..a.end], text[b.start..b.end]) < 0 };
    return ok;
}
