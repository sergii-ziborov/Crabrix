import Link from "next/link";

const links = [
  ["Overview", "/"],
  ["Learn", "/learn"],
  ["Blog", "/blog"],
  ["Technology", "/technology"],
  ["About", "/about"],
  ["Support", "/support"],
] as const;

export function SiteHeader() {
  return (
    <header className="site-header">
      <div className="site-shell site-header-row">
        <Link className="site-brand" href="/" aria-label="Crabrix home">
          <span className="site-mark" aria-hidden="true">🦀</span>
          <span>Crabrix</span>
        </Link>
        <nav className="site-nav" aria-label="Main navigation">
          {links.map(([label, href]) => <Link key={href} href={href}>{label}</Link>)}
        </nav>
      </div>
    </header>
  );
}
