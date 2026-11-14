// musl has no <execinfo.h>. Compute's trace recorder includes it for backtrace(); with this
// stand-in it records no stack frames. Remove once Compute guards the include.

#pragma once

static inline int backtrace(void **buffer, int size) {
    (void)buffer;
    (void)size;
    return 0;
}
