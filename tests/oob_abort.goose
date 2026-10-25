// An index out of bounds in a path package: the runtime's abort message names
// the package's file by its path relative to the program, not by the absolute
// path the compiler sees it at.
import oob from "./oob";

fn main() {
    oob::at(5);
}
