#include <stddef.h>

void *memcpy(void *destination, const void *source, size_t count)
{
    unsigned char *d = (unsigned char *)destination;
    const unsigned char *s = (const unsigned char *)source;
    while (count-- != 0u) *d++ = *s++;
    return destination;
}

void *memset(void *destination, int value, size_t count)
{
    unsigned char *d = (unsigned char *)destination;
    while (count-- != 0u) *d++ = (unsigned char)value;
    return destination;
}

void *memmove(void *destination, const void *source, size_t count)
{
    unsigned char *d = (unsigned char *)destination;
    const unsigned char *s = (const unsigned char *)source;
    if (d < s) {
        while (count-- != 0u) *d++ = *s++;
    } else if (d > s) {
        d += count;
        s += count;
        while (count-- != 0u) *--d = *--s;
    }
    return destination;
}

int memcmp(const void *left, const void *right, size_t count)
{
    const unsigned char *a = (const unsigned char *)left;
    const unsigned char *b = (const unsigned char *)right;
    while (count-- != 0u) {
        if (*a != *b) return (int)*a - (int)*b;
        ++a;
        ++b;
    }
    return 0;
}
