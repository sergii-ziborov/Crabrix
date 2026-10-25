#ifndef CRABRIX_NATIVE_COMPILER_API_H
#define CRABRIX_NATIVE_COMPILER_API_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct CrabrixNativeCompiler CrabrixNativeCompiler;
typedef int32_t (*CrabrixNativeHostCall)(void*, const char*, const char*, const uint64_t*, uint32_t, uint64_t*);
typedef int32_t (*CrabrixNativePoll)(void*);
// Each guarded entry returns a Wasm trap, zero on success, or -1 when busy.
// A callback reports errors by returning; no nonlocal jump crosses Swift.
const char* crabrix_native_compiler_source_sha256(void);
CrabrixNativeCompiler* crabrix_native_compiler_create(void*, CrabrixNativeHostCall, CrabrixNativePoll);
int32_t crabrix_native_compiler_run(CrabrixNativeCompiler*, uint64_t);
// 1=alloc, 2=free, 3=dispatch; all calls have an independent C trap scope.
int32_t crabrix_native_compiler_export(CrabrixNativeCompiler*, uint32_t, uint32_t, uint32_t, uint64_t*);
uint8_t* crabrix_native_compiler_memory(CrabrixNativeCompiler*);
uint64_t crabrix_native_compiler_memory_size(CrabrixNativeCompiler*);
uint64_t crabrix_native_compiler_remaining_work(CrabrixNativeCompiler*);
int32_t crabrix_native_compiler_reduce_work(CrabrixNativeCompiler*, uint64_t);
void crabrix_native_compiler_free(CrabrixNativeCompiler*);
#ifdef __cplusplus
}
#endif
#endif
