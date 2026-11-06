import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { lessonPreview, lessonWordCount } from '../lib/lesson-preview.ts';
const snapshot = JSON.parse(readFileSync(new URL('../content/courses.json', import.meta.url)));
test('all 774 previews withhold exercises and keep code markup balanced', () => {
  let count = 0;
  for (const course of snapshot.courses) for (const unit of course.units) for (const lesson of unit.lessons) {
    const preview = lessonPreview(lesson, course.id === 'basics');
    assert.equal(Object.keys(preview).sort().join(','), 'paragraphs,rule,summary');
    assert.ok(preview.paragraphs.length > 0, lesson.id);
    const content = [lesson.title, preview.summary, preview.rule, ...preview.paragraphs].join(' ');
    const words = content.trim().split(/\s+/).length;
    assert.ok(words <= Math.ceil(lessonWordCount(lesson, course.id === 'basics') * .30) + 2, `${lesson.id}: ${words}`);
    assert.equal((preview.paragraphs.join(' ').match(/`/g) || []).length % 2, 0, lesson.id);
    count++;
  }
  assert.equal(count, 774);
});

const lessons = snapshot.courses.flatMap(course => course.units.flatMap(unit => unit.lessons.map(lesson => ({ lesson, basics: course.id === 'basics' }))));
const count = text => text.trim().split(/\s+/).filter(Boolean).length;

test('no preview shows the whole explanation, including lessons whose budget is mostly code', () => {
  for (const { lesson, basics } of lessons) {
    const explanation = lesson.writing?.explanation || lesson.algorithm?.idea || '';
    const shown = lessonPreview(lesson, basics).paragraphs.join(' ');
    assert.ok(count(shown) <= count(explanation) * .6, `${lesson.id}: ${count(shown)} of ${count(explanation)}`);
  }
  for (const id of ['algorithm.lazy-segment-tree.challenge', 'algorithm.heavy-light.challenge']) assert.ok(lessons.some(({ lesson }) => lesson.id === id), id);
});

test('previews end on a real sentence, never on a macro name in a code span', () => {
  for (const { lesson, basics } of lessons) {
    const shown = lessonPreview(lesson, basics).paragraphs.join(' ').trim();
    assert.ok(!/!`$/.test(shown), `${lesson.id}: ${shown.slice(-40)}`);
    assert.match(shown, /[.!?]$/, lesson.id);
  }
  const lesson = { title: 'T', concept: 'C', writing: { summary: 'S', explanation: 'Alpha beta gamma delta epsilon with `dbg!` here now. Then `dbg!` one two three four five six seven eight.', exampleCode: Array(200).fill('code').join(' ') } };
  assert.deepEqual(lessonPreview(lesson).paragraphs, ['Alpha beta gamma delta epsilon with `dbg!` here now.']);
});

test('figure captions render inline code through prose()', () => {
  const page = readFileSync(new URL('../app/learn/[course]/[lesson]/page.tsx', import.meta.url), 'utf8');
  assert.equal(page.match(/<figcaption>\{prose\(lesson\.illustration\.caption\)\}<\/figcaption>/g)?.length, 2);
  assert.ok(!page.includes('<figcaption>{lesson.illustration.caption}'));
});

test('all 600 algorithm previews lead with their teaching stage, not the shared fixture preamble', () => {
  const anchors = { model: /^Begin with the concrete question:/, recognize: /^A problem is a good match for /, challenge: /^Solve the exact task,/ };
  const bodies = new Set();
  const course = snapshot.courses.find(course => course.id === 'algorithms');
  for (const unit of course.units) for (const lesson of unit.lessons) {
    const preview = lessonPreview(lesson);
    const body = preview.paragraphs.join(' ');
    assert.match(body, anchors[lesson.algorithm.stage], lesson.id);
    assert.ok(!bodies.has(body), lesson.id);
    bodies.add(body);
    assert.ok(!body.includes(lesson.writing.exampleCode));
  }
  assert.equal(bodies.size, 600);
});
