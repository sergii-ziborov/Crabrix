import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { legacyMain, legacyMetadata, legacyPages, type LegacyPage } from "@/lib/legacy";

export function generateStaticParams() {
  return legacyPages.map((slug) => ({ slug }));
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  if (!legacyPages.includes(slug as LegacyPage)) return {};
  return legacyMetadata[slug as LegacyPage];
}

export default async function LegacyPageView({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  if (!legacyPages.includes(slug as LegacyPage)) notFound();
  return <div className="legacy-page inner-page" dangerouslySetInnerHTML={{ __html: legacyMain(slug as LegacyPage) }} />;
}
