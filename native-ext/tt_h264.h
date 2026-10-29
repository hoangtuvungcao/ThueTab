/* Minimal H.264 (Baseline) decoder for the ThuêTab app's live view, on top of h264bsd (Apache 2.0, from Android). */
#ifndef TT_H264_H
#define TT_H264_H
#include <stdint.h>

typedef struct tt_dec tt_dec;
tt_dec *tt_new(void);
void tt_free(tt_dec *d);
/* Decodes one access unit (Annex B). 1 = a new picture is ready, 0 = none, -1 = undecodable data. */
int tt_decode(tt_dec *d, const uint8_t *data, uint32_t len);
/* Last picture as tightly packed RGBA8, cropped to the display size. */
const uint8_t *tt_rgba(tt_dec *d, uint32_t *w, uint32_t *h);
#endif
