"""cli_test and cli_tests: run goosegrep over a copy of testdata/ and checks its stdout and exit code."""

load("@rules_shell//shell:sh_test.bzl", "sh_test")

def cli_test(name, args, expected = None, exit_code = 0, setup = ""):
    """`name + "_test"` runs `goosegrep args...` in a copy of testdata/.

    Args:
      name: The case; the target is `name + "_test"`.
      args: goosegrep's arguments.
      expected: Its expected stdout; `expected/<name>.out` by default.
      exit_code: Its expected exit code.
      setup: Bash run in the copy first, to add what git cannot hold well
        (symlinks, FIFOs, odd names).
    """
    if expected == None:
        expected = "expected/%s.out" % name
    sh_test(
        name = name + "_test",
        size = "small",
        srcs = ["cli_test.sh"],
        args = [
            "$(rootpath :goosegrep)",
            "$(rootpath testdata/README.md)",
            "$(rootpath %s)" % expected,
            str(exit_code),
        ] + args,
        data = [
            ":goosegrep",
            ":testdata",
            expected,
        ],
        env = {"SETUP": setup},
    )

def cli_tests(cases):
    """A cli_test for each case: a dict of cli_test's arguments."""
    for case in cases:
        cli_test(**case)
