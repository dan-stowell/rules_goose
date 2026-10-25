// //tests/glob:glob_test, whose srcs glob takes in this file too.
import std;
import .helper;

fn main() {
    assert(helper_value() == 42);
    print("ok");
}
