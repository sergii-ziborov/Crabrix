# Original blog images — 18 October 2026

Mode: built-in `image_gen`. Ten selected landscape PNG assets (1536 × 1024), one cover and one explanatory infographic per new article. Each was visually inspected. No CLI/API fallback was used.

Selected paths, article dates, word counts, captions and SHA-256 digests: [asset manifest](blog-assets-2026-10-18.json).

The two initial infographic candidates below were rejected during review. Selected sibling `v2` assets replace them in the articles; the rejected files are not in the public release. Other existing images were preserved.

## rust-iterators-workshop.png

Project asset: `site/public/blog/rust-iterators-workshop.png`

### Generation prompt

Use case: illustration-story. Asset type: original editorial cover for the Crabrix Rust programming blog. One polished 3:2 landscape raster illustration. Match the established blog visual language: tactile layered paper and clay, deep midnight navy background, warm cream surfaces, mint accents, one small friendly coral-orange crab. Carefully composed, sophisticated editorial quality, soft practical lighting, generous breathing room. No lettering, no interface screenshots, no logos or watermarks. A miniature conveyor workshop: four numbered-shape tokens enter a selection gate, two chosen tokens continue through a transformation wheel into one small result bowl. The crab operates the final take-up handle, visually explaining that a consumer pulls items through the pipeline. Shapes rather than printed numbers; no text. Distinct ordered stages, no oversized factory clutter.

## rust-iterators-v2-infographic.png

Project asset: `site/public/blog/rust-iterators-v2-infographic.png`

### Generation prompt

Use case: infographic-diagram. Asset type: original educational infographic for the Crabrix Rust programming blog. One polished 3:2 landscape raster infographic. Midnight navy background, cream typography, mint/coral/soft-gold diagram accents, flat crisp geometric panels with subtle paper texture. Large readable text and ample whitespace, visually precise arrows and alignment. All listed text must be exact. Do not invent facts, numerical measurements, extra labels, logos or watermarks. Title: "A consumer drives the pipeline". Four vertically stacked wide rows with clear arrows downward. Row labels and contents exactly: "Input" then four chips "2" "7" "4" "9"; "Keep even" then two chips "2" "4"; "Square" then two chips "4" "16"; "Sum" then one large chip "20". A slender arrow labelled "Demand" rises from Sum toward Input on the right. Footer exactly: "collect() stores results; sum() returns one value". Values 7 and 9 visibly leave at the filter stage. No speed percentages or memory-size claims.

### Targeted correction

Edit target: the generated `rust-iterators-infographic.png` candidate.

Edit this existing educational infographic with ONE precise correction. Preserve all typography, all numbers, layout, navy background, colors, and the upward mint Demand arrow. Remove BOTH curved coral arrows that run from the Input row to the crossed-out rejected 7 and 9 in the Keep even row. These arrows are misleading; leave no curved coral arrows between those rows. Keep the rejected crossed-out 7 and 9 tiles in place. Keep the central vertical cream stage arrows. The numbers must remain input [2,7,4,9], accepted [2,4], squared [4,16], sum 20. No other changes.

## rust-utf8-workshop.png

Project asset: `site/public/blog/rust-utf8-workshop.png`

### Generation prompt

Use case: illustration-story. Asset type: original editorial cover for the Crabrix Rust programming blog. One polished 3:2 landscape raster illustration. Match the established blog visual language: tactile layered paper and clay, deep midnight navy background, warm cream surfaces, mint accents, one small friendly coral-orange crab. Carefully composed, sophisticated editorial quality, soft practical lighting, generous breathing room. No lettering, no interface screenshots, no logos or watermarks. A crab carefully arranges a row of seven small mosaic tiles into three differently sized groups: one single tile, one pair, one group of four. Above each group is a decorative letter-shaped form, an accented letter-shaped form, and a tiny crab silhouette. Clear grouping dividers act as safe cutting guides; a delicate cutting tool rests only at group boundaries. The metaphor is UTF-8 byte boundaries, not a text editor. No printed letters or numeric text.

## rust-utf8-infographic.png

Project asset: `site/public/blog/rust-utf8-infographic.png`

### Generation prompt

Use case: infographic-diagram. Asset type: original educational infographic for the Crabrix Rust programming blog. One polished 3:2 landscape raster infographic. Midnight navy background, cream typography, mint/coral/soft-gold diagram accents, flat crisp geometric panels with subtle paper texture. Large readable text and ample whitespace, visually precise arrows and alignment. All listed text must be exact. Do not invent facts, numerical measurements, extra labels, logos or watermarks. Title: "UTF-8: bytes are not characters". Show the exact example text "aé🦀" prominently, using precomposed é U+00E9. Under it, seven equal byte cells in one horizontal row, grouped 1 / 2 / 4 with distinct colors. Exact hex bytes left to right: "61" "C3" "A9" "F0" "9F" "A6" "80". Above the three groups: "a" over 61, "é" over C3 A9, a small crab glyph over the last four cells. Under the groups exactly: "1 byte" "2 bytes" "4 bytes". Footer: "7 bytes • 3 Unicode scalar values" and a smaller caution "A visible character can contain several scalars". Boundary markers only at offsets "0", "1", "3", "7". No boundary in the middle of a group.

## rust-testing-workshop.png

Project asset: `site/public/blog/rust-testing-workshop.png`

### Generation prompt

Use case: illustration-story. Asset type: original editorial cover for the Crabrix Rust programming blog. One polished 3:2 landscape raster illustration. Match the established blog visual language: tactile layered paper and clay, deep midnight navy background, warm cream surfaces, mint accents, one small friendly coral-orange crab. Carefully composed, sophisticated editorial quality, soft practical lighting, generous breathing room. No lettering, no interface screenshots, no logos or watermarks. A quiet testing bench, a coral crab compares a small finished module with a tray of deliberately different input specimens: a normal filled tile, an empty slot tile, a cracked malformed tile, and a boundary-marked ruler tile. A magnifying glass and a simple mechanical check fixture express repeatable verification. Mint check symbols may appear as symbols, not words. This is disciplined debugging and fixtures, not software dashboards or generic code rain.

## rust-testing-v2-infographic.png

Project asset: `site/public/blog/rust-testing-v2-infographic.png`

### Generation prompt

Use case: infographic-diagram. Asset type: original educational infographic for the Crabrix Rust programming blog. One polished 3:2 landscape raster infographic. Midnight navy background, cream typography, mint/coral/soft-gold diagram accents, flat crisp geometric panels with subtle paper texture. Large readable text and ample whitespace, visually precise arrows and alignment. All listed text must be exact. Do not invent facts, numerical measurements, extra labels, logos or watermarks. Title: "Choose the test boundary". Three equal cards, not a pyramid or performance chart. Card 1 title "Unit" subtitle "One rule" with a single function block and input/output arrows. Card 2 title "Integration" subtitle "Public API" with two connected module blocks behind a clearly drawn package boundary. Card 3 title "Doctest" subtitle "An executable example" with a document page containing a short code-shaped diagram and a check mark. Bottom horizontal strip title "Useful cases" with four chips: "Normal" "Empty" "Malformed" "Boundary". Footer: "Assert behaviour, not private implementation". No timing, coverage percentages or invented statistics.

### Targeted correction

Edit target: the generated `rust-testing-infographic.png` candidate.

Revise the CONTENT of this Rust testing infographic while preserving its beautiful navy, cream, mint, coral and yellow visual style and three-column layout. Title remains 'Choose the test boundary'. Unit card subtitle 'One rule', diagram must be input arrow -> simple box labelled 'Rule' -> output arrow; no fake function signature. Integration card subtitle 'Public API': replace its internal modules diagram with two boxes. A small box 'External test' must be OUTSIDE a dotted rectangle labelled 'Library'. An arrow from External test enters the Library rectangle and points to a box labelled 'Public API'. This correctly shows an integration test as an external caller of a library API, not internal module-to-module calls. Doctest subtitle 'An executable example': replace code with a simple document icon and three short, readable lines 'Show usage' / 'Run example' / 'Check result', plus a check mark. Do NOT include incomplete or syntactically invalid Rust code anywhere. Preserve bottom Useful cases row Normal, Empty, Malformed, Boundary and footer 'Assert behaviour, not private implementation'. Clear professional analytical explanatory diagram, landscape1536x1024.

## rust-cargo-features-workshop.png

Project asset: `site/public/blog/rust-cargo-features-workshop.png`

### Generation prompt

Use case: illustration-story. Asset type: original editorial cover for the Crabrix Rust programming blog. One polished 3:2 landscape raster illustration. Match the established blog visual language: tactile layered paper and clay, deep midnight navy background, warm cream surfaces, mint accents, one small friendly coral-orange crab. Carefully composed, sophisticated editorial quality, soft practical lighting, generous breathing room. No lettering, no interface screenshots, no logos or watermarks. A modular workbench for a small Rust toolkit: a compact central engine, two optional attachable modules in different colors, and a larger unused accessory tray. The crab selects just the necessary modules and checks a small travel case with a constrained opening. Physical cables lead from two request cards to the same central engine, subtly showing shared feature requests. No text or numbers, no false benchmark imagery, no laptop GUI.

## rust-cargo-features-infographic.png

Project asset: `site/public/blog/rust-cargo-features-infographic.png`

### Generation prompt

Use case: infographic-diagram. Asset type: original educational infographic for the Crabrix Rust programming blog. One polished 3:2 landscape raster infographic. Midnight navy background, cream typography, mint/coral/soft-gold diagram accents, flat crisp geometric panels with subtle paper texture. Large readable text and ample whitespace, visually precise arrows and alignment. All listed text must be exact. Do not invent facts, numerical measurements, extra labels, logos or watermarks. Title: "Feature requests add together". At the top two cards: left "App" with chip "json"; right "CLI" with chip "csv". Both point with clear arrows to one middle card titled "One package version" containing two chips "json" and "csv". Under that card a short equation exactly: "{json} ∪ {csv} = {json, csv}". Bottom two separate notes: "default-features = false is local to a dependency edge" and "Features do not guarantee target compatibility". Small footer: "Illustration: one normal-dependency context". No implication that all versions or build contexts always unify. Keep the long notes large and readable.

## rust-enum-states-workshop.png

Project asset: `site/public/blog/rust-enum-states-workshop.png`

### Generation prompt

Use case: illustration-story. Asset type: original editorial cover for the Crabrix Rust programming blog. One polished 3:2 landscape raster illustration. Match the established blog visual language: tactile layered paper and clay, deep midnight navy background, warm cream surfaces, mint accents, one small friendly coral-orange crab. Carefully composed, sophisticated editorial quality, soft practical lighting, generous breathing room. No lettering, no interface screenshots, no logos or watermarks. An elegant miniature railway control scene: three distinct platforms connected in one direction through two deliberate gates. At the first platform a blank cream document tile is assembled, at the second it receives a mint validation seal, at the third a completed document sits safely in an archive slot. A friendly coral crab operates the junction. An unused tangled bundle of two loose toggle wires lies off to one side. No lettering or numbers. Convey explicit workflow stages and legal transitions without any financial or network claims.

## rust-enum-states-infographic.png

Project asset: `site/public/blog/rust-enum-states-infographic.png`

### Generation prompt

Use case: infographic-diagram. Asset type: original educational infographic for the Crabrix Rust programming blog. One polished 3:2 landscape raster infographic. Midnight navy background, cream typography, mint/coral/soft-gold diagram accents, flat crisp geometric panels with subtle paper texture. Large readable text and ample whitespace, visually precise arrows and alignment. All listed text must be exact. Do not invent facts, numerical measurements, extra labels, logos or watermarks. Title: "Model the states you intend". Upper half: exactly three large state cards labelled "Draft", "Ready", "Sent", connected left-to-right. First arrow label "Validate", second arrow label "Send". A return arrow from Ready to Draft is labelled "Edit". Sent has no outgoing arrow. Lower half: a compact truth table titled "Two flags allow four combinations". Columns "valid" "sent" "Meaning"; four rows exactly "false | false | Draft", "true | false | Ready", "true | true | Sent", "false | true | Invalid". Last row coral warning background, other rows navy with cream text. Footer: "An enum names three intended states". Explain only this chosen workflow, no universal claim about all boolean pairs.
