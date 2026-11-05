import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {postPublicationDate,postModificationDate} from '../lib/post-dates.ts';
test('backfilled editorial dates do not replace actual publication in search metadata',()=>{
 const post={date:'2026-10-30',publishedDate:'2026-11-04'};
 assert.equal(postPublicationDate(post),'2026-11-04');assert.equal(postModificationDate(post),'2026-11-04');
 assert.equal(postModificationDate({...post,modifiedDate:'2026-11-05'}),'2026-11-05');
});
test('all article dates and contextual Academy links remain valid',()=>{
 const posts=JSON.parse(readFileSync(new URL('../content/posts.json',import.meta.url)));
 const courses=JSON.parse(readFileSync(new URL('../content/courses.json',import.meta.url)));
 const lessons=new Set(courses.courses.flatMap(c=>c.units.flatMap(u=>u.lessons.map(l=>`/learn/${c.id}/${l.id}/`))));
 for(const post of posts){
  const published=postPublicationDate(post),modified=postModificationDate(post);
  assert.match(published,/^\d{4}-\d{2}-\d{2}$/);assert.match(modified,/^\d{4}-\d{2}-\d{2}$/);assert(modified>=published,post.slug);
  for(const section of post.sections)for(const link of section.links??[])if(/^\/learn\/[^/]+\/[^/]+\/$/.test(link.url))assert(lessons.has(link.url),post.slug+' '+link.url);
 }
});
test('qualified lessons and articles have reciprocal contextual links',async()=>{
 const {lessonRelatedPosts}=await import('../lib/lesson-related-posts.ts');
 const posts=JSON.parse(readFileSync(new URL('../content/posts.json',import.meta.url)));
 const courses=JSON.parse(readFileSync(new URL('../content/courses.json',import.meta.url)));
 for(const course of courses.courses)for(const unit of course.units)for(const lesson of unit.lessons)if(lesson.playgroundProject){
  const slugs=lessonRelatedPosts(course.id,lesson.id);assert(slugs.length>0,lesson.id);
  for(const slug of slugs){const post=posts.find(p=>p.slug===slug);assert(post);assert(post.sections.some(section=>section.links?.some(link=>link.url===`/learn/${course.id}/${lesson.id}/`)),slug+' does not link back');}
 }
});
