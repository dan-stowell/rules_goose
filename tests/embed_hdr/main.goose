// Calls C from native.h (c_hdrs) and embeds the same file (srcs).
import std;

let NATIVE_H: const u8[:] = embed_file("native.h");

extern fn embed_hdr_value() -> i64;

fn main() {
    assert(embed_hdr_value() == 42);
    assert(NATIVE_H.len > 0);
    assert((NATIVE_H[0] as i64) == 47);  // '/'
    print("ok");
}
