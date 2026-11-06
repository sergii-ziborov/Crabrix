import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { safeReturnPath } from '../lib/return-path.ts';

const snapshot = JSON.parse(readFileSync(new URL('../content/courses.json', import.meta.url)));

test('every lesson path survives sign-in, including dotted Atlas IDs', () => {
  let count = 0;
  for (const course of snapshot.courses) for (const unit of course.units) for (const lesson of unit.lessons) {
    const path = `/learn/${course.id}/${lesson.id}/`;
    assert.equal(safeReturnPath(path), path);
    count++;
  }
  assert.equal(count, 774);
  assert.equal(safeReturnPath('/learn/'), '/learn/');
  assert.equal(safeReturnPath('/learn/algorithms'), '/learn/algorithms');
});

test('anything that could leave /learn/ falls back to /learn/', () => {
  for (const value of ['', '/', 'https://evil.example/', '//evil.example/', '/learn//evil.example/', '/learn/../account/', '/learn/./x/', '/learn/a/../../account/', '/learn/..%2f..%2faccount/',
    '/learn\\evil.example', '/learn/\\evil.example', '/learn/a?next=//evil.example', '/learn/a#x', '/learn/a\n/', '/learn/.hidden/', '/learn/a./', '/learn/a..b/', '/learn/A/', '/learnx/', ' /learn/', '/account/']) {
    assert.equal(safeReturnPath(value), '/learn/', JSON.stringify(value));
  }
});

test('lesson Playground return path is narrow and cannot carry a second query or an origin',()=>{
 assert.equal(safeReturnPath('/playground/?lesson=projects/serde-roundtrip-validation'),'/playground/?lesson=projects/serde-roundtrip-validation');
 for(const path of ['/playground/?lesson=projects/serde&next=//evil.test','//evil.test/playground/?lesson=a/b','/playground/?lesson=../secret','/playground/?lesson=a/b#secret','/playground/?lesson=a%2fb']) assert.equal(safeReturnPath(path),'/learn/');
});
