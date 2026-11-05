import Link from "next/link";

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="site-shell site-footer-row">
        <div>© 2026 Serhii Ziborov. All rights reserved.</div>
        <nav aria-label="Footer navigation">
          <Link prefetch={false} href="/learn">Learn</Link>
          <Link prefetch={false} href="/blog">Blog</Link>
          <Link prefetch={false} href="/guide/">User guide</Link>
          <Link prefetch={false} href="/ai/">Connect AI</Link>
          <Link prefetch={false} href="/sitemap/">Sitemap</Link>
          <Link prefetch={false} href="/about">About</Link>
          <Link prefetch={false} href="/technology">Technology</Link>
          <Link prefetch={false} href="/support">Support</Link>
          <Link prefetch={false} href="/privacy">Privacy</Link>
          <Link prefetch={false} href="/terms">Terms</Link>
          <Link prefetch={false} href="/licenses">Licenses</Link>
          <a href="https://github.com/sergii-ziborov/Crabrix">GitHub</a>
        </nav>
      </div>
      <p className="site-shell trademark">Rust and the Rust logo are trademarks of the Rust Foundation. Crabrix is independent of the Rust Foundation and Apple.</p>
    </footer>
  );
}
