import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { valueText } from '../lib/algorithm-trace-types.ts';

const root = new URL('../content/algorithm-traces/', import.meta.url);
const manifest = JSON.parse(readFileSync(new URL('manifest.json', root)));
const read = key => JSON.parse(readFileSync(new URL(`${key}.json`, root)));
const snapshot = JSON.parse(readFileSync(new URL('../content/courses.json', import.meta.url)));
const lessons = snapshot.courses.find(c => c.id === 'algorithms').units.flatMap(u => u.lessons);

test('all 600 algorithm lessons replay their own exact example, including independent challenge fixtures', () => {
  const keys = new Set(), patterns = new Set();
  assert.equal(lessons.length, 600);
  for (const lesson of lessons) {
    const key = manifest.lessons[lesson.id], trace = read(key);
    assert.equal(trace.pattern, lesson.algorithm.patternID, lesson.id);
    assert.equal(trace.source, lesson.writing.exampleCode, lesson.id);
    assert.equal(trace.sourceHash, createHash('sha256').update(lesson.writing.exampleCode).digest('hex'), lesson.id);
    assert.equal(trace.verification.stdoutMatchesOriginal, true, key);
    assert.equal(trace.verification.independentOracle, true, key);
    assert.ok(trace.input.length > 0, key);
    keys.add(key); patterns.add(trace.pattern);
  }
  assert.equal(keys.size, 400); assert.equal(patterns.size, 200);
  assert.equal(Object.keys(manifest.lessons).length, 600);
  assert.equal(manifest.keys.length, 401);
});

test('execution frames, values, call stacks and source locations are complete and bounded', () => {
  for (const key of manifest.keys) {
    const trace = read(key), lines = trace.source.split('\n').length;
    assert.ok(trace.frames.length >= 2 && trace.frames.length <= 50000, key);
    for (const frame of trace.frames) {
      const site = trace.sites[frame.site];
      assert.ok(site && site.line >= 1 && site.line <= lines, key);
      assert.ok(frame.stack.length > 0, key);
      assert.equal(site.function, frame.stack.at(-1)[0], key);
      assert.equal(new Set(frame.locals.map(([name]) => name)).size, frame.locals.length, key);
      for (const [name, ref] of frame.locals) {
        assert.ok(name && trace.values[ref], key);
        assert.equal(typeof valueText(trace.values[ref].data), 'string', key);
      }
    }
    assert.ok(Buffer.byteLength(JSON.stringify(trace)) < 2 * 1024 * 1024, key);
  }
});

test('demo is separate from the gated lesson, and closure algorithms expose their accumulator', () => {
  const demo = read('demo-linear-scan');
  assert.equal(demo.stdout, '3\n');
  assert.equal(demo.input, '[6, 2, 8, -1, 4]');
  assert.ok(!lessons.some(l => l.writing.exampleCode === demo.source));
  const xor = read(manifest.lessons['algorithm.xor-cancellation.model']);
  const acc = xor.frames.flatMap(f => f.locals.filter(([n]) => n === 'acc').map(([, ref]) => valueText(xor.values[ref].data)));
  assert.ok(new Set(acc).size >= 3, 'fold must have actual per-iteration states');
  const membership = read(manifest.lessons['algorithm.hash-membership.model']);
  assert.ok(membership.frames.some(f => f.stack.at(-1)[0].startsWith('closure') && f.locals.some(([name, ref]) => name === 'seen' && membership.values[ref].data.kind === 'set' && membership.values[ref].data.items.length >= 2)), 'closures expose their changing captured set too');
  assert.equal(valueText({ kind: 'scalar', text: '18446744073709551615' }), '18446744073709551615');
});
