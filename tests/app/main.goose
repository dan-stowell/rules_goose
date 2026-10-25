// Calls C from another package: //tests/native:foo, its header in c_hdrs.
import std;

extern fn foo_scale(x: i64) -> i64;

fn main() {
    assert(foo_scale(6) == 42);
    print("ok");
}
