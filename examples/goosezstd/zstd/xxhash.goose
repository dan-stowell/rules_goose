// XXH64, which a zstd frame's optional content checksum is the low 32 bits
// of (seed 0). Unsigned arithmetic wraps in Goose, as the hash wants.
import std;
import zstd.bits;

let XXH_P1: u64 = 11400714785074694791;
let XXH_P2: u64 = 14029467366897019727;
let XXH_P3: u64 = 1609587929392839161;
let XXH_P4: u64 = 9650029242287828579;
let XXH_P5: u64 = 2870177450012600261;

fn rotl(x: u64, r: i64) -> u64 { (x << r) | (x >> (64 - r)) }

fn xxh_round(acc: u64, input: u64) -> u64 { rotl(acc + input * XXH_P2, 31) * XXH_P1 }

fn xxh_merge(acc: u64, v: u64) -> u64 { (acc ^ xxh_round(0, v)) * XXH_P1 + XXH_P4 }

fn xxh64(data: const u8[:], seed: u64) -> u64 {
    let n = data.len;
    var p = 0;
    var h: u64 = 0;
    if n >= 32 {
        var v1 = seed + XXH_P1 + XXH_P2;
        var v2 = seed + XXH_P2;
        var v3 = seed;
        var v4 = seed - XXH_P1;
        while p + 32 <= n {
            v1 = xxh_round(v1, load_le64(data, p));
            v2 = xxh_round(v2, load_le64(data, p + 8));
            v3 = xxh_round(v3, load_le64(data, p + 16));
            v4 = xxh_round(v4, load_le64(data, p + 24));
            p += 32;
        }
        h = rotl(v1, 1) + rotl(v2, 7) + rotl(v3, 12) + rotl(v4, 18);
        h = xxh_merge(h, v1);
        h = xxh_merge(h, v2);
        h = xxh_merge(h, v3);
        h = xxh_merge(h, v4);
    } else {
        h = seed + XXH_P5;
    }
    h += n as u64;
    while p + 8 <= n {
        h ^= xxh_round(0, load_le64(data, p));
        h = rotl(h, 27) * XXH_P1 + XXH_P4;
        p += 8;
    }
    if p + 4 <= n {
        h ^= load_le(data, p, 4) * XXH_P1;
        h = rotl(h, 23) * XXH_P2 + XXH_P3;
        p += 4;
    }
    while p < n {
        h ^= data[p] * XXH_P5;
        h = rotl(h, 11) * XXH_P1;
        p++;
    }
    h ^= h >> 33;
    h *= XXH_P2;
    h ^= h >> 29;
    h *= XXH_P3;
    h ^= h >> 32;
    return h;
}
