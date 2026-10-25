# goosezstd

A Zstandard decompressor ([RFC 8878](https://www.rfc-editor.org/rfc/rfc8878))
written in pure Goose, built with `goose_binary` and tested against the real
`zstd`.

```sh
goosezstd -d IN [-o OUT]   # decompress IN (- for stdin) to OUT, or stdout
goosezstd -t IN            # test that IN decompresses
```

It decodes zstd and skippable frames (any number, back to back), raw, RLE and
compressed blocks, raw/RLE/Huffman literals (one or four streams, and
treeless), FSE sequence tables (predefined, RLE, compressed and repeat), repeat
offsets, and checks the frame content size and XXH64 content checksum. No
dictionaries. Input and output are held in memory, and the output doubles as
the match window.

| File | |
|---|---|
| `goosezstd.goose` | `main` |
| `cli.goose` | the command line, generic over the decoder |
| `zstd/frame.goose` | frames and blocks: `zstd_decompress` |
| `zstd/blocks.goose` | literals and sequences sections, match copying |
| `zstd/huffman.goose` | Huffman tree descriptions and streams |
| `zstd/fse.goose` | FSE table descriptions and decoding tables |
| `zstd/bits.goose` | forward and backward bit readers |
| `zstd/xxhash.goose` | XXH64 |
| `libzstd_demo.goose`, `libzstd_shim.h` | the same CLI over the real libzstd, via `extern fn` and `cc_deps` |

A corrupt input anywhere in the decoder is one line,
`corrupt("what went wrong")`, which is `return str(msg) from zstd_decompress`:
the error message lands in `zstd_decompress`'s result, past every frame in
between, and none of those functions has any error plumbing.

## Tests

The BCR `zstd` module (a dev dependency of rules_goose) builds the real `zstd`
CLI and `datagen`. At build time they make the inputs (lorem ipsum, Goose
sources, repetitive text, zeros, noise, synthetic data, an empty file, one
byte, and a Doom level) and compress each at nine settings (`--fast=5`, `-1`,
`-3`, `-19`, `--ultra -22`, `--long=27`, `-T4`, `--no-check`, and from a pipe,
so with no content size). Each `<input>_<setting>_test` decodes one with
goosezstd to a file, to stdout and from stdin, and compares the result with
the input byte for byte.

* `multi_frame_test`: five frames and two skippable frames in one file.
* `reject_test`: bad magic, a bad checksum, truncation, trailing garbage and
  garbled entropy-coded data all fail with a message.
* `libzstd_demo_*_test`: the libzstd demo through the same harness.
* `bench_test`: prints both decoders' throughput on 64 MiB of synthetic data.
  On BuildBuddy RBE with `-c opt`, goosezstd ran at about 260 MB/s and zstd at
  about 1.2 GB/s.

```sh
bb remote test //examples/goosezstd/... --config=remote
bb remote test //examples/goosezstd:bench_test --config=remote -c opt --test_output=all
```
