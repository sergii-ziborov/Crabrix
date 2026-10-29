import type { MetadataRoute } from "next";

export const dynamic = "force-static";

export default function robots(): MetadataRoute.Robots {
  // Public sign-in pages must be crawlable for their noindex directives to be
  // observed. Account data remains authenticated; temporary rooms stay excluded.
  return { rules: { userAgent: "*", allow: "/", disallow: ["/account/", "/playground/room/", "/api/playground/"] }, sitemap: "https://crabrix.com/sitemap.xml" };
}
