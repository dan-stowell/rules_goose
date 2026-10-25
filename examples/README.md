# Examples

Two programs built with `goose_binary` and tested in this repository
(`bb remote test //examples/... --config=remote`).

- [`goosegrep/`](goosegrep): a small ripgrep in Goose. It searches files and
  directories recursively, skipping symlinks, non-regular files and (unless
  named) binary and hidden files, with `-i`, `-w`, `-F`, `-v`, `-c`, `-l`
  and `-n`/`-N`. Its walk lists directories through a few lines of C
  (`dir_shim.h`, an `extern fn` passed in `c_hdrs`) that report each entry's
  type as `lstat` sees it. `search_test` is a `goose_test` of the search
  module; each other `*_test` runs the binary over a copy of `testdata/`
  (some add symlinks, a FIFO or an odd name to it first) and compares its
  stdout and exit code with `expected/`.
- [`goosezstd/`](goosezstd): a Zstandard decompressor in pure Goose, tested
  against the real `zstd` CLI from the BCR module (a dev dependency), plus a
  `libzstd_demo` that calls libzstd through `extern fn`, `c_hdrs` and
  `cc_deps`, and benchmarks. See its [README](goosezstd/README.md).
