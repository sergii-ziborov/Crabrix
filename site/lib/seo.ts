import type { Metadata } from "next";

export const siteOrigin = "https://crabrix.com";
export const defaultSocialImage = "/images/crabrix-search.png";

export function pageUrl(path: string): string {
  const pathname = path.split(/[?#]/, 1)[0].replace(/^\/+|\/+$/g, "");
  // Next keeps extension-like final segments (including Atlas lesson IDs)
  // without a trailing slash, even when trailingSlash is enabled.
  const extensionLike = /\.[^/]+$/.test(pathname);
  return `${siteOrigin}/${pathname}${pathname && !extensionLike ? "/" : ""}`;
}

export function pageMetadata({ title, description, path, image = defaultSocialImage,
  imageAlt = "Crabrix: learn Rust and compile projects locally on iPhone and iPad", articleDate, kind, modifiedDate,
}: { title: string; description: string; path: string; image?: string; imageAlt?: string; articleDate?: string; kind?: "article"; modifiedDate?: string }): Metadata {
  const url = pageUrl(path);
  return {
    title, description,
    alternates: { canonical: url },
    openGraph: { title, description, url, siteName: "Crabrix", locale: "en_US",
      type: articleDate || kind === "article" ? "article" : "website",
      ...(articleDate ? { publishedTime: articleDate } : {}),
      ...(modifiedDate ? { modifiedTime: modifiedDate } : {}),
      images: [{ url: new URL(image, siteOrigin).href, alt: imageAlt }],
    },
    twitter: { card: "summary_large_image", title, description, images: [new URL(image, siteOrigin).href] },
  };
}

export function breadcrumbs(items: { name: string; path: string }[]) {
  return { "@type": "BreadcrumbList", itemListElement: items.map((item, index) => ({
    "@type": "ListItem", position: index + 1, name: item.name, item: pageUrl(item.path),
  })) };
}
