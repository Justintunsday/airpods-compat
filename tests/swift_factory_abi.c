#include <assert.h>
#include <stdint.h>
// A compiler/calling-convention contract, not a claim about private Swift ABI
// behavior on a physical iPhone. Native objects/witness tables are never faked.
#if defined(__APPLE__)
#include "../tweak/Platform/SwiftFeatureFactory.h"
static void *expectedDevice, *expectedContext, *expectedResult;
static __attribute__((swiftcall)) void *factory(uint32_t pid, void *device,
                                                void *context __attribute__((swift_context))) {
    assert(pid == 0x201b && device == expectedDevice && context == expectedContext);
    return expectedResult;
}
int main(void) {
    int device, context, result;
    expectedDevice = &device; expectedContext = &context; expectedResult = &result;
    ACFeatureFactory call = factory;
    assert(call(0x201b, &device, &context) == &result);
    return 0;
}
#else
int main(void) { return 0; } // Apple ABI check runs on macOS CI.
#endif
