// Finite State Entropy tables (RFC 8878 section 4.1).
//
// A decoding table has 2^log states. Each state names a symbol, and says
// how many bits to read and what to add to them to reach the next state.
import std;
import zstd.bits;

struct FseEntry { sym: u8, nbits: u8, base: u16 }

// The largest table zstd uses has accuracy log 9 (literal and match lengths).
let FSE_MAX_STATES = 512;

struct FseTable { log: i64, t: FseEntry[FSE_MAX_STATES] }

// Builds the decoding table for a normalized distribution: norm[s] is the
// probability of symbol s in units of 2^-log, with -1 meaning "less than
// one" (a single state, at the top of the table).
fn fse_build(t: FseTable&, norm: const i16[:], log: i64) {
    let size = 1 << log;
    var high = size - 1;
    var next: i64[256] = [0; 256];
    for s in norm.len {
        let c: i64 = norm[s];
        if c == -1 {
            t.t[high & 511].sym = s as! u8;
            high--;
            next[s & 255] = 1;
        } else {
            next[s & 255] = c;
        }
    }
    // Spread the remaining symbols over the table with a fixed step that is
    // coprime with the table size, skipping the "less than one" states.
    let step = (size >> 1) + (size >> 3) + 3;
    let m = size - 1;
    var pos = 0;
    for s in norm.len {
        let c: i64 = norm[s];
        for i in c {
            t.t[pos & 511].sym = s as! u8;
            pos = (pos + step) & m;
            while pos > high { pos = (pos + step) & m; }
        }
    }
    if pos != 0 { corrupt("FSE distribution does not fill its table"); }
    for u in size {
        let e .= t.t[u & 511];
        let s = e.sym;
        let ns = next[s];
        next[s] = ns + 1;
        let nb = log - highbit(ns as! u64);
        e.nbits = nb as! u8;
        e.base = ((ns << nb) - size) as! u16;
    }
    t.log = log;
}

// A table that always yields `sym` and reads nothing (RLE mode).
fn fse_rle(t: FseTable&, sym: u8) {
    t.log = 0;
    t.t[0] = FseEntry { sym: sym, nbits: 0, base: 0 };
}

// Reads a table description (RFC 8878 4.1.1) from the front of src and
// builds the table. Returns the number of bytes the description took.
fn fse_read_table(t: FseTable&, src: const u8[:], max_log: i64, max_sym: i64) -> i64 {
    if src.len == 0 { corrupt("missing FSE table description"); }
    var r = FwdBits { src: src, pos: 0 };
    let log = fwd_read(r, 4) as i64 + 5;
    if log > max_log { corrupt("FSE accuracy log too large"); }
    var norm: i16[256] = [0; 256];
    var remaining = (1 << log) + 1;
    var threshold = 1 << log;
    var nb = log + 1;
    var sym = 0;
    var prev0 = false;
    while remaining > 1 && sym <= max_sym {
        if prev0 {
            // After a zero probability: 2-bit repeat counts of further zeros,
            // 3 meaning "three more, and another count follows".
            loop {
                let rep = fwd_read(r, 2) as i64;
                sym += rep;
                if rep != 3 { break; }
            }
            if sym > max_sym { break; }
        }
        let maxv = (2 * threshold - 1) - remaining;
        let v = fwd_peek(r, nb) as i64;
        var count = 0;
        if (v & (threshold - 1)) < maxv {
            count = v & (threshold - 1);
            r.pos += nb - 1;
        } else {
            count = v & (2 * threshold - 1);
            if count >= threshold { count -= maxv; }
            r.pos += nb;
        }
        count -= 1;                       // -1: "less than one"
        remaining -= abs(count);
        norm[sym & 255] = count as i16;
        sym++;
        prev0 = count == 0;
        while remaining < threshold { nb--; threshold >>= 1; }
    }
    if remaining != 1 || sym > max_sym + 1 || r.pos > src.len * 8 {
        corrupt("bad FSE table description");
    }
    fse_build(t, norm[..sym], log);
    return (r.pos + 7) >> 3;
}

// Decoding: a state is an index into the table.
fn fse_init(t: const FseTable&, b: BackBits&) -> i64 { back_read(b, t.log) as i64 }

fn fse_sym(t: const FseTable&, state: i64) -> u8 { t.t[state & 511].sym }

fn fse_next(t: const FseTable&, b: BackBits&, state: i64) -> i64 {
    let e = t.t[state & 511];
    return e.base as i64 + back_read(b, e.nbits) as i64;
}
