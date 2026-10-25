"""goose_c: compiles a Goose program to one standalone C file.

The program's sources and the standard library are staged into one tree, and
the Goose compiler runs on it, writing `goose --standalone -o <name>.c`.
goose_binary and goose_test (defs.bzl) build that file with cc_binary or
cc_test.
"""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _repo_path(f):
    """f's path relative to the root of its repository."""
    if f.owner.workspace_name:
        return f.short_path[len("../" + f.owner.workspace_name + "/"):]
    return f.short_path

def _goose_c_impl(ctx):
    main = ctx.file.main
    repo = main.owner.workspace_name
    pkg = main.owner.package
    prefix = pkg + "/" if pkg else ""
    stage = "_goose/%s" % ctx.label.name

    # main and srcs, by their path relative to main's package: Goose resolves
    # imports relative to the main file. The compiler runs from <stage>/src,
    # so it sees the same tree on every machine, and the paths it writes into
    # the C (in messages and the like) are these relative ones.
    staged = []
    main_rel = _repo_path(main)[len(prefix):]
    for f in [main] + ctx.files.srcs:
        path = _repo_path(f)
        if f.owner.workspace_name != repo or not path.startswith(prefix):
            fail(("%s is not in the package of main (@%s//%s) or below it. Goose resolves imports " +
                  "relative to the main file, so main and srcs must all be under main's package. " +
                  "(C headers go in c_hdrs, which may come from any package.)") % (f.owner, repo, pkg))
        rel = path[len(prefix):]
        if rel.endswith(".build"):
            # The compiler reads a package's `<name>.build` sidecar silently,
            # and with -o it ignores its C sources; native code goes through
            # cc_deps and c_hdrs instead.
            fail("%s is a Goose sidecar (.build) file, which rules_goose does not support: " % f.owner +
                 "build the C with cc_library and pass it in cc_deps (and its header in c_hdrs)")
        out = ctx.actions.declare_file("%s/src/%s" % (stage, rel))
        ctx.actions.symlink(output = out, target_file = f)
        staged.append(out)
    src_dir = staged[0].path[:-len(main_rel) - 1]

    # The standard library, beside the sources as <stage>/stdlib.
    for f in ctx.files._stdlib:
        out = ctx.actions.declare_file("%s/%s" % (stage, _repo_path(f)))
        ctx.actions.symlink(output = out, target_file = f)
        staged.append(out)

    # The compiler only writes `#include "<name>"` for a c_hdrs header; it
    # never reads it. Each header is named by its path in its repository, and
    # that repository's root goes on the C compile's quote include path, so
    # the header is included where it is, beside its own siblings.
    hdr_names = [_repo_path(h) for h in ctx.files.c_hdrs]
    hdr_roots = ["/".join([p for p in [h.root.path, h.owner.workspace_root] if p]) or "." for h in ctx.files.c_hdrs]

    compiler = ctx.attr._compiler[DefaultInfo].files_to_run
    args = ctx.actions.args()
    args.add(compiler.executable)
    args.add(ctx.outputs.out)
    args.add(src_dir)
    args.add(main_rel)
    args.add_all(ctx.attr.goose_opts)
    args.add_all(hdr_names, before_each = "--include")

    ctx.actions.run_shell(
        outputs = [ctx.outputs.out],
        inputs = staged,
        tools = [compiler],
        arguments = [args],
        mnemonic = "GooseCompile",
        progress_message = "Compiling Goose program %{label}",
        command = """
set -eu
execroot="$(pwd -P)"
compiler="$execroot/$1"
out="$execroot/$2"
# Nothing is fetched (--offline), and no package cache is read: GOOSE_HOME
# names a directory that does not exist.
goose_home="${out%/*}/.goose-home-unused"
cd "$3"
main="$4"
shift 4
here_physical="$(pwd -P)"
here_logical="$(pwd)"
# The compiler's progress goes to stdout, its errors to stderr.
GOOSE_HOME="$goose_home" \\
    "$compiler" --standalone --offline --stdlib ../stdlib "$@" -o "$out" "$main" > /dev/null
# Path packages (import x from "./dir") are named by absolute path in the C,
# only ever in the NUL-terminated file names of abort locations
# (`static const char gs_fileN[] = "...";`); make those paths relative to the
# source tree, so the C is the same everywhere.
c="$(< "$out")"
if [[ "$c" == *"$here_physical/"* || "$c" == *"$here_logical/"* ]]; then
  c="${c//"$here_physical/"/}"
  c="${c//"$here_logical/"/}"
  printf '%s\\n' "$c" > "$out"
fi
""",
    )

    return [
        DefaultInfo(files = depset([ctx.outputs.out])),
        CcInfo(compilation_context = cc_common.create_compilation_context(
            headers = depset(ctx.files.c_hdrs),
            quote_includes = depset(hdr_roots),
        )),
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
