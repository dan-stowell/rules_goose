/* The C side of libzstd_demo.goose: decompresses every frame in src with
   libzstd's streaming API, appending the content to the Goose builder out.
   Returns 1 on success; on failure appends libzstd's error name to err and
   returns 0. */
#include <stdlib.h>
#include <string.h>
#include <zstd.h>

static int32_t c_zstd_decompress(sl_u8 src, gs_rref out, gs_rref err) {
    const char *msg = NULL;
    ZSTD_DCtx *d = ZSTD_createDCtx();
    size_t cap = ZSTD_DStreamOutSize();
    char *buf = malloc(cap);
    ZSTD_inBuffer in = { src.data, (size_t)src.len, 0 };
    size_t left = 0;
    if (d == NULL || buf == NULL) msg = "out of memory";
    while (msg == NULL) {
        ZSTD_outBuffer o = { buf, cap, 0 };
        left = ZSTD_decompressStream(d, &o, &in);
        if (ZSTD_isError(left)) { msg = ZSTD_getErrorName(left); break; }
        gs_bld_append(out, buf, o.pos);
        if (in.pos == in.size && (left == 0 || o.pos == 0)) break;
    }
    if (msg == NULL && left != 0) msg = "truncated input";
    free(buf);
    ZSTD_freeDCtx(d);
    if (msg != NULL) { gs_bld_append(err, msg, strlen(msg)); return 0; }
    return 1;
}
