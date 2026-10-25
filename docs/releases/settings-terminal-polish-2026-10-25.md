# Settings and terminal follow-up — 25 October 2026

- Project settings now uses a neutral **X** to close at the trailing edge. **Save** is the prominent blue action at the leading edge, with a contrasting black label. The durable save and error handling from build 91 are retained.
- The extra Run button beside the terminal input is removed. The keyboard's Go key still submits through the same command handler; the project Run action in the workspace header is retained.
- The terminal shows the project name before its prompt only when it fits after reserving 140 points for input, the existing history/keyboard controls, gaps and padding. Long names fall back to the directory prompt. The command row remains 50 points high.
- No changes to Duo fold placement, build tab placement, keyboard helpers, compiler configuration or package capabilities.

Verification: optimized iOS Simulator app build; website verification is recorded separately in the site deployment notes.
