import type { ReactNode } from "react";
import Link from "next/link";

export function AuthShell({ title, description, children }: { title: string; description: string; children: ReactNode }) {
  return <div className="site-shell auth-page">
    <aside className="auth-story">
      <p className="eyebrow">Crabrix Academy</p>
      <h1>A little Rust.<br />A real understanding.</h1>
      <p className="lede">Read, trace, change, and try again. Your free account opens every lesson.</p>
      <div className="auth-code-art" aria-hidden="true"><span>fn</span> grow() &#123;<br />&nbsp;&nbsp;<span>let</span> next = practice();<br />&nbsp;&nbsp;understanding.push(next);<br />&#125;</div>
      <ul className="auth-benefits"><li>742 lessons and algorithm steps</li><li>Examples, explanations and infographics</li><li>Free access. No payment details.</li></ul>
      <Link className="auth-link" href="/learn/">Explore the course library →</Link>
    </aside>
    <section className="auth-panel"><h2>{title}</h2><p>{description}</p>{children}</section>
  </div>;
}
