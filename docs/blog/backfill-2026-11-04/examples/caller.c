#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
extern bool crabrix_is_even(uint32_t value);
int main(void) {
    volatile uint32_t values[] = {0, 1, 2, UINT32_MAX};
    assert(crabrix_is_even(values[0]) == true);
    assert(crabrix_is_even(values[1]) == false);
    assert(crabrix_is_even(values[2]) == true);
    assert(crabrix_is_even(values[3]) == false);
    puts("C/Rust ABI smoke: all checks passed");
    return 0;
}
