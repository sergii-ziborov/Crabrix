import { test } from 'node:test';
import assert from 'node:assert/strict';
import { blogPage, blogPagePath, parseBlogPage } from '../lib/blog-pagination.ts';

test('the archive reaches every article once, in order, across partial and full pages', () => {
  for (const count of [0, 1, 12, 13, 24, 32, 36, 37]) {
    const posts = Array.from({ length: count }, (_, id) => ({ id }));
    const first = blogPage(posts, 1);
    const pages = Array.from({ length: first.pageCount }, (_, index) => blogPage(posts, index + 1));
    assert.deepEqual(pages.flatMap(page => page.posts), posts);
    assert.equal(pages.at(-1).end, count);
    assert.ok(pages.every(page => page.posts.length <= 12));
    assert.equal(blogPage(posts, first.pageCount + 1), undefined);
    assert.equal(blogPagePath(1), '/blog/');
    assert.equal(blogPagePath(2), '/blog/page/2/');
  }
});

test('invalid page IDs cannot alias a valid archive or create a soft 404', () => {
  for (const value of ['0', '-1', '01', '2.0', '2e0', '+2', ' 2', '2 ', 'NaN', 'Infinity', '9007199254740992', '999999999999999999999']) {
    assert.equal(parseBlogPage(value), undefined, value);
  }
  assert.equal(parseBlogPage('1'), 1);
  assert.equal(parseBlogPage('3'), 3);
  for (const value of [0, -1, 1.5, NaN, Infinity]) assert.equal(blogPage([1], value), undefined);
});
