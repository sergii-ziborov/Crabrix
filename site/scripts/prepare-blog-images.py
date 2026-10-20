#!/usr/bin/env python3
"""Encode generated PNG originals as responsive WebP delivery copies."""
import json
from pathlib import Path
from PIL import Image
site = Path(__file__).resolve().parents[1]
posts = json.loads((site / 'content/posts.json').read_text())
rows = []
for src in sorted({s['image']['src'] for p in posts for s in p['sections'] if s.get('image')}):
    original = site / 'public' / src.lstrip('/')
    with Image.open(original) as image:
        full = original.with_suffix('.webp')
        image.save(full, 'WEBP', quality=92, method=6)
        small = original.with_name(original.stem + '-640.webp')
        thumb = image.copy()
        thumb.thumbnail((640, 10000), Image.Resampling.LANCZOS)
        thumb.save(small, 'WEBP', quality=92, method=6)
        rows.append({'source': src, 'sourceBytes': original.stat().st_size,
                     'full': '/' + full.relative_to(site / 'public').as_posix(), 'fullBytes': full.stat().st_size,
                     'small': '/' + small.relative_to(site / 'public').as_posix(), 'smallBytes': small.stat().st_size,
                     'dimensions': image.size, 'smallDimensions': thumb.size})
print(json.dumps({'images': rows, 'originalBytes': sum(r['sourceBytes'] for r in rows),
                  'fullWebPBytes': sum(r['fullBytes'] for r in rows),
                  'cardWebPBytes': sum(r['smallBytes'] for r in rows)}, indent=2))
