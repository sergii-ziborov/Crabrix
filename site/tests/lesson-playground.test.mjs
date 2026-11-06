import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {lessonPlayground} from '../lib/lesson-playground.ts';
import {readCargoRoot} from '../lib/browser-cargo-manifest.ts';
const content=JSON.parse(readFileSync(new URL('../content/courses.json',import.meta.url)));
test('all eight qualified starters are bounded local projects and serialize as RSC plain objects',()=>{
 const lessons=content.courses.flatMap(c=>c.units.flatMap(u=>u.lessons)).filter(l=>l.playgroundProject);
 assert.equal(lessons.length,8);
 let preparedDependencies=0,manifestFree=0,featureOnly=0;
 for(const lesson of lessons){
  const project=lessonPlayground(lesson.playgroundProject);
  assert.equal(Object.getPrototypeOf(project),Object.prototype);assert.equal(Object.getPrototypeOf(project.files),Object.prototype);
  assert.equal(project.files[project.entryFile],lesson.writing.exampleCode);
  if (['public-api-compatibility','msrv-verification'].includes(lesson.id)) {
   assert.deepEqual(Object.keys(project.files),['main.rs']); assert.equal(project.edition,'2021'); manifestFree++;
  } else if (lesson.id==='feature-compatibility-matrix') {
   const cargo=readCargoRoot(project); assert.equal(cargo.dependencies.length,0);
   assert.deepEqual(cargo.enabled,['default','details','trace']); featureOnly++;
  } else {
   assert(project.files['Cargo.lock'].includes('checksum ='));
   assert(readCargoRoot(project).dependencies.length>0); preparedDependencies++;
  }
  assert.deepEqual(JSON.parse(JSON.stringify(project)),project);
 }
 assert.equal(preparedDependencies,5);assert.equal(manifestFree,2);assert.equal(featureOnly,1);
});
test('RSC conversion cannot bypass path validation',()=>{
 const lesson=content.courses.flatMap(c=>c.units.flatMap(u=>u.lessons)).find(l=>l.playgroundProject);
 assert.throws(()=>lessonPlayground({...lesson.playgroundProject,files:{...lesson.playgroundProject.files,'../escape.rs':'bad'}}));
});
