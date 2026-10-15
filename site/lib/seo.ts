import type { Metadata } from "next";

export const siteOrigin = "https://crabrix.com";
export const defaultSocialImage = "/images/crabrix-search.png";

export function pageUrl(path: string): string {
  const pathname = path.split(/[?#]/, 1)[0].replace(/^\/+|\/+$/g, "");
  return `${siteOrigin}/${pathname ? `${pathname}/` : ""}`;
}

export function pageMetadata({ title, description, path, image = defaultSocialImage,
  imageAlt = "Crabrix: learn Rust and compile projects locally on iPhone and iPad", articleDate,
}: { title: string; description: string; path: string; image?: string; imageAlt?: string; articleDate?: string }): Metadata {
  const url = pageUrl(path);
  return {
    title, description,
    alternates: { canonical: url },
    openGraph: { title, description, url, siteName: "Crabrix", locale: "en_US",
      type: articleDate ? "article" : "website",
      ...(articleDate ? { publishedTime: articleDate } : {}),
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
