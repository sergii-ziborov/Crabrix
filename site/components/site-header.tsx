import Link from "next/link";
import { currentViewer } from "@/lib/auth";
import { SiteNavigation } from "@/components/site-navigation";

export async function SiteHeader() {
  const viewer = await currentViewer();
  return (
    <header className="site-header">
      <div className="site-shell site-header-row">
        <Link className="site-brand" href="/" aria-label="Crabrix home">
          <span className="site-mark" aria-hidden="true"><img src="/brand/crabrix-mark.png" width="35" height="35" alt="" /></span>
          <span>Crabrix</span>
        </Link>
        <SiteNavigation />
        <Link className="site-account" href={viewer ? "/account/" : "/login/"}>{viewer ? "Account" : "Sign in"}</Link>
      </div>
    </header>
  );
}
