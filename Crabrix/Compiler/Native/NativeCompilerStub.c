#include "NativeCompilerAPI.h"
#include <stddef.h>
#include <TargetConditionals.h>
#if (TARGET_OS_SIMULATOR && !defined(CRABRIX_NATIVE_COMPILER_SIMULATOR)) || defined(CRABRIX_NATIVE_COMPILER_BUILD_STUB)
const char* crabrix_native_compiler_source_sha256(void) { return ""; }
CrabrixNativeCompiler* crabrix_native_compiler_create(void* c, CrabrixNativeHostCall h, CrabrixNativePoll p) { return NULL; }
int32_t crabrix_native_compiler_run(CrabrixNativeCompiler* c, uint64_t b) { return -2; }
int32_t crabrix_native_compiler_export(CrabrixNativeCompiler* c, uint32_t k, uint32_t a, uint32_t b, uint64_t* r) { return -2; }
uint8_t* crabrix_native_compiler_memory(CrabrixNativeCompiler* c) { return NULL; }
uint64_t crabrix_native_compiler_memory_size(CrabrixNativeCompiler* c) { return 0; }
uint64_t crabrix_native_compiler_remaining_work(CrabrixNativeCompiler* c) { return 0; }
int32_t crabrix_native_compiler_reduce_work(CrabrixNativeCompiler* c, uint64_t r) { return -2; }
void crabrix_native_compiler_free(CrabrixNativeCompiler* c) {}
#endif
