const related: Record<string, readonly string[]> = {
  'projects/public-api-compatibility': ['testing-rust-boundaries-fixtures-doctests'],
  'projects/msrv-verification': ['rust-1-99-1-patch-regression-testing'],
  'projects/feature-compatibility-matrix': ['cargo-features-portable-dependencies'],
  'projects/serde-roundtrip-validation': ['rust-serde-json-validation-boundaries'],
  'concurrency/async-runtime': ['rust-async-cancellation-safe-timeouts'],
  'concurrency/joinset-task-ownership': ['rust-async-cancellation-safe-timeouts'],
  'concurrency/semaphore-backpressure': ['rust-async-cancellation-safe-timeouts'],
  'concurrency/graceful-shutdown-protocol': ['rust-async-cancellation-safe-timeouts'],
};
export const lessonRelatedPosts = (course: string, lesson: string): readonly string[] => related[`${course}/${lesson}`] ?? [];
