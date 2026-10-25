# Examples

Two programs built with `goose_binary` and tested in this repository
(`bb remote test //examples/... --config=remote`).

- [`goosegrep/`](goosegrep): a small ripgrep in Goose. It searches files and
  directories recursively, skipping hidden and binary files, with `-i`, `-w`,
  `-F`, `-v`, `-c`, `-l` and `-n`/`-N`. `search_test` is a `goose_test` of the
  search module; each `*_test` sh_test runs the binary over `testdata/` and
  compares its stdout and exit code with `expected/`.
- [`goosezstd/`](goosezstd): a Zstandard decompressor in pure Goose, tested
  against the real `zstd` CLI from the BCR module (a dev dependency), plus a
  `libzstd_demo` that calls libzstd through `extern fn`, `c_hdrs` and
  `cc_deps`, and benchmarks. See its [README](goosezstd/README.md).
