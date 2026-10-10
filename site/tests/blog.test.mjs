import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const posts = JSON.parse(readFileSync(new URL('../content/posts.json', import.meta.url)));
test('three new Rust articles meet the requested length and image count', () => {
  const images = new Set();
  for (const slug of ['rust-1-99-upgrade', 'ownership-in-a-real-program', 'result-errors-that-help']) {
    const post = posts.find(p => p.slug === slug);
    assert.ok(post);
    assert.ok(post.sections.flatMap(s => s.paragraphs).join(' ').split(/\s+/).length >= 1500, slug);
    const illustrations = post.sections.filter(s => s.image).map(s => s.image);
    assert.equal(illustrations.length, 2);
    assert.ok(illustrations.some(image => image.src.endsWith('-infographic.png')));
    for (const image of illustrations) {
      assert.ok(image.alt && image.caption);
      const bytes = readFileSync(new URL('../public' + image.src, import.meta.url));
      images.add(createHash('sha256').update(bytes).digest('hex'));
    }
  }
  assert.equal(images.size, 6);
});
