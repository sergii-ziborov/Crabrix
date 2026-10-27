import type { MetadataRoute } from "next";

export const dynamic = "force-static";

export default function robots(): MetadataRoute.Robots {
  return { rules: { userAgent: "*", allow: "/", disallow: ["/account/", "/login/", "/register/", "/recover/", "/playground/room/", "/api/playground/"] }, sitemap: "https://crabrix.com/sitemap.xml" };
}
