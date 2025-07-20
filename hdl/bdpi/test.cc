#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint64_t c_test_f() {
    return 0xAAAAAAAAAAAAAAAA;
}

uint64_t c_test(uint32_t v) {
    return (uint64_t) 0xCAFEAFFE << 32 | v;
}

#ifdef __cplusplus
}
#endif