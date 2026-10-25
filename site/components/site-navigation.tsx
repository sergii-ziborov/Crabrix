"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const links = [
  ["Overview", "/"],
  ["Learn", "/learn/"],
  ["Blog", "/blog/"],
  ["Guide", "/guide/"],
  ["Technology", "/technology/"],
  ["About", "/about/"],
  ["Support", "/support/"],
] as const;

export function SiteNavigation() {
  const pathname = usePathname();
  return (
    <nav className="site-nav" aria-label="Main navigation">
      {links.map(([label, href]) => {
        const active = href === "/" ? pathname === "/" : pathname === href.slice(0, -1) || pathname.startsWith(href);
        return <Link key={href} href={href} aria-current={active ? "page" : undefined}>{label}</Link>;
      })}
    </nav>
  );
}
