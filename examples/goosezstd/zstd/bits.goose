// Bit readers for Zstandard (RFC 8878 section 4.1).
//
// Two directions: FSE table descriptions are read forward, least significant
// bit first; entropy-coded streams (Huffman literals, FSE weights, sequences)
// are read backward, from the end marker in their last byte towards their
// first byte. Both work on a slice of the input with a bit position, and a
// read is one 8-byte little-endian load, a shift and a mask.
import std;

// The n low bits set (n < 64).
fn mask(n: i64) -> u64 { ((1 as u64) << n) - 1 }

// The index of the highest set bit of x (x != 0).
fn highbit(x: u64) -> i64 { 63 - clz(x) }

// Little-endian load of the 8 bytes at src[at..at + 8]; bytes outside src
// read as zero.
fn load_le64(src: const u8[:], at: i64) -> u64 {
    if at >= 0 && at + 8 <= src.len {
        // One bounds check for the slice, none for the bytes.
        let w = src[at..at + 8];
        assert(w.len == 8);
        return w[0] | (w[1] as u64 << 8) | (w[2] as u64 << 16) |
               (w[3] as u64 << 24) | (w[4] as u64 << 32) |
               (w[5] as u64 << 40) | (w[6] as u64 << 48) |
               (w[7] as u64 << 56);
    }
    var v: u64 = 0;
    for k in 8 {
        let i = at + k;
        if i >= 0 && i < src.len { v |= src[i] as u64 << (8 * k); }
    }
    return v;
}

// A little-endian integer of `size` bytes (at most 8) at src[at..].
fn load_le(src: const u8[:], at: i64, size: i64) -> u64 {
    if size == 0 { return 0; }
    let v = load_le64(src, at);
    if size >= 8 { return v; }
    return v & mask(size * 8);
}

// ---- Forward, LSB first ---------------------------------------------------

struct FwdBits { src: const u8[:], pos: i64 }   // pos: bits consumed

fn fwd_peek(r: FwdBits&, n: i64) -> u64 {
    (load_le64(r.src, r.pos >> 3) >> (r.pos & 7)) & mask(n)
}

fn fwd_read(r: FwdBits&, n: i64) -> u64 {
    let v = fwd_peek(r, n);
    r.pos += n;
    return v;
}

// ---- Backward -------------------------------------------------------------

// pos counts the bits not yet read: the next read of n bits returns bits
// [pos - n, pos) of the stream. Reading past the start makes pos negative;
// the missing bits read as zero, and callers check pos to detect it.
struct BackBits { src: const u8[:], pos: i64 }

// Starts a backward stream: its last byte holds a 1 bit marking the end,
// above which everything is padding. False if there is no marker.
fn back_bits(src: const u8[:]) -> BackBits, bool {
    if src.len == 0 { return BackBits { src: src, pos: 0 }, false; }
    let last = src[src.len - 1];
    if last == 0 { return BackBits { src: src, pos: 0 }, false; }
    return BackBits { src: src, pos: (src.len - 1) * 8 + highbit(last) }, true;
}

fn back_peek(b: BackBits&, n: i64) -> u64 {
    let p = b.pos - n;
    if p >= 0 { return (load_le64(b.src, p >> 3) >> (p & 7)) & mask(n); }
    if p + n <= 0 { return 0; }
    return (load_le64(b.src, 0) << -p) & mask(n);
}

fn back_read(b: BackBits&, n: i64) -> u64 {
    let v = back_peek(b, n);
    b.pos -= n;
    return v;
}
