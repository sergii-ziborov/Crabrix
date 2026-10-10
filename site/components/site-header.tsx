import Link from "next/link";
import { currentViewer } from "@/lib/auth";

const links = [
  ["Overview", "/"],
  ["Learn", "/learn"],
  ["Blog", "/blog"],
  ["Technology", "/technology"],
  ["About", "/about"],
  ["Support", "/support"],
] as const;

export async function SiteHeader() {
  const viewer = await currentViewer();
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
        <Link className="site-account" href={viewer ? "/account/" : "/login/"}>{viewer ? "Account" : "Sign in"}</Link>
      </div>
    </header>
  );
}
