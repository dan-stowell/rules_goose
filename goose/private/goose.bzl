"""Implementation of goose_binary and goose_test.

A Goose program is built in two steps:

1. `goose_c`, the private rule here, stages the program's sources and the
   standard library into one tree and runs the Goose compiler on it, writing a
   single standalone C file (`goose --standalone -o <name>.c`).
2. `cc_binary` or `cc_test` compiles and links that C file with whatever C
   toolchain the build has registered.
"""

load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_test.bzl", "cc_test")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

# What the standalone runtime needs at link time.
_LINK_FLAGS = ["-lm", "-pthread", "-ldl"]

def _package_prefix(label):
    """The short_path prefix of files in `label`'s package, with a trailing slash."""
    parts = []
    if label.workspace_name:
        parts.append("../" + label.workspace_name)
    if label.package:
        parts.append(label.package)
    return "/".join(parts) + "/" if parts else ""

def _relative_to(f, prefix, what, main):
    if not f.short_path.startswith(prefix):
        fail("%s %s is not in the package of main (%s), or below it: Goose resolves imports " %
             (what, f.short_path, main.short_path) +
             "relative to the main file, so every file of the program must be under its package")
    return f.short_path[len(prefix):]

def _goose_c_impl(ctx):
    main = ctx.file.main
    prefix = _package_prefix(main.owner)
    stage = "_goose/%s" % ctx.label.name

    # Every file of the program, by its path relative to main's package. The
    # compiler runs from <stage>/src, so it sees the same tree on every
    # machine, and the paths it writes into the C (in messages and the like)
    # are these relative ones.
    files = {}
    for what, group in [("main", [main]), ("srcs", ctx.files.srcs), ("c_hdrs", ctx.files.c_hdrs)]:
        for f in group:
            rel = _relative_to(f, prefix, what, main)
            if rel.endswith(".build"):
                # The compiler reads a package's `<name>.build` sidecar
                # silently, and with -o it ignores its C sources; native code
                # goes through cc_deps and c_hdrs instead.
                fail("%s: %s is a Goose sidecar (.build) file, which rules_goose does not support: " %
                     (what, f.short_path) +
                     "build the C with cc_library and pass it in cc_deps (and its header in c_hdrs)")
            if rel in files and files[rel] != f:
                fail("two files stage to %s: %s and %s" % (rel, files[rel].path, f.path))
            files[rel] = f

    staged = {}
    for rel, f in files.items():
        out = ctx.actions.declare_file("%s/src/%s" % (stage, rel))
        ctx.actions.symlink(output = out, target_file = f)
        staged[rel] = out

    # The standard library, beside the sources as <stage>/stdlib.
    stdlib = []
    for f in ctx.files._stdlib:
        rel = f.short_path[len(_package_prefix(f.owner)):]
        if not rel.startswith("stdlib/"):
            fail("unexpected file in the Goose standard library: " + f.short_path)
        out = ctx.actions.declare_file("%s/%s" % (stage, rel))
        ctx.actions.symlink(output = out, target_file = f)
        stdlib.append(out)

    main_rel = _relative_to(main, prefix, "main", main)
    src_dir = staged[main_rel].path[:-len(main_rel) - 1]

    args = ctx.actions.args()
    args.add(ctx.executable._compiler)
    args.add(ctx.outputs.out)
    log = ctx.actions.declare_file(ctx.label.name + ".log")
    args.add(log)
    args.add(src_dir)
    args.add(main_rel)
    args.add_all(ctx.attr.goose_opts)
    for h in ctx.files.c_hdrs:
        args.add("--include", _relative_to(h, prefix, "c_hdrs", main))

    ctx.actions.run_shell(
        outputs = [ctx.outputs.out, log],
        inputs = depset(staged.values() + stdlib),
        tools = [ctx.executable._compiler],
        arguments = [args],
        mnemonic = "GooseCompile",
        progress_message = "Compiling Goose program %{label}",
        # Bash builtins only: some remote executors (actiond) have nothing else.
        command = """
set -eu
execroot="$(pwd -P)"
compiler="$execroot/$1"
out="$execroot/$2"
# Nothing is fetched (--offline), and no package cache is read: GOOSE_HOME
# names a directory that does not exist.
goose_home="${out%/*}/.goose-home-unused"
log="$execroot/$3"
cd "$4"
main="$5"
shift 5
here_physical="$(pwd -P)"
here_logical="$(pwd)"
# The compiler's progress goes to stdout, its errors to stderr.
GOOSE_HOME="$goose_home" \\
    "$compiler" --standalone --offline --stdlib ../stdlib "$@" -o "$out" "$main" > "$log"
# Path packages (import x from "./dir") are named by absolute path in the C;
# make those paths relative to the source tree, so the C is the same everywhere.
c="$(< "$out")"
if [[ "$c" == *"$here_physical/"* || "$c" == *"$here_logical/"* ]]; then
  c="${c//"$here_physical/"/}"
  c="${c//"$here_logical/"/}"
  printf '%s\\n' "$c" > "$out"
fi
""",
    )

    compilation_context = cc_common.create_compilation_context(
        headers = depset([staged[_relative_to(h, prefix, "c_hdrs", main)] for h in ctx.files.c_hdrs]),
        # The C names an --include header by its path relative to main's
        # package, which is where it is staged.
        quote_includes = depset([src_dir]),
    )
    linking_context = cc_common.create_linking_context(
        linker_inputs = depset([cc_common.create_linker_input(
            owner = ctx.label,
            user_link_flags = depset(_LINK_FLAGS),
        )]),
    )
    return [
        DefaultInfo(files = depset([ctx.outputs.out, log])),
        CcInfo(
            compilation_context = compilation_context,
            linking_context = linking_context,
        ),
    ]

goose_c = rule(
    implementation = _goose_c_impl,
    doc = "Compiles a Goose program to one standalone C file, `out`.",
    attrs = {
        "c_hdrs": attr.label_list(allow_files = [".h", ".hh", ".hpp", ".inc"]),
        "goose_opts": attr.string_list(),
        "main": attr.label(allow_single_file = [".goose"], mandatory = True),
        "out": attr.output(mandatory = True),
        "srcs": attr.label_list(allow_files = True),
        "_compiler": attr.label(
            default = "@goose_src//:goose",
            executable = True,
            cfg = "exec",
        ),
        "_stdlib": attr.label(
            default = "@goose_src//:stdlib",
            allow_files = True,
        ),
    },
    provides = [CcInfo],
)

# Attributes the generated C target shares with the cc rule.
_SHARED_ATTRS = ["tags", "testonly", "target_compatible_with", "compatible_with", "restricted_to"]

def goose_program(cc_rule, is_test, name, main, srcs = [], c_hdrs = [], cc_deps = [], goose_opts = [], deps = None, **kwargs):
    """Shared helper of goose_binary and goose_test."""
    if deps != None:
        fail("goose_binary and goose_test take cc_deps, not deps")
    shared = {k: kwargs[k] for k in _SHARED_ATTRS if k in kwargs}
    if is_test:
        shared["testonly"] = True
    goose_c(
        name = name + "_goose",
        main = main,
        srcs = srcs,
        c_hdrs = c_hdrs,
        goose_opts = goose_opts,
        out = name + ".c",
        visibility = ["//visibility:private"],
        **shared
    )
    cc_rule(
        name = name,
        srcs = [name + ".c"],
        deps = [name + "_goose"] + cc_deps,
        **kwargs
    )

def goose_binary_impl(**kwargs):
    goose_program(cc_binary, False, **kwargs)

def goose_test_impl(**kwargs):
    goose_program(cc_test, True, **kwargs)
