import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { practiceCopy, practiceProgram, practiceNotice } from '../lib/practice-copy.ts';
import { ACADEMY_EVENTS, academyEventKey } from '../lib/academy-event-names.ts';

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const snapshot = JSON.parse(read('../content/courses.json'));
const starters = JSON.parse(read('../content/academy-practice-starters.json'));
const schema = JSON.parse(read('../content/academy-learning-state.schema.json'));
const lessons = new Map(snapshot.courses.flatMap(course => course.units.flatMap(unit => unit.lessons.map(lesson => [`${course.id}/${lesson.id}`, lesson]))));
const sha = text => createHash('sha256').update(text, 'utf8').digest('hex');

test('every qualified practice copy opens with the lesson text unchanged', () => {
  assert.equal(starters.schemaVersion, 1);
  assert.ok(starters.starters.length >= 150, `${starters.starters.length} starters`);
  for (const starter of starters.starters) {
    const lesson = lessons.get(`${starter.courseId}/${starter.lessonId}`);
    assert.ok(lesson, `${starter.courseId}/${starter.lessonId} is published`);
    assert.ok(!lesson.playgroundProject, 'lessons with their own project keep it');
    assert.notEqual(starter.courseId, 'algorithms');
    const document = practiceCopy(lesson, starter);
    assert.ok(document, `${starter.courseId}/${starter.lessonId} copy`);
    assert.deepEqual(Object.keys(document.files), ['main.rs']);
    assert.equal(document.entryFile, 'main.rs');
    const program = document.files['main.rs'];
    assert.equal(sha(program), starter.programSha256);
    const code = lesson.writing[starter.source];
    if (starter.wrap === 'in-main') assert.equal(program.split('\n').slice(1, -2).map(line => line.slice(line ? 4 : 0)).join('\n'), code.trimEnd());
    else assert.ok(program.startsWith(code.trimEnd()));
  }
});

test('a changed lesson never opens a stale practice copy', () => {
  const starter = starters.starters[0];
  const lesson = structuredClone(lessons.get(`${starter.courseId}/${starter.lessonId}`));
  assert.ok(practiceCopy(lesson, starter));
  lesson.writing[starter.source] += '\n// edited';
  assert.equal(practiceCopy(lesson, starter), undefined);
  assert.equal(practiceCopy(lesson, undefined), undefined);
  assert.equal(practiceCopy({ id: 'other', writing: lesson.writing }, starter), undefined);
});

test('wrapping matches crabrix-courses tools/practice_starters.py', () => {
  assert.equal(practiceProgram('struct A;', 'main-added'), 'struct A;\n\nfn main() {}\n');
  assert.equal(practiceProgram('let x = 1;\n\nprintln!("{x}");\n', 'in-main'), 'fn main() {\n    let x = 1;\n\n    println!("{x}");\n}\n');
  assert.equal(practiceProgram('fn main() {}', null), 'fn main() {}');
  assert.match(practiceNotice({ check: 'fails-by-design', wrap: null }), /does not compile yet/);
  for (const wrap of [null, 'main-added', 'in-main']) assert.match(practiceNotice({ check: 'compiles', wrap }), /saved drafts are not changed/);
});

test('only fixed event names and details are counted', () => {
  assert.deepEqual(academyEventKey('with_ai_opened'), { event: 'with_ai_opened', detail: '' });
  assert.deepEqual(academyEventKey('client_selected', 'codex'), { event: 'client_selected', detail: 'codex' });
  assert.equal(academyEventKey('client_selected', 'evil'), undefined);
  assert.equal(academyEventKey('client_selected'), undefined);
  assert.equal(academyEventKey('with_ai_opened', 'x'), undefined);
  assert.equal(academyEventKey('toString'), undefined);
  assert.equal(academyEventKey('__proto__'), undefined);
  assert.equal(academyEventKey({ event: 'x' }), undefined);
  assert.deepEqual(Object.keys(ACADEMY_EVENTS).sort(), ['client_selected', 'feedback_answered', 'first_run_from_ai', 'instructions_copied',
    'lesson_opened_from_ai', 'playground_opened_from_ai', 'prompt_copied', 'returned_to_learning', 'with_ai_opened']);
});

test('the event endpoint stores counters only and the browser respects privacy signals', () => {
  const route = read('../app/api/academy/v1/events/route.ts'), store = read('../lib/academy-events.ts'), client = read('../lib/academy-events-client.ts');
  assert.doesNotMatch(route + store, /cookies\(|headers\.get\(["'](cookie|x-forwarded-for|user-agent|x-real-ip)/i);
  assert.match(store, /day TEXT NOT NULL, event TEXT NOT NULL, detail TEXT NOT NULL, count INTEGER NOT NULL/);
  assert.match(store, /400 \* 86_400_000/);
  assert.match(client, /credentials: "omit"/);
  assert.match(client, /globalPrivacyControl/);
  assert.match(client, /doNotTrack/);
  assert.doesNotMatch(read('../components/ai-learning-client.tsx'), /fetch\(/, 'feedback text never leaves the browser except as an email draft');
});

test('switches turn off only the new feature', async () => {
  const route = read('../app/api/academy/v1/[...path]/route.ts');
  assert.match(route, /status\.json[\s\S]*academyApiEnabled\(\)\) return failure\(503/);
  assert.match(read('../app/learn/with-ai/page.tsx'), /if \(!aiLearningEnabled\(\)\) notFound\(\)/);
  assert.match(read('../app/learn/page.tsx'), /aiLearningEnabled\(\) && <section className="with-ai-entry"/);
  assert.match(read('../app/sitemap.ts'), /aiLearningEnabled\(\) \? \["learn\/with-ai"\]/);
  process.env.CRABRIX_AI_LEARNING = 'off'; process.env.CRABRIX_ACADEMY_MCP_STATE = 'paused';
  const flags = await import('../lib/flags.ts');
  assert.equal(flags.aiLearningEnabled(), false);
  assert.equal(flags.academyApiEnabled(), true);
  assert.equal(flags.academyMcpState(), 'paused');
  process.env.CRABRIX_AI_LEARNING = 'on'; delete process.env.CRABRIX_ACADEMY_MCP_STATE;
  assert.equal(flags.aiLearningEnabled(), true);
  assert.equal(flags.academyMcpState(), 'on');
  for (const file of ['../app/playground/page.tsx', '../components/playground/workspace.tsx']) assert.doesNotMatch(read(file), /academyApiEnabled|CRABRIX_AI_LEARNING/);
});

test('every Examples project opens as a copy and keeps its files unchanged', () => {
  const examples = JSON.parse(read('../content/academy-examples.json')).examples;
  const page = read('../app/playground/page.tsx'), academy = read('../lib/academy.ts');
  assert.match(page, /examplePlaygroundDocument\(example\)/);
  assert.match(page, /The original Example and your saved drafts are not changed/);
  assert.match(academy, /kind: "example-copy"/);
  for (const example of examples) {
    assert.ok(Object.keys(example.files).length <= 16 && example.files[example.entryFile], example.id);
    assert.doesNotMatch(example.files['Cargo.toml'] ?? '', /\[dependencies\]\s*\n\s*[a-z]/, `${example.id} is std-only`);
    assert.match(example.id, /^[a-z0-9][a-z0-9-]{0,79}$/);
  }
  assert.ok(ACADEMY_EVENTS.playground_opened_from_ai.includes('example-copy'));
});

test('the AI Learning State schema is v1 and published by the API', () => {
  assert.equal(schema.properties.format.const, 'crabrix.ai-learning-state');
  assert.equal(schema.properties.schemaVersion.const, 1);
  assert.match(read('../app/api/academy/v1/[...path]/route.ts'), /learning-state\.schema\.json/);
  for (const key of lessons.keys()) assert.match(key.split('/')[1], new RegExp(schema.$defs.id.pattern));
});

test('the privacy policy describes the counters and the app screen', () => {
  const policy = read('../privacy.html');
  assert.match(policy, /id="learn-with-ai"/);
  assert.match(policy, /deleted after 400 days/);
  assert.match(policy, /Global Privacy Control or Do Not Track/);
  assert.match(policy, /status\.json/);
});
