"""sample_test: builds an upstream Goose sample and checks its stdout."""

load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//goose:defs.bzl", "goose_binary")

def sample_test(name, main, expected, srcs = [], c_hdrs = [], goose_opts = ["-O2"], **kwargs):
    """`name` is the program (goose_binary); `name + "_test"` runs it and diffs stdout."""
    goose_binary(
        name = name,
        main = main,
        srcs = srcs,
        c_hdrs = c_hdrs,
        goose_opts = goose_opts,
        testonly = True,
    )
    sh_test(
        name = name + "_test",
        srcs = ["expect_stdout.sh"],
        args = [
            "$(rootpath :%s)" % name,
            "$(rootpath %s)" % expected,
        ],
        data = [
            ":" + name,
            expected,
        ],
        **kwargs
    )
