/* Minimal libc declarations for cross-compiling the decoder to macOS without the Apple SDK (resolved from
 * libSystem at load time). */
#pragma once
#include <stddef.h>
void *malloc(size_t);
void *calloc(size_t, size_t);
void *realloc(void *, size_t);
void free(void *);
