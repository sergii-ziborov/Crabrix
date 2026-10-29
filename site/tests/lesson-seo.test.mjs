import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { lessonDescription, lessonModifiedDates, searchDescription } from '../lib/lesson-seo.ts';
import { pageUrl } from '../lib/seo.ts';
const snapshot = JSON.parse(readFileSync(new URL('../content/courses.json', import.meta.url)));
test('all 754 lessons have readable unique search descriptions without code delimiters', () => {
  const descriptions = new Set();
  let count = 0;
  for (const course of snapshot.courses) for (const unit of course.units) for (const lesson of unit.lessons) {
    const description = lessonDescription(lesson);
    assert.ok(description.length > 25 && description.length <= 170, lesson.id);
    assert.ok(!description.includes('`'));
    assert.ok(!descriptions.has(description), lesson.id);
    descriptions.add(description); count++;
  }
  assert.equal(count, 754);
  assert.ok(!searchDescription('A '.repeat(100)).endsWith(' '));
  assert.equal(lessonModifiedDates['basics/strings'], '2026-10-20');
});

test('canonical URLs match Next trailing-slash handling for ordinary and dotted lesson IDs', () => {
  assert.equal(pageUrl('/'), 'https://crabrix.com/');
  assert.equal(pageUrl('/blog/rust-checked-arithmetic-conversions/'), 'https://crabrix.com/blog/rust-checked-arithmetic-conversions/');
  assert.equal(pageUrl('/learn/basics/strings'), 'https://crabrix.com/learn/basics/strings/');
  assert.equal(pageUrl('/learn/algorithms/algorithm.linear-scan.model/'), 'https://crabrix.com/learn/algorithms/algorithm.linear-scan.model');
  assert.equal(pageUrl('/learn/algorithms/algorithm.linear-scan.model?source=index'), 'https://crabrix.com/learn/algorithms/algorithm.linear-scan.model');
});
