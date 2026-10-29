#include "tt_h264.h"
#include <stdlib.h>
#include <string.h>
#include "h264bsd/h264bsd_decoder.h"

struct tt_dec { storage_t *s; uint8_t *rgba; uint32_t w, h, cap; uint8_t *buf; uint32_t buf_cap; };

/* An access unit delimiter after the frame makes the decoder finish the picture now instead of waiting for the
 * next frame to arrive (one frame less latency). */
static const uint8_t AUD[] = { 0, 0, 0, 1, 9, 0xf0 };

tt_dec *tt_new(void) {
    tt_dec *d = calloc(1, sizeof *d);
    if (!d) return NULL;
    d->s = h264bsdAlloc();
    if (!d->s || h264bsdInit(d->s, 1) != H264BSD_RDY) { tt_free(d); return NULL; }
    return d;
}

void tt_free(tt_dec *d) {
    if (!d) return;
    if (d->s) { h264bsdShutdown(d->s); h264bsdFree(d->s); }
    free(d->rgba); free(d->buf); free(d);
}

static int take_picture(tt_dec *d) {
    u32 id, idr, err, *pic = NULL, *p;
    while ((p = h264bsdNextOutputPictureRGBA(d->s, &id, &idr, &err))) pic = p;
    if (!pic) return 0;
    u32 full_w = h264bsdPicWidth(d->s) * 16, crop, left, w, top, h;
    h264bsdCroppingParams(d->s, &crop, &left, &w, &top, &h);
    if (!crop) { left = top = 0; w = full_w; h = h264bsdPicHeight(d->s) * 16; }
    uint32_t need = w * h * 4;
    if (need > d->cap) {
        uint8_t *n = realloc(d->rgba, need);
        if (!n) return -1;
        d->rgba = n; d->cap = need;
    }
    for (uint32_t y = 0; y < h; y++) memcpy(d->rgba + y * w * 4, pic + (top + y) * full_w + left, w * 4);
    d->w = w; d->h = h;
    return 1;
}

int tt_decode(tt_dec *d, const uint8_t *data, uint32_t len) {
    uint32_t total = len + sizeof AUD;
    if (total > d->buf_cap) {
        uint8_t *n = realloc(d->buf, total);
        if (!n) return -1;
        d->buf = n; d->buf_cap = total;
    }
    memcpy(d->buf, data, len);
    memcpy(d->buf + len, AUD, sizeof AUD);
    u8 *p = d->buf;
    u32 left = total, used = 0;
    int got = 0, stalls = 0;
    while (left > 0) {
        u32 r = h264bsdDecode(d->s, p, left, 0, &used);
        if (r == H264BSD_PIC_RDY) { int t = take_picture(d); if (t < 0) return -1; got |= t; }
        else if (r == H264BSD_ERROR || r == H264BSD_PARAM_SET_ERROR || r == H264BSD_MEMALLOC_ERROR) return got ? 1 : -1;
        /* HDRS_RDY (new stream parameters active) consumes nothing: the same slice must be fed again. */
        if (!used) { if (r != H264BSD_HDRS_RDY || ++stalls > 2) break; continue; }
        p += used; left -= used;
    }
    return got;
}

const uint8_t *tt_rgba(tt_dec *d, uint32_t *w, uint32_t *h) { *w = d->w; *h = d->h; return d->rgba; }
