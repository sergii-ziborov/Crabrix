import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { algorithmMethodGuides, algorithmGuideSources } from '../lib/algorithm-method-guides.ts';

const snapshot = JSON.parse(readFileSync(new URL('../content/courses.json', import.meta.url)));
const atlas = snapshot.courses.find(course => course.id === 'algorithms');

test('every existing method has a distinct public choice, counterexample check and Rust representation guide', () => {
  assert.deepEqual(Object.keys(algorithmMethodGuides).sort(), atlas.units.map(unit => unit.id).sort());
  const text = new Set();
  for (const unit of atlas.units) {
    const guide = algorithmMethodGuides[unit.id];
    assert.ok(guide.choose.split(/\s+/).length >= 45, unit.id);
    for (const paragraph of Object.values(guide)) {
      assert.ok(paragraph.length > 100, unit.id);
      assert.ok(!text.has(paragraph), unit.id);
      text.add(paragraph);
    }
    // The public stage navigation must stay inside its actual pattern.
    const patterns = new Map();
    for (const lesson of unit.lessons) {
      const id = lesson.algorithm.patternID;
      patterns.set(id, [...(patterns.get(id) || []), lesson.algorithm.stage]);
    }
    assert.equal(patterns.size, 10);
    for (const stages of patterns.values()) assert.deepEqual(stages, ['model', 'recognize', 'challenge']);
  }
  assert.equal(algorithmGuideSources.length, 3);
  assert.ok(algorithmGuideSources.every(source => source.url.startsWith('https://')));
});
