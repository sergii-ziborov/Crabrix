import { createHash } from 'node:crypto';
import type { AlgorithmTrace } from './algorithm-trace-types';
import { lessonPlayground } from './lesson-playground.ts';

/** A personal experiment starts from the verified recording, never its practice stub. */
export function algorithmPlayground(trace: AlgorithmTrace, lessonID: string) {
  if (!/^[a-z0-9-]+$/.test(trace.pattern) ||
      !['model', 'recognize', 'challenge'].some(stage => lessonID === `algorithm.${trace.pattern}.${stage}`) ||
      createHash('sha256').update(trace.source).digest('hex') !== trace.sourceHash) {
    throw new Error('The algorithm example does not match its recording.');
  }
  return lessonPlayground({
    schemaVersion: 1, name: Array.from(`Atlas · ${trace.title}`).slice(0, 80).join(''),
    entryFile: 'src/main.rs', edition: '2024', files: {
      'Cargo.toml': '[package]\nname = "atlas_example"\nversion = "0.1.0"\nedition = "2024"\n\n[dependencies]\n',
      'src/main.rs': trace.source,
      'README.md': `# Algorithm experiment\n\nOriginal lesson: https://crabrix.com/learn/algorithms/${lessonID}/\n\nOriginal source SHA-256: ${trace.sourceHash}\n\nThis personal copy starts with the recorded example and its original input. Change the code, then use Run or Debug locally. The lesson recording and your Academy progress remain unchanged. Recordings use a native Rust target; Playground runs on wasm32-wasip1, where target-sized types such as usize can have different limits.\n\n## Reference input\n\n${trace.input}\n\n## Original standard output\n\n${trace.stdout}\n`,
    },
  });
}
