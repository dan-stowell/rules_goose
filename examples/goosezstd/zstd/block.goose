// Compressed blocks (RFC 8878 section 3.1.1.3): a literals section, then a
// sequences section that interleaves those literals with matches copied
// from earlier output.
import std;
import zstd.bits;
import zstd.fse;
import zstd.huffman;

let BLOCK_MAX = 131072;

// What a frame's blocks hand on to the next block: repeat offsets, the last
// Huffman tree (for treeless literals) and the last sequence tables (for
// repeat mode).
struct FrameState {
    reps: i64[3],
    huf_ok: bool,
    ll_ok: bool,
    of_ok: bool,
    ml_ok: bool,
    huf: HufTable,
    ll: FseTable,
    of: FseTable,
    ml: FseTable,
}

fn new_frame_state() -> FrameState { FrameState { reps: [1, 4, 8], .. } }

// ---- Literals ------------------------------------------------------------

// Decodes the literals section at the front of src into lits. Returns the
// number of bytes the section took.
fn decode_literals(src: const u8[:], st: FrameState&, lits: u8[>..]&) -> i64 {
    if src.len == 0 { corrupt("missing literals section"); }
    let b0: i64 = src[0];
    let kind = b0 & 3;
    let sf = (b0 >> 2) & 3;
    if kind < 2 {
        // Raw or RLE: a 1, 2 or 3 byte header holding the size.
        var hsize = 1;
        var regen = b0 >> 3;
        if sf == 1 {
            hsize = 2;
            regen = (load_le(src, 0, 2) >> 4) as i64;
        } else if sf == 3 {
            hsize = 3;
            regen = (load_le(src, 0, 3) >> 4) as i64;
        }
        if regen > BLOCK_MAX { corrupt("literals too large"); }
        if kind == 0 {
            if hsize + regen > src.len { corrupt("truncated raw literals"); }
            lits.append(src[hsize..hsize + regen]);
            return hsize + regen;
        }
        if hsize + 1 > src.len { corrupt("truncated RLE literals"); }
        lits.resize(regen, src[hsize]);
        return hsize + 1;
    }

    // Huffman-compressed (kind 2) or treeless (kind 3, reusing the last tree).
    let hsize = match sf { 0, 1 => 3, 2 => 4, _ => 5 };
    if hsize > src.len { corrupt("truncated literals header"); }
    let v = load_le(src, 0, hsize);
    let bits = match hsize { 3 => 10, 4 => 14, _ => 18 };
    let regen = ((v >> 4) & mask(bits)) as i64;
    let csize = ((v >> (4 + bits)) & mask(bits)) as i64;
    if regen > BLOCK_MAX { corrupt("literals too large"); }
    if hsize + csize > src.len { corrupt("truncated compressed literals"); }
    var data = src[hsize..hsize + csize];
    if kind == 2 {
        let used = huf_read_table(st.huf, data);
        st.huf_ok = true;
        data = data[used..];
    } else if !st.huf_ok {
        corrupt("treeless literals without an earlier tree");
    }
    if sf == 0 {
        huf_decode_stream(st.huf, data, lits, regen);
    } else {
        // Four streams, after a jump table of the first three sizes.
        if data.len < 6 { corrupt("truncated jump table"); }
        let s1 = load_le(data, 0, 2) as i64;
        let s2 = load_le(data, 2, 2) as i64;
        let s3 = load_le(data, 4, 2) as i64;
        let a = 6 + s1;
        let b = a + s2;
        let c = b + s3;
        if c > data.len { corrupt("bad jump table"); }
        let seg = (regen + 3) / 4;
        let last = regen - 3 * seg;
        if last < 0 { corrupt("too few literals for four streams"); }
        huf_decode_stream(st.huf, data[6..a], lits, seg);
        huf_decode_stream(st.huf, data[a..b], lits, seg);
        huf_decode_stream(st.huf, data[b..c], lits, seg);
        huf_decode_stream(st.huf, data[c..], lits, last);
    }
    return hsize + csize;
}

// ---- Sequences -----------------------------------------------------------

// Literal-length and match-length codes: a baseline plus extra bits.
let LL_BASE: i64[36] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512, 1024, 2048, 4096,
    8192, 16384, 32768, 65536];
let LL_BITS: i64[36] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
let ML_BASE: i64[53] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
    18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 37,
    39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027, 2051, 4099, 8195,
    16387, 32771, 65539];
let ML_BITS: i64[53] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5,
    7, 8, 9, 10, 11, 12, 13, 14, 15, 16];

// The predefined distributions (RFC 8878 3.1.1.3.2.2).
let LL_DEFAULT: i16[36] = [4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 1, 1, 1, 1, -1, -1, -1, -1];
let ML_DEFAULT: i16[53] = [1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, -1, -1, -1, -1, -1, -1, -1];
let OF_DEFAULT: i16[29] = [1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1];

fn predefined(norm: const i16[:], log: i64) -> FseTable {
    var t = FseTable { log: 0, .. };
    fse_build(t, norm, log);
    return t;
}

let LL_PREDEF = predefined(LL_DEFAULT, 6);
let ML_PREDEF = predefined(ML_DEFAULT, 6);
let OF_PREDEF = predefined(OF_DEFAULT, 5);

// Sets up one of the three tables for a block, per its compression mode.
// Returns the bytes its description took.
fn read_seq_table(t: FseTable&, ok: bool&, mode: i64, src: const u8[:],
                  predef: const FseTable&, max_log: i64, max_sym: i64) -> i64 {
    if mode == 0 {
        t = predef;
        ok = true;
        return 0;
    }
    if mode == 1 {
        if src.len == 0 { corrupt("missing RLE symbol"); }
        if src[0] > max_sym { corrupt("bad RLE symbol"); }
        fse_rle(t, src[0]);
        ok = true;
        return 1;
    }
    if mode == 2 {
        let used = fse_read_table(t, src, max_log, max_sym);
        ok = true;
        return used;
    }
    if !ok { corrupt("repeat mode without an earlier table"); }
    return 0;
}

// Decodes the sequences section in src and executes it: literals from lits
// and matches from earlier output, appended to out. A match may reach back
// to frame_start, where this frame's output began, and no further.
fn decode_sequences(src: const u8[:], st: FrameState&, lits: const u8[:],
                    out: u8[>..]&, frame_start: i64) {
    if src.len == 0 { corrupt("missing sequences section"); }
    let b0: i64 = src[0];
    var nseq = 0;
    var p = 1;
    if b0 < 128 {
        nseq = b0;
    } else if b0 < 255 {
        if src.len < 2 { corrupt("truncated sequence count"); }
        nseq = ((b0 - 128) << 8) + src[1];
        p = 2;
    } else {
        if src.len < 3 { corrupt("truncated sequence count"); }
        nseq = src[1] + (src[2] as i64 << 8) + 0x7F00;
        p = 3;
    }
    if nseq == 0 {
        if p != src.len { corrupt("data after an empty sequences section"); }
        out.append(lits);
        return;
    }
    if p >= src.len { corrupt("missing compression modes"); }
    let modes: i64 = src[p];
    p++;
    if modes & 3 != 0 { corrupt("reserved compression mode bits set"); }
    p += read_seq_table(st.ll, st.ll_ok, (modes >> 6) & 3, src[p..], LL_PREDEF, 9, 35);
    if p > src.len { corrupt("truncated sequence tables"); }
    p += read_seq_table(st.of, st.of_ok, (modes >> 4) & 3, src[p..], OF_PREDEF, 8, 31);
    if p > src.len { corrupt("truncated sequence tables"); }
    p += read_seq_table(st.ml, st.ml_ok, (modes >> 2) & 3, src[p..], ML_PREDEF, 9, 52);
    if p > src.len { corrupt("truncated sequence tables"); }

    var b, ok = back_bits(src[p..]);
    if !ok { corrupt("bad sequence stream"); }
    let ll_t .= st.ll;
    let of_t .= st.of;
    let ml_t .= st.ml;
    var sll = fse_init(ll_t, b);
    var sof = fse_init(of_t, b);
    var sml = fse_init(ml_t, b);
    var r0 = st.reps[0];
    var r1 = st.reps[1];
    var r2 = st.reps[2];
    var lp = 0;
    let block_start = out.len;
    for i in nseq {
        let ofc: i64 = fse_sym(of_t, sof);
        let mlc: i64 = fse_sym(ml_t, sml);
        let llc: i64 = fse_sym(ll_t, sll);
        // Extra bits come in the order offset, match length, literal length.
        let ofv = ((1 as u64) << ofc) as! i64 + back_read(b, ofc) as! i64;
        let ml = ML_BASE[mlc % 53] + back_read(b, ML_BITS[mlc % 53]) as! i64;
        let ll = LL_BASE[llc % 36] + back_read(b, LL_BITS[llc % 36]) as! i64;

        // Offset values 1-3 name a repeat offset; with no literals before
        // the match, they shift by one (and 3 means "the last one, minus 1").
        var off = 0;
        if ofv > 3 {
            off = ofv - 3;
            r2 = r1;
            r1 = r0;
            r0 = off;
        } else {
            let idx = if ll == 0 { ofv } else { ofv - 1 };
            if idx == 0 {
                off = r0;
            } else {
                off = if idx == 1 { r1 } else if idx == 2 { r2 } else { r0 - 1 };
                if off == 0 { corrupt("zero offset"); }
                if idx > 1 { r2 = r1; }
                r1 = r0;
                r0 = off;
            }
        }

        if i + 1 < nseq {
            // States update in the order literal length, match length, offset.
            sll = fse_next(ll_t, b, sll);
            sml = fse_next(ml_t, b, sml);
            sof = fse_next(of_t, b, sof);
        }

        if lp + ll > lits.len { corrupt("sequence needs more literals than there are"); }
        out.append(lits[lp..lp + ll]);
        lp += ll;
        if off > out.len - frame_start { corrupt("match offset before the start of the frame"); }
        copy_match(out, off, ml);
    }
    if b.pos != 0 { corrupt("sequence stream size mismatch"); }
    out.append(lits[lp..]);
    if out.len - block_start > BLOCK_MAX { corrupt("block too large"); }
    st.reps = [r0, r1, r2];
}

// Appends `len` bytes copied from `off` bytes back. The source may overlap
// what is being written (off < len), which repeats the last off bytes.
fn copy_match(out: u8[>..]&, off: i64, len: i64) {
    let from = out.len - off;
    if off >= len {
        out.append(out[from..from + len]);
    } else {
        for k in len { out.push(out[from + k]); }
    }
}

// Decodes one compressed block, appending its content to out. lits is the
// caller's scratch buffer for the literals.
fn decode_block(src: const u8[:], st: FrameState&, lits: u8[>..]&, out: u8[>..]&, frame_start: i64) {
    lits.clear();
    let used = decode_literals(src, st, lits);
    decode_sequences(src[used..], st, lits, out, frame_start);
}
