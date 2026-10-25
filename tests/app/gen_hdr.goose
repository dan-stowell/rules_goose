// Calls C from a genrule-generated header (c_hdrs).
import std;

extern fn gen_value() -> i64;

fn main() {
    assert(gen_value() == 42);
    print("ok");
}
