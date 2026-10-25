/* The C side of //tests/app:native_test's extern fn. Its own include is of a
   sibling header, which must resolve from wherever foo.h is included. */
#include "foo_detail.h"

int64_t foo_scale(int64_t x);
