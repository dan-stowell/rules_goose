// A goose_test that must fail: its assert does not hold.
import std;

fn main() {
    var xs: i32[>..] = [];
    xs.push(1);
    assert(xs.len == 2);
}
