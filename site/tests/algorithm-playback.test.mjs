import test from 'node:test';
import assert from 'node:assert/strict';
import {previousFrameIndices,collectionChanges,atlasValueKey} from '../lib/algorithm-playback.ts';
const scalar=text=>({kind:'scalar',text});
test('rewind compares the same call after nested and recursive activations',()=>{
  const frame=stack=>({site:0,locals:[],stack:stack.map(id=>['call',id])});
  assert.deepEqual(previousFrameIndices([[1],[1,2],[1,2],[1],[1,3],[1,3,4],[1,3],[1]].map(frame)),[undefined,undefined,1,0,undefined,undefined,4,3]);
});
test('maps distinguish inserted, changed and removed keys without flagging reordered entries',()=>{
  const before={kind:'map',entries:[[scalar('a'),scalar('1')],[scalar('b'),scalar('2')],[scalar('gone'),scalar('0')]]};
  const after={kind:'map',entries:[[scalar('b'),scalar('3')],[scalar('new'),scalar('4')],[scalar('a'),scalar('1')]]};
  const diff=collectionChanges(after,before);
  assert.deepEqual([...diff.added],[atlasValueKey(scalar('new'))]);
  assert.deepEqual([...diff.updated],[atlasValueKey(scalar('b'))]);
  assert.deepEqual(diff.removed,[{key:scalar('gone'),value:scalar('0')}]);
  assert.equal(collectionChanges(after).added.size,0,'first capture has no previous state');
});
test('set changes follow membership rather than unstable display positions',()=>{
  const before={kind:'set',items:[scalar('1'),scalar('2')]},after={kind:'set',items:[scalar('2'),scalar('3')]};
  const diff=collectionChanges(after,before);
  assert.deepEqual([...diff.added],[atlasValueKey(scalar('3'))]);assert.deepEqual(diff.removed,[{key:scalar('1')}]);
  assert.equal(atlasValueKey(before),atlasValueKey({kind:'set',items:[scalar('2'),scalar('1')]}));
  assert.notEqual(atlasValueKey(scalar('[1]')),atlasValueKey({kind:'list',items:[scalar('1')]}));
});
