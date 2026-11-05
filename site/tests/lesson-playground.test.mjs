import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {lessonPlayground} from '../lib/lesson-playground.ts';
import {readCargoRoot} from '../lib/browser-cargo-manifest.ts';
const content=JSON.parse(readFileSync(new URL('../content/courses.json',import.meta.url)));
test('all five qualified starters are bounded valid Cargo projects and serialize as RSC plain objects',()=>{
 const lessons=content.courses.flatMap(c=>c.units.flatMap(u=>u.lessons)).filter(l=>l.playgroundProject);
 assert.equal(lessons.length,5);
 for(const lesson of lessons){
  const project=lessonPlayground(lesson.playgroundProject);
  assert.equal(Object.getPrototypeOf(project),Object.prototype);assert.equal(Object.getPrototypeOf(project.files),Object.prototype);
  assert.equal(project.files[project.entryFile],lesson.writing.exampleCode);
  assert(project.files['Cargo.lock'].includes('checksum ='));
  assert(readCargoRoot(project).dependencies.length>0);
  assert.deepEqual(JSON.parse(JSON.stringify(project)),project);
 }
});
test('RSC conversion cannot bypass path validation',()=>{
 const lesson=content.courses.flatMap(c=>c.units.flatMap(u=>u.lessons)).find(l=>l.playgroundProject);
 assert.throws(()=>lessonPlayground({...lesson.playgroundProject,files:{...lesson.playgroundProject.files,'../escape.rs':'bad'}}));
});
