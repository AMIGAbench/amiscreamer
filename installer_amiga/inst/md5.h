/* MD5 (RFC 1321) für die GOG-Teile, md5.c */
#ifndef MD5_H
#define MD5_H
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t h[4];
    uint64_t len;
    uint8_t buf[64];
} Md5;
void md5_init(Md5 *m);
void md5_update(Md5 *m, const void *data, size_t n);
void md5_final(Md5 *m, uint8_t out[16]);
#endif
