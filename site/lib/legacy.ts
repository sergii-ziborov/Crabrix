import { readFileSync } from "node:fs";
import { join } from "node:path";

export const legacyPages = ["about", "technology", "support", "privacy", "terms"] as const;
export type LegacyPage = (typeof legacyPages)[number];

export const legacyMetadata: Record<LegacyPage, { title: string; description: string }> = {
  about: {
    title: "About Crabrix",
    description: "The story behind the native Rust workspace for iPhone and iPad.",
  },
  technology: {
    title: "Crabrix technology",
    description: "The bundled Rust toolchain, Cargo support, sandbox limits and current gaps.",
  },
  support: {
    title: "Crabrix support",
    description: "Help with building, packages, lessons, projects and purchases.",
  },
  privacy: {
    title: "Crabrix privacy policy",
    description: "What stays on your device and what is shared when you choose to connect.",
  },
  terms: {
    title: "Crabrix terms",
    description: "The terms for the Crabrix app and website.",
  },
};

// The checked-in HTML is the canonical copy of the legal and product pages.
// Next renders only its main body; navigation, spacing and footer are shared.
export function legacyMain(name: LegacyPage | "index"): string {
  const source = readFileSync(join(process.cwd(), `${name}.html`), "utf8");
  const match = source.match(/<main>([\s\S]*?)<\/main>/i);
  if (!match) throw new Error(`Missing <main> in ${name}.html`);
  return match[1]
    .replaceAll('src="screenshots/', 'src="/screenshots/')
    .replaceAll('href="screenshots/', 'href="/screenshots/');
}
