#pragma once
#include <stdint.h>
// Swift Array is one native word. The static metatype travels in swiftself.
typedef __attribute__((swiftcall)) void *(*ACFeatureFactory)(
    uint32_t, void *, void * __attribute__((swift_context)));
