import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { lessonPreview, lessonWordCount } from '../lib/lesson-preview.ts';
const snapshot = JSON.parse(readFileSync(new URL('../content/courses.json', import.meta.url)));
test('all 742 previews withhold exercises and keep code markup balanced', () => {
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
  assert.equal(count, 742);
});
