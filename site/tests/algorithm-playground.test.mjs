import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {algorithmPlayground} from '../lib/algorithm-playground.ts';
import {readCargoRoot} from '../lib/browser-cargo-manifest.ts';

const content=JSON.parse(readFileSync(new URL('../content/courses.json',import.meta.url)));
const manifest=JSON.parse(readFileSync(new URL('../content/algorithm-traces/manifest.json',import.meta.url)));
const lessons=content.courses.find(c=>c.id==='algorithms').units.flatMap(u=>u.lessons);
test('all 600 Atlas stages open independent editable copies of their exact recorded example',()=>{
  assert.equal(lessons.length,600);
  for(const lesson of lessons){
    const trace=JSON.parse(readFileSync(new URL(`../content/algorithm-traces/${manifest.lessons[lesson.id]}.json`,import.meta.url)));
    const copy=algorithmPlayground(trace,lesson.id);
    assert.equal(copy.files[copy.entryFile],lesson.writing.exampleCode,lesson.id);
    assert.equal(copy.files[copy.entryFile],trace.source,lesson.id);
    assert.equal(copy.edition,'2024');assert.equal(Object.getPrototypeOf(copy.files),Object.prototype);
    assert.deepEqual(readCargoRoot(copy).dependencies,[]);
    assert.ok(copy.files['README.md'].includes(trace.sourceHash));
    assert.ok(copy.files['README.md'].includes(`/algorithms/${lesson.id}/`));
    copy.files[copy.entryFile]+='\n// learner experiment';
    assert.equal(trace.source,lesson.writing.exampleCode,'editing the copy cannot change the replay');
    assert.deepEqual(JSON.parse(JSON.stringify(copy)),copy);
  }
});
test('changed source, mismatched lesson identity and arbitrary paths cannot enter the experiment route',()=>{
  const lesson=lessons[0],trace=JSON.parse(readFileSync(new URL(`../content/algorithm-traces/${manifest.lessons[lesson.id]}.json`,import.meta.url)));
  assert.throws(()=>algorithmPlayground({...trace,source:trace.source+'\n// changed'},lesson.id));
  for(const id of ['../escape','algorithm.another.model',`${lesson.id}/../../file`])assert.throws(()=>algorithmPlayground(trace,id));
});
