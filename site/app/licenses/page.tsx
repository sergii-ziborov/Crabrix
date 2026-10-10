import type { Metadata } from "next";
import Link from "next/link";
import legal from "@/content/legal-documents.json";
import licenses from "@/content/license-index.json";

export const metadata: Metadata = {
  title: "Licenses and content rights",
  description: "Crabrix application source terms, personal learning permission, and original compiler and Swift dependency licenses.",
};

export default function LicensesPage() {
  return (
    <div className="site-shell article-page">
      <div className="page-intro">
        <p className="eyebrow">About & legal</p>
        <h1>Licenses and content rights</h1>
        <p className="lede">The application source, educational material, and open-source components have separate terms. These same documents are bundled in the app for offline reading.</p>
      </div>
      <div className="article-content">
        <section>
          <h2>Using the App Store application</h2>
          <p>Apple’s <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/">Standard EULA</a> applies to the App Store application. Our <Link href="/terms/">Terms of Use</Link> explain Crabrix and the separate free website Academy service; the <Link href="/privacy/">Privacy Policy</Link> describes both. The source license below governs the published application and website code.</p>
        </section>
        {legal.filter((document) => ["source-license", "content-license"].includes(document.id)).map((document) => (
          <section key={document.id} id={document.id}>
            <h2>{document.title}</h2>
            <pre className="legal-text">{document.blocks[0].text}</pre>
          </section>
        ))}
        <section>
          <h2>Third-party open-source components</h2>
          <p>These components retain their original licenses. Neither the application source license nor the course content terms restrict rights they grant you. Read the <a href="/licenses/ThirdPartyNotices.md">complete notices summary</a> and each original text below.</p>
          {licenses.map((license) => (
            <details className="license-disclosure" key={license.id}>
              <summary>{license.name}</summary>
              <p>{license.summary}</p>
              <ul>{license.documents.map((name) => <li key={name}><a href={`/licenses/${name}.txt`}>{name}</a></li>)}</ul>
            </details>
          ))}
        </section>
        <section>
          <h2>Compiler and sysroot notices</h2>
          <p>The pinned <a href="https://github.com/sergii-ziborov/crabrix-toolchain/releases/tag/toolchain-2026-10-02.1">2026-10-02.1 toolchain release</a> includes primary Rust, LLVM, WASI and Cranelift licenses and the exact 1,592-package source inventory. The inventory includes build-time dependencies and preserves the original notice files and declared license expressions.</p>
          <ul>
            <li><a href="/licenses/ToolchainLicenses.zip">Primary license and copyright archive</a></li>
            <li><a href="/licenses/ToolchainVendorNotices.zip">Full vendored notice archive and index</a></li>
          </ul>
          <p>These archives are copied byte for byte from the signed release and also ship inside the app under Settings → About Crabrix → Open-source licenses → Compiler and sysroot dependency notices. Website, native app, and GitHub copies are checked by the same release script.</p>
        </section>
      </div>
    </div>
  );
}
