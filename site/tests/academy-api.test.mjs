import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { learningPrompts, lessonPrompt, ACADEMY_MCP_URL } from '../lib/ai-learning.ts';

const snapshot = JSON.parse(readFileSync(new URL('../content/courses.json', import.meta.url)));
const paths = JSON.parse(readFileSync(new URL('../content/academy-paths.json', import.meta.url)));
const examples = JSON.parse(readFileSync(new URL('../content/academy-examples.json', import.meta.url)));
const contract = readFileSync(new URL('../content/academy-teaching-contract.md', import.meta.url), 'utf8');
const route = readFileSync(new URL('../app/api/academy/v1/[...path]/route.ts', import.meta.url), 'utf8');
const academy = readFileSync(new URL('../lib/academy.ts', import.meta.url), 'utf8');
const lessons = new Set(snapshot.courses.flatMap(course => course.units.flatMap(unit => unit.lessons.map(lesson => `${course.id}/${lesson.id}`))));

test('learning paths only reference published lessons', () => {
  assert.equal(paths.schemaVersion, 1);
  assert.equal(paths.paths.length, 8);
  for (const path of paths.paths) for (const step of path.steps) assert.ok(lessons.has(`${step.courseId}/${step.lessonId}`), `${path.id}: ${step.courseId}/${step.lessonId}`);
});

test('the Examples library and the teaching contract are synced', () => {
  assert.equal(examples.examples.length, 46);
  for (const example of examples.examples) assert.ok(example.files[example.entryFile], example.id);
  assert.match(contract, /Version \d+\.\d+\.\d+/);
});

test('the API never reads accounts, cookies or progress, and drops non-public lesson fields', () => {
  assert.doesNotMatch(route + academy, /cookies\(|auth-store|headers\(\)\.get\(["']cookie/);
  assert.match(academy, /playgroundProject: _project, resources: _resources/);
  assert.match(route, /Access-Control-Allow-Origin/);
});

test('copy prompts carry only public lesson context', () => {
  assert.equal(learningPrompts.length, 4);
  assert.equal(ACADEMY_MCP_URL, 'https://crabrix.com/mcp/academy');
  const prompt = lessonPrompt({ courseId: 'basics', lessonId: 'what-is-rust', title: 'What Rust Is', goal: 'Rust is `compiled`.',
    url: 'https://crabrix.com/learn/basics/what-is-rust/' });
  assert.match(prompt, /courseId "basics", lessonId "what-is-rust"/);
  assert.doesNotMatch(prompt, /`/);
  assert.match(prompt, /do not mark anything as passed/);
});
