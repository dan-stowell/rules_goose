# rules_goose

Bazel rules for [Goose](https://github.com/aardappel/goose), a language whose
whole-program compiler transpiles to C.

`goose_binary` and `goose_test` run the Goose compiler (built from source, at a
pinned commit) to turn a program into one standalone C file, then build that file
with `cc_binary` / `cc_test`. The C compile and link use **whatever C toolchain
your build registers**: rules_goose brings no toolchain of its own.

Bzlmod only.

## Setup

```starlark
# MODULE.bazel
bazel_dep(name = "rules_goose", version = "...")
```

Register a C/C++ toolchain as you normally would (or rely on the auto-detected
local one). It builds both the Goose compiler (C++20, in the exec configuration)
and your programs.

## Usage

```starlark
load("@rules_goose//goose:defs.bzl", "goose_binary", "goose_test")

goose_binary(
    name = "hello",
    main = "hello.goose",
    srcs = ["util.goose", "geom/geom.goose"],
)

# extern fns implemented in C: the header goes to the compiler (--include) and
# to the C compile; a cc_library with the implementation goes in cc_deps.
goose_binary(
    name = "call_c",
    main = "call_c.goose",
    c_hdrs = ["call_c.h"],
    goose_opts = ["-O2"],
)

goose_test(
    name = "hello_test",
    main = "hello_test.goose",
    size = "small",
)
```

`bazel build //:hello` writes `hello.c` (target `//:hello.c`) and links `hello`.

### Attributes

| Attribute    | Description |
|--------------|-------------|
| `name`       | The `cc_binary` / `cc_test`. The generated C is `<name>.c`. |
| `main`       | The program's root `.goose` file. Imports resolve relative to it. |
| `srcs`       | The program's other `.goose` files (modules, path packages), and files it reads with `embed_file`. |
| `c_hdrs`     | C headers passed to the compiler with `--include`, for the C side of `extern fn`s. The generated C includes them (by their path relative to main's package), and they reach the C compile. |
| `cc_deps`    | `cc_library` targets to link: the C behind `extern fn`s. |
| `goose_opts` | Extra compiler flags: `-O0`/`-O1`/`-O2`, `--debug`, `-DNAME=value`, `--no-bce`, ... |
| everything else | Passed to `cc_binary` / `cc_test`: `data`, `args`, `env`, `copts`, `linkopts`, `visibility`, `tags`, `size`, `timeout`, ... (`deps` is rejected; use `cc_deps`). |

### How the compile works

- Every file of the program (`main`, `srcs`, `c_hdrs`) must be in main's
  package or below it. They are staged into one directory tree, keyed by their
  path relative to main's package, beside a copy of the standard library, and
  the compiler runs from there:
  `goose --standalone --offline --stdlib ../stdlib [goose_opts] [--include h]... -o <name>.c <main>`.
  So `import a.b;`, `import .x;` and path packages (`import x from "./dir";`)
  all work as they do outside Bazel, as long as the files are listed.
- `--offline`: the compile never fetches a package, and it reads no package
  cache (`GOOSE_HOME` points at a directory that does not exist). Git packages
  (`import x from "owner/repo@tag";`) and the blessed packages that live in other
  repositories (gfx, audio, ui, physics) are therefore not available; vendor a
  package's `.goose` files into your tree and import it as a path package
  instead.
- The C is the same on every machine: paths in it are relative to the staged
  tree. (The compiler names path packages by absolute path; the rule rewrites
  those.) `tests:c_has_no_build_paths_test` checks this.
- The standalone C holds the whole runtime; the rule links it with
  `-lm -pthread -ldl`.

### Sidecar `.build` files are rejected

Goose reads a package's `<name>.build` sidecar (its C sources, includes,
defines, libraries, `exclude`d directories) whenever it is present beside the
package's entry file. With `-o` the compiler builds none of that C, so a sidecar
would be half-honoured, silently. rules_goose therefore refuses any `.build`
file in `srcs` (and only listed files are staged, so the compiler never sees an
unlisted one). Build a package's C with `cc_library` and pass it in `cc_deps`,
its header in `c_hdrs`.

### Not supported (yet)

JIT mode, `goose build` / `goose run`, `--header` (library mode), and the
compiled-in blessed packages.

## Toolchains

The Goose compiler is built with plain rules_cc in an overlay BUILD file
(`goose/private/goose_src.BUILD.bazel`), and the generated C with `cc_binary` /
`cc_test`, so any registered toolchain works: the auto-detected local one,
hermetic-llvm, toolchains_llvm, zig, ...

This repository's own builds use
[hermetic-llvm](https://github.com/hermeticbuild/hermetic-llvm), registered as
a dev dependency (users don't inherit it). `.bazelrc` targets
`@llvm//platforms:linux_x86_64_musl` for both the target and the host (exec)
platform: everything, the Goose compiler included, is linked statically against
musl, so it runs on any x86-64 Linux whatever its glibc (remote executors
included). On another host OS this cross-compiles; use the remote config below
to run the tests.

## Developing rules_goose

```sh
# BuildBuddy RBE (the runner clones the branch from GitHub, so push first)
bb remote test //... --config=remote
```

`--config=remote` sets the BuildBuddy executor, cache and BES flags,
`--remote_download_minimal` and `--jobs=100`.

Tests (`tests/`) build upstream samples and tests straight from the pinned Goose
tree and compare their stdout with upstream's expected output:

| Target | Upstream source |
|--------|-----------------|
| `//tests:tour_test` | `samples/01_tour.goose` |
| `//tests:sieve_test` | `samples/07_sieve.goose` (imports `std` and `os`) |
| `//tests:call_c_test` | `samples/24_call_c.goose`, with `call_c.h` through `c_hdrs` |
| `//tests:pkg_basic_test` | `test/packages/pkg_basic.goose` (path packages, module and relative imports) |
| `//tests:c_has_no_build_paths_test` | the generated C names no build path |
| `//tests:smoke_test` | a `goose_test` |

The Goose sources are Apache-2.0, (c) the Goose authors; TinyCC, which the
compiler links, is LGPL-2.1.

## Updating Goose

Change `GOOSE_COMMIT` and `sha256` in `MODULE.bazel`, then check the overlay
against upstream's `CMakeLists.txt`, `cmake/libtcc.cmake` and
`cmake/package.cmake`.
