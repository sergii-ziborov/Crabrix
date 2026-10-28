import { readFileSync } from "node:fs";
import { join } from "node:path";
import capabilities from "../content/capabilities.json";

export const legacyPages = ["about", "technology", "support", "privacy", "terms"] as const;
export type LegacyPage = (typeof legacyPages)[number];

export const legacyMetadata: Record<LegacyPage, { title: string; description: string }> = {
  about: {
    title: "About Crabrix",
    description: "Meet Crabrix: the offline Rust compiler, illustrated Academy and local web lab for iPhone, iPad and Duo. Learn how projects and course updates work.",
  },
  technology: {
    title: "Crabrix technology",
    description: "Understand Crabrix’s bundled Rust compiler, Cargo and browser npm package preparation, TypeScript/JSX builds, offline WebKit preview, WASI sandbox limits and supported build-script boundaries.",
  },
  support: {
    title: "Crabrix support",
    description: "Get help with Crabrix projects, Rust build errors, package downloads, offline courses, web previews and purchases. Learn what to include in a useful report.",
  },
  privacy: {
    title: "Crabrix privacy policy",
    description: "App data stays on your device; this policy also explains website Academy accounts, necessary cookies and your rights.",
  },
  terms: {
    title: "Crabrix terms",
    description: "Read the terms for Crabrix’s offline compiler, website Academy accounts, educational content, original projects and third-party open-source components.",
  },
};

// The checked-in HTML is the canonical copy of the legal and product pages.
// Next renders only its main body; navigation, spacing and footer are shared.
export function legacyMain(name: LegacyPage | "index"): string {
  const source = readFileSync(join(process.cwd(), `${name}.html`), "utf8");
  const match = source.match(/<main>([\s\S]*?)<\/main>/i);
  if (!match) throw new Error(`Missing <main> in ${name}.html`);
  return match[1]
    .replace(/(<li data-capability="rust\.build-scripts">)[\s\S]*?(<\/li>)/, (_, start: string, end: string) => {
      const description = capabilities.capabilities.find(item => item.id === "rust.build-scripts")?.publicDescription;
      if (!description) throw new Error("Missing build-script capability profile");
      const escaped = description.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
      return start + escaped + end;
    })
    .replaceAll('src="screenshots/', 'src="/screenshots/')
    .replaceAll('href="screenshots/', 'href="/screenshots/');
}
