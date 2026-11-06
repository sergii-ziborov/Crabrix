import {test} from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
const dimensions=url=>{
 const data=readFileSync(url);
 if(data.subarray(0,8).toString('hex')==='89504e470d0a1a0a'){assert(url.pathname.endsWith('.png'));return [data.readUInt32BE(16),data.readUInt32BE(20)];}
 assert.equal(data.readUInt16BE(0),0xffd8);assert(/\.jpe?g$/.test(url.pathname));
 for(let at=2;at+9<data.length;){
  assert.equal(data[at],0xff);const marker=data[at+1],length=data.readUInt16BE(at+2);
  if([0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf].includes(marker))return [data.readUInt16BE(at+7),data.readUInt16BE(at+5)];
  assert(length>=2);at+=length+2;
 }
 throw new Error('JPEG dimensions not found');
};
test('all article images reserve their true intrinsic size before loading',()=>{
 const posts=JSON.parse(readFileSync(new URL('../content/posts.json',import.meta.url)));let count=0;
 for(const post of posts)for(const section of post.sections)if(section.image){const image=section.image;assert.deepEqual([image.width,image.height],dimensions(new URL('../public'+image.src,import.meta.url)),image.src);count++;}
 assert.equal(count,93);
});
test('all 774 lesson infographics retain their true intrinsic dimensions',()=>{
 const courses=JSON.parse(readFileSync(new URL('../content/courses.json',import.meta.url)));let count=0;
 for(const course of courses.courses)for(const unit of course.units)for(const lesson of unit.lessons){const image=lesson.illustration;assert.deepEqual([image.width,image.height],dimensions(new URL('../content/learn-media/'+course.id+'/'+image.path.slice(6),import.meta.url)),lesson.id);count++;}
 assert.equal(count,774);
});
