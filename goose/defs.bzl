"""Public API of rules_goose: goose_binary and goose_test.

Both compile a Goose program to one standalone C file with the Goose compiler
(`goose --standalone --offline -o <name>.c`), then build that file with
`cc_binary` or `cc_test`. The C compile and link use whatever C toolchain the
build has registered.

Attributes:
  name: The cc_binary / cc_test target. The C file is `<name>.c`.
  main: The program's root `.goose` file. Imports (`import a.b;`, `import .x;`
    and path packages, `import x from "./dir";`) resolve relative to it.
  srcs: The program's other `.goose` files, and any files it reads at compile
    time with embed_file. Every file must be in main's package or below it.
    `.build` sidecar files are rejected (see README.md).
  c_hdrs: C headers passed to the compiler as `--include`, for the C side of
    `extern fn` declarations. They are included by the generated C after its
    type declarations, and reach the C compile too.
  cc_deps: cc_library targets to link (the C behind `extern fn`s).
  goose_opts: Extra Goose compiler flags, such as `-O2`, `--debug` or `-DNAME=1`.
  **kwargs: Everything else (data, args, env, copts, linkopts, visibility,
    tags, size, timeout, ...) is passed to cc_binary / cc_test.
"""

load("//goose/private:goose.bzl", "goose_binary_impl", "goose_test_impl")

def goose_binary(name, main, srcs = [], c_hdrs = [], cc_deps = [], goose_opts = [], **kwargs):
    """A Goose program, built as a cc_binary. See the module docstring."""
    goose_binary_impl(
        name = name,
        main = main,
        srcs = srcs,
        c_hdrs = c_hdrs,
        cc_deps = cc_deps,
        goose_opts = goose_opts,
        **kwargs
    )

def goose_test(name, main, srcs = [], c_hdrs = [], cc_deps = [], goose_opts = [], **kwargs):
    """A Goose program run as a test (cc_test): it passes when it exits 0."""
    goose_test_impl(
        name = name,
        main = main,
        srcs = srcs,
        c_hdrs = c_hdrs,
        cc_deps = cc_deps,
        goose_opts = goose_opts,
        **kwargs
    )
