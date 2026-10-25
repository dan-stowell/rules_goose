# rules_goose

Bazel rules for [Goose](https://github.com/aardappel/goose), a language whose
compiler transpiles a whole program to C. `goose_binary` and `goose_test` run
the Goose compiler (built from source at a pinned commit) to write one
standalone C file, then build it with `cc_binary` / `cc_test`, using whatever C
toolchain your build registers. Bzlmod only.

## Setup

```starlark
# MODULE.bazel
bazel_dep(name = "rules_goose", version = "...")
```

Register a C/C++ toolchain as usual (or rely on the auto-detected one). It
builds both the Goose compiler (C++20, exec configuration) and your programs.

## Usage

```starlark
load("@rules_goose//goose:defs.bzl", "goose_binary", "goose_test")

goose_binary(
    name = "hello",
    main = "hello.goose",
    srcs = ["util.goose", "geom/geom.goose"],
    c_hdrs = ["//native:foo.h"],   # C side of extern fns, from any package
    cc_deps = ["//native:foo"],    # the cc_library behind them
    goose_opts = ["-O2"],
)

goose_test(name = "hello_test", main = "hello_test.goose", size = "small")
```

`bazel build //app:hello` writes `hello.c` (target `//app:hello.c`) and links
`hello`. A `goose_test` passes when the program exits 0.

| Attribute    | Description |
|--------------|-------------|
| `main`       | The root `.goose` file; imports resolve relative to it. |
| `srcs`       | Other `.goose` files and `embed_file` inputs, in main's package or below. |
| `c_hdrs`     | Headers for `extern fn`s, passed as `--include`; any package. |
| `cc_deps`    | `cc_library` targets to link. |
| `goose_opts` | Extra compiler flags: `-O2`, `--debug`, `-DNAME=value`, ... |
| others       | Passed to `cc_binary` / `cc_test` (a non-empty `deps` is rejected; use `cc_deps`). |

The docstring in `goose/defs.bzl` is the full reference.

## How compiling works

- `main` and `srcs` are staged by their path relative to main's package, beside
  the standard library, and the compiler runs there:
  `goose --standalone --offline --stdlib ../stdlib [goose_opts] [--include h]... -o <name>.c <main>`.
  So `import a.b;`, `import .x;` and path packages (`import x from "./dir";`)
  work as outside Bazel, as long as every file is listed. Files outside main's
  package are an error; `.build` sidecars are rejected (build their C with
  `cc_library` and use `cc_deps`/`c_hdrs`).
- A `c_hdrs` header is included as its path in its repository
  (`#include "native/foo.h"`), and stays beside its own sibling headers.
  It may be in `srcs` too (for `embed_file`), unless that stages it under its
  include name, as when main is in its repository's root package.
- Known limit: two `c_hdrs` headers with the same path in different
  repositories collide on that include name.
- Known limit: execution-root paths with characters Goose escapes in C strings
  (quotes, non-ASCII) are not rewritten out of the generated C.
- `--offline`: nothing is fetched and no package cache is read, so git packages
  and the blessed packages from other repositories (gfx, audio, ui, physics)
  are unavailable; vendor their `.goose` files and import them as path packages.
- The C is the same on every machine: the absolute paths the compiler writes
  for path packages are rewritten relative to the staged tree
  (`//tests:c_has_no_build_paths_test`).
- Under the default `fastbuild` the C compiles at `-O0`. Use `-c opt` or pass
  `copts` (e.g. `copts = ["-O2"]`) for optimized programs.

Not supported: JIT mode, `goose build`/`run`, `--header`, the compiled-in
blessed packages.

## Platforms

Linux and macOS, on x86_64 and aarch64; the runtime links `-lm -pthread`, plus
`-ldl` on Linux. Windows (MSVC or MinGW) is not supported: building the compiler for it
fails with a clear error.

## Developing

This repository's builds use
[hermetic-llvm](https://github.com/hermeticbuild/hermetic-llvm) (a dev
dependency) targeting static musl on x86_64 Linux; `--config=glibc` targets
glibc 2.28 with dynamic linking instead. Run the tests on BuildBuddy RBE (the
runner clones from GitHub, so push first):

```sh
bb remote test //... --config=remote
bb remote test //... --config=remote --config=glibc
```

`tests/` builds upstream samples straight from the pinned Goose tree and
compares their stdout with upstream's, plus tests of `c_hdrs`/`cc_deps` across
packages, abort locations, and a `goose_test` that must fail.

To update Goose, change `GOOSE_COMMIT` and `sha256` in `MODULE.bazel` and check
the overlay (`goose/private/goose_src.BUILD.bazel`) against upstream's
`CMakeLists.txt` and `cmake/*.cmake`. Goose is Apache-2.0; TinyCC, which the
compiler links, is LGPL-2.1.
