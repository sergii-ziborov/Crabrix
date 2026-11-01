import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { valueText } from '../lib/algorithm-trace-types.ts';
import { isAdjacencyList, linkedTree } from '../lib/algorithm-state-model.ts';

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

const framesOf = (lesson, name) => { const trace = read(manifest.lessons[lesson]); return trace.frames.flatMap(frame => frame.locals.filter(([local]) => local === name).map(([, ref]) => trace.values[ref].data)); };

test('only real adjacency lists draw as graphs', () => {
  const list = items => ({ kind: 'list', items });
  const dinic = framesOf('algorithm.dinic-max-flow.model', 'g').filter(value => value.kind === 'list');
  const grid = framesOf('algorithm.word-grid-search.model', 'g').filter(value => value.kind === 'list');
  assert.ok(dinic.length && grid.length);
  assert.ok(dinic.every(value => !isAdjacencyList(value)));
  assert.ok(grid.every(value => !isAdjacencyList(value)));
  const dijkstra = framesOf('algorithm.dijkstra.model', 'graph').filter(value => value.kind === 'list');
  assert.ok(dijkstra.length && dijkstra.every(isAdjacencyList));
  assert.equal(isAdjacencyList(list([list([]), list([])])), true);
  assert.equal(isAdjacencyList(list([list([{ kind: 'scalar', text: '2' }]), list([])])), false);
});

test('linked structures are drawn to their full length', () => {
  const lengths = framesOf('algorithm.reverse-k-group.model', 'head').map(value => { let n = 0; for (let node = linkedTree(value); node; node = node.children[0]?.node) n++; return n; });
  assert.equal(Math.max(...lengths), 7);
  const scalar = text => ({ kind: 'scalar', text });
  const none = { kind: 'named', name: 'None', value: { kind: 'list', items: [] } };
  let tail = none;
  for (let i = 40; i > 0; i--) tail = { kind: 'named', name: 'Some', value: { kind: 'list', items: [{ kind: 'named', name: 'Box', value: { kind: 'map', entries: [[scalar('val'), scalar(String(i))], [scalar('next'), tail]] } }] } };
  let n = 0;
  for (let node = linkedTree(tail); node; node = node.children[0]?.node) n++;
  assert.equal(n, 40);
});

test('the source image keeps the one test its build script gates on', () => {
  const ignore = readFileSync(new URL('../.dockerignore', import.meta.url), 'utf8').split('\n');
  const build = JSON.parse(readFileSync(new URL('../package.json', import.meta.url))).scripts.build;
  assert.ok(build.includes('tests/algorithm-traces.test.mjs'));
  assert.ok(ignore.indexOf('!tests/algorithm-traces.test.mjs') > ignore.indexOf('tests'));
});
