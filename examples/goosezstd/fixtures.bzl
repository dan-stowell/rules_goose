"""Test fixtures made with the real zstd CLI at build time, and the tests that decode them."""

load("@rules_shell//shell:sh_test.bzl", "sh_test")

ZSTD = "@zstd//:zstd_cli"

def zstd_compress(name, src, flags, stdin = False):
    """`name`.zst: `src` compressed by the zstd CLI with `flags`.

    With stdin, zstd reads a pipe, so the frame has no content size.
    """
    redirect = "< $<" if stdin else "$<"
    native.genrule(
        name = name,
        srcs = [src],
        outs = [name + ".zst"],
        cmd = "$(execpath %s) -q -f -c %s %s > $@" % (ZSTD, flags, redirect),
        tools = [ZSTD],
        testonly = True,
    )

def decompress_test(name, compressed, original, decoder = ":goosezstd", size = "small"):
    """Decodes `compressed` with `decoder` and compares it with `original`."""
    sh_test(
        name = name,
        size = size,
        srcs = ["decompress_test.sh"],
        args = [
            "$(rootpath %s)" % decoder,
            "$(rootpath %s)" % compressed,
            "$(rootpath %s)" % original,
        ],
        data = [decoder, compressed, original],
    )

def zstd_matrix(inputs, settings):
    """A decompress_test per input and setting: `<input>_<setting>_test`.

    Args:
      inputs: {input name: label}.
      settings: {setting name: (zstd flags, read from stdin)}.
    """
    for input_name, src in inputs.items():
        for setting, (flags, stdin) in settings.items():
            name = "%s_%s" % (input_name, setting)
            zstd_compress(name, src, flags, stdin)
            decompress_test(name + "_test", ":%s.zst" % name, src)
