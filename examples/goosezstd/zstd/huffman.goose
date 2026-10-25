// Huffman-coded literals (RFC 8878 section 4.2).
//
// The tree is sent as a list of weights, one per symbol, the last one
// implied. Decoding uses a flat table indexed by the next maxbits bits of
// the stream: every code of n bits owns 2^(maxbits - n) consecutive slots.
import std;
import zstd.bits;
import zstd.fse;

struct HufEntry { sym: u8, nbits: u8 }

let HUF_MAX_BITS = 11;

struct HufTable { maxbits: i64, t: HufEntry[2048] }

// Reads a Huffman tree description from the front of src into h. Returns
// the number of bytes it took.
fn huf_read_table(h: HufTable&, src: const u8[:]) -> i64 {
    if src.len == 0 { corrupt("missing Huffman tree description"); }
    var w: u8[256] = [0; 256];
    var n = 0;
    let hb: i64 = src[0];
    var used = 0;
    if hb >= 128 {
        // Weights stored directly, 4 bits each, high nibble first.
        n = hb - 127;
        used = 1 + (n + 1) / 2;
        if used > src.len { corrupt("truncated Huffman weights"); }
        for i in n {
            let b = src[1 + i / 2];
            w[i & 255] = if i % 2 == 0 { b >> 4 } else { b & 15 };
        }
    } else {
        // Weights compressed with FSE: two interleaved states share one
        // backward stream, which ends when a read runs past its start.
        used = 1 + hb;
        if used > src.len { corrupt("truncated Huffman weights"); }
        let ws = src[1..used];
        var ft = FseTable { log: 0, .. };
        let tsz = fse_read_table(ft, ws, 6, 255);
        if tsz > ws.len { corrupt("bad Huffman weight table"); }
        var b, ok = back_bits(ws[tsz..]);
        if !ok { corrupt("bad Huffman weight stream"); }
        var s1 = fse_init(ft, b);
        var s2 = fse_init(ft, b);
        loop {
            if n >= 254 { corrupt("too many Huffman weights"); }
            w[n & 255] = fse_sym(ft, s1);
            n++;
            s1 = fse_next(ft, b, s1);
            if b.pos < 0 { w[n & 255] = fse_sym(ft, s2); n++; break; }
            w[n & 255] = fse_sym(ft, s2);
            n++;
            s2 = fse_next(ft, b, s2);
            if b.pos < 0 { w[n & 255] = fse_sym(ft, s1); n++; break; }
        }
    }

    // The implied last weight brings the total to a power of two.
    var sum = 0;
    for i in n {
        let wi: i64 = w[i & 255];
        if wi > HUF_MAX_BITS { corrupt("Huffman weight too large"); }
        if wi > 0 { sum += 1 << (wi - 1); }
    }
    if sum == 0 { corrupt("empty Huffman tree"); }
    let maxbits = highbit(sum as u64) + 1;
    if maxbits > HUF_MAX_BITS { corrupt("Huffman code too long"); }
    let rest = (1 << maxbits) - sum;
    if rest & (rest - 1) != 0 { corrupt("Huffman weights do not complete a tree"); }
    if n >= 256 { corrupt("too many Huffman weights"); }
    w[n & 255] = (highbit(rest as u64) + 1) as! u8;
    n++;

    // Codes go to the smallest weights first, and within a weight in
    // symbol order: so each weight's slots form one run.
    var count: i64[16] = [0; 16];
    for i in n { count[w[i & 255] & 15] += 1; }
    var start: i64[16] = [0; 16];
    var at = 0;
    for wt in 1..maxbits + 1 {
        start[wt & 15] = at;
        at += count[wt & 15] << (wt - 1);
    }
    for s in n {
        let wt: i64 = w[s & 255];
        if wt == 0 { continue; }
        let len = 1 << (wt - 1);
        let e = HufEntry { sym: s as! u8, nbits: (maxbits + 1 - wt) as! u8 };
        let from = start[wt & 15];
        for k in len { h.t[(from + k) & 2047] = e; }
        start[wt & 15] = from + len;
    }
    h.maxbits = maxbits;
    return used;
}

// Decodes `count` literals from one backward stream, appending them to out.
fn huf_decode_stream(h: const HufTable&, src: const u8[:], out: u8[>..]&, count: i64) {
    var b, ok = back_bits(src);
    if !ok { corrupt("bad Huffman stream"); }
    let mb = h.maxbits;
    for i in count {
        let e = h.t[(back_peek(b, mb) as! i64) & 2047];
        out.push(e.sym);
        b.pos -= e.nbits;
    }
    if b.pos != 0 { corrupt("Huffman stream size mismatch"); }
}
