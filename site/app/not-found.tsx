import Link from "next/link";

export default function NotFound() {
  return <div className="site-shell page-intro"><p className="eyebrow">404</p><h1>Page not found</h1><p className="lede">This page has moved or does not exist.</p><Link className="btn" href="/">Back to Crabrix</Link></div>;
}
