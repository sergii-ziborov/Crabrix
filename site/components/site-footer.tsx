import Link from "next/link";

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="site-shell site-footer-row">
        <div>© 2026 Serhii Ziborov. All rights reserved.</div>
        <nav aria-label="Footer navigation">
          <Link href="/learn">Learn</Link>
          <Link href="/blog">Blog</Link>
          <Link href="/about">About</Link>
          <Link href="/technology">Technology</Link>
          <Link href="/support">Support</Link>
          <Link href="/privacy">Privacy</Link>
          <Link href="/terms">Terms</Link>
          <Link href="/licenses">Licenses</Link>
          <a href="https://github.com/sergii-ziborov/Crabrix">GitHub</a>
        </nav>
      </div>
      <p className="site-shell trademark">Rust and the Rust logo are trademarks of the Rust Foundation. Crabrix is independent of the Rust Foundation and Apple.</p>
    </footer>
  );
}
