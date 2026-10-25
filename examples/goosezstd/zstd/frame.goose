// Zstandard frames (RFC 8878 section 3.1): the entry point of the decoder.
//
//   let err = zstd_decompress(compressed, out);   // "" on success
//
// Decoding errors anywhere below use `return ... from zstd_decompress`, so
// the functions in between carry no error plumbing at all.
import std;
import zstd.bits;
import zstd.blocks;
import zstd.xxhash;

let ZSTD_MAGIC: u64 = 0xFD2FB528;
let SKIPPABLE_MAGIC: u64 = 0x184D2A50;     // ...to 0x184D2A5F

// Decompresses every frame in src (zstd and skippable frames, back to
// back, at least one), appending the content to out. Returns an error
// message, empty on success; on an error, out holds what was decoded before
// it.
fn zstd_decompress(src: const u8[:], out: u8[>..]&) -> u8[>..] {
    if src.len == 0 { corrupt("empty input: no frames"); }
    var p = 0;
    while p < src.len {
        if src.len - p < 4 { corrupt("truncated frame header"); }
        let magic = load_le(src, p, 4);
        if magic & 0xFFFFFFF0 == SKIPPABLE_MAGIC {
            if src.len - p < 8 { corrupt("truncated skippable frame"); }
            let size = load_le(src, p + 4, 4) as i64;
            if size > src.len - p - 8 { corrupt("truncated skippable frame"); }
            p += 8 + size;
            continue;
        }
        if magic != ZSTD_MAGIC { corrupt("not in zstd format (bad magic number)"); }
        p += 4;
        p += decode_frame(src[p..], out);
    }
    return [];
}

// Ends the innermost zstd_decompress with an error message.
fn corrupt(msg: const u8[:]) { return str(msg) from zstd_decompress; }

// Decodes one frame (after its magic number). Returns the bytes it took.
fn decode_frame(src: const u8[:], out: u8[>..]&) -> i64 {
    if src.len < 1 { corrupt("truncated frame header"); }
    let fhd: i64 = src[0];
    let fcs_flag = fhd >> 6;
    let single = (fhd >> 5) & 1 == 1;
    if fhd & 8 != 0 { corrupt("reserved frame header bit set"); }
    let has_checksum = (fhd >> 2) & 1 == 1;
    let did_size = match fhd & 3 { 0 => 0, 1 => 1, 2 => 2, _ => 4 };
    let fcs_size = match fcs_flag { 0 => if single { 1 } else { 0 }, 1 => 2, 2 => 4, _ => 8 };
    var p = 1;
    var window = 0;
    if !single {
        if p >= src.len { corrupt("truncated frame header"); }
        let wd: i64 = src[p];
        p++;
        // Up to about 2^41. libzstd refuses windows over 2^27 unless told
        // otherwise, to bound its memory; here the whole output is in
        // memory anyway, so the window size costs nothing.
        let base = 1 << (10 + (wd >> 3));
        window = base + (base / 8) * (wd & 7);
    }
    if p + did_size + fcs_size > src.len { corrupt("truncated frame header"); }
    if load_le(src, p, did_size) != 0 { corrupt("dictionaries are not supported"); }
    p += did_size;
    var content_size = -1;
    if fcs_size > 0 {
        content_size = load_le(src, p, fcs_size) as! i64;
        if fcs_size == 2 { content_size += 256; }
        if content_size < 0 { corrupt("frame content size too large"); }
    }
    p += fcs_size;
    if single { window = content_size; }
    let block_max = min(window, BLOCK_MAX);

    let frame_start = out.len;
    var st = new_frame_state();
    var lits: u8[>..] = [];
    loop {
        if p + 3 > src.len { corrupt("truncated block header"); }
        let bh = load_le(src, p, 3) as i64;
        p += 3;
        let last = bh & 1 == 1;
        let kind = (bh >> 1) & 3;
        let size = bh >> 3;
        if size > block_max { corrupt("block larger than the window allows"); }
        if kind == 0 {
            if p + size > src.len { corrupt("truncated raw block"); }
            out.append(src[p..p + size]);
            p += size;
        } else if kind == 1 {
            if p + 1 > src.len { corrupt("truncated RLE block"); }
            out.resize(out.len + size, src[p]);
            p += 1;
        } else if kind == 2 {
            if p + size > src.len { corrupt("truncated compressed block"); }
            decode_block(src[p..p + size], st, lits, out, frame_start, window, block_max);
            p += size;
        } else {
            corrupt("reserved block type");
        }
        if last { break; }
    }

    let produced = out.len - frame_start;
    if content_size >= 0 && produced != content_size { corrupt("frame content size mismatch"); }
    if has_checksum {
        if p + 4 > src.len { corrupt("truncated checksum"); }
        let want = load_le(src, p, 4);
        p += 4;
        if xxh64(out[frame_start..], 0) & 0xFFFFFFFF != want { corrupt("checksum mismatch"); }
    }
    return p;
}
