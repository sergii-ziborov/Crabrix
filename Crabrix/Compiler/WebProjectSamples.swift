import Foundation

enum WebProjectSamples {
    static let files: [String: String] = [
        "index.html": """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Crabrix Web Lab</title>
          <link rel="stylesheet" href="styles.css">
          <script src="app.js" defer></script>
        </head>
        <body>
          <main>
            <p class="eyebrow">BUILT HERE · RUNS OFFLINE</p>
            <h1>Small page. Real code. 🦀</h1>
            <p>Edit the HTML, CSS and JavaScript, then Run again.</p>
            <button id="counter" type="button">Clicks: 0</button>
            <p id="status" role="status">Ready for your first click.</p>
          </main>
        </body>
        </html>
        """,
        "styles.css": """
        :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
        body { margin: 0; min-height: 100vh; display: grid; place-items: center;
          background: #0d1724; color: #f5f0df; }
        main { max-width: 36rem; padding: 2rem; }
        .eyebrow { color: #7de0c3; font-size: .72rem; letter-spacing: .12em; }
        h1 { font-size: clamp(2rem, 6vw, 3.8rem); line-height: 1.1; }
        p { line-height: 1.6; }
        button { border: 0; border-radius: 999px; padding: .9rem 1.6rem;
          background: #7de0c3; color: #10242b; font: inherit; font-weight: 700;
          cursor: pointer; transition: transform .15s ease; }
        button:hover { transform: translateY(-2px); }
        button:focus-visible { outline: 3px solid #ffbd66; outline-offset: 4px; }
        @media (prefers-reduced-motion: reduce) { button { transition: none; } }
        """,
        "app.js": """
        const button = document.querySelector('#counter');
        const status = document.querySelector('#status');
        let clicks = 0;
        button.addEventListener('click', () => {
          clicks += 1;
          button.textContent = `Clicks: ${clicks}`;
          status.textContent = 'JavaScript is running locally.';
          console.log('Counter updated:', clicks);
        });
        """,
    ]

    static let rustGenerator = #"""
    use std::fs;

    fn main() {
        // Write the generated site into the program's writable sandbox.
        fs::write("/sandbox/index.html", include_str!("../web/index.html")).unwrap();
        fs::write("/sandbox/styles.css", include_str!("../web/styles.css")).unwrap();
        fs::write("/sandbox/app.js", include_str!("../web/app.js")).unwrap();
        println!("Generated index.html, styles.css and app.js locally.");
    }
    """#
}
