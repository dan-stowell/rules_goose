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
    `extern fn` declarations, from any package. The generated C includes each
    by its path in its repository (`#include "native/foo.h"`), after its type
    declarations, and the header reaches the C compile too.
  cc_deps: cc_library targets to link (the C behind `extern fn`s).
  goose_opts: Extra Goose compiler flags, such as `-O2`, `--debug` or `-DNAME=1`.
  **kwargs: Everything else (data, args, env, copts, linkopts, visibility,
    tags, size, timeout, ...) is passed to cc_binary / cc_test.
"""

load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_test.bzl", "cc_test")
load("//goose/private:goose.bzl", "goose_c")

# Attributes the generated C target shares with the cc rule.
_SHARED_ATTRS = ["tags", "testonly", "visibility", "target_compatible_with", "compatible_with", "restricted_to"]

def _goose_program(cc_rule, name, main, srcs = [], c_hdrs = [], cc_deps = [], goose_opts = [], deps = None, linkopts = [], **kwargs):
    if deps != None:
        fail("goose_binary and goose_test take cc_deps, not deps")
    goose_c(
        name = name + "_goose",
        main = main,
        srcs = srcs,
        c_hdrs = c_hdrs,
        goose_opts = goose_opts,
        out = name + ".c",
        **{k: kwargs[k] for k in _SHARED_ATTRS if k in kwargs}
    )
    cc_rule(
        name = name,
        srcs = [name + ".c"],
        deps = [name + "_goose"] + cc_deps,
        # What the standalone runtime needs: dlopen is in libdl on Linux
        # (before glibc 2.34; an empty archive since), in libc elsewhere.
        linkopts = ["-lm", "-pthread"] + select({
            Label("@platforms//os:linux"): ["-ldl"],
            "//conditions:default": [],
        }) + linkopts,
        **kwargs
    )

def goose_binary(name, **kwargs):
    """A Goose program, built as a cc_binary. See the module docstring."""
    _goose_program(cc_binary, name, **kwargs)

def goose_test(name, **kwargs):
    """A Goose program run as a test (cc_test): it passes when it exits 0."""
    _goose_program(cc_test, name, testonly = True, **kwargs)
