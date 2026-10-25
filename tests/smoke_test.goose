// A goose_test: passes when the program exits 0, fails on a failed assert.
import std;

fn main() {
    var xs: i32[>..] = [];
    for i in 10 { xs.push(i as i32 * 3); }
    assert(xs.len == 10);
    assert(xs[9] == 27);
    print("ok");
}
