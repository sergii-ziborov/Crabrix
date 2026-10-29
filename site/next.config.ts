import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  allowedDevOrigins: ["127.0.0.1"],
  output: "standalone",
  trailingSlash: true,
  images: { unoptimized: true },
  poweredByHeader: false,
  outputFileTracingIncludes: { "/*": ["./content/courses.json", "./*.html"], "/learn/*": ["./content/algorithm-traces/*.json"], "/learn-media/*": ["./content/learn-media/**/*.png"] },
  outputFileTracingExcludes: { "/*": ["./auth-data/**/*", "./tests/**/*"] },
  experimental: { serverActions: { bodySizeLimit: "16kb" } },
  async redirects() {
    return ["about", "technology", "support", "privacy", "terms"].map((route) => ({ source: `/${route}.html`, destination: `/${route}/`, permanent: true }));
  },
  async headers() {
    return [
      { source: "/:path*", headers: [
        { key: "X-Content-Type-Options", value: "nosniff" },
        { key: "X-Frame-Options", value: "DENY" },
        { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
        { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
      ] },
      { source: "/.well-known/apple-app-site-association", headers: [{ key: "Content-Type", value: "application/json" }] },
      { source: "/playground/room/:path*", headers: [{ key: "Referrer-Policy", value: "no-referrer" }, { key: "X-Robots-Tag", value: "noindex, nofollow, noarchive" }, { key: "Cache-Control", value: "private, no-store" }] },
      { source: "/playground/:path*", headers: [{ key: "Cross-Origin-Opener-Policy", value: "same-origin" }, { key: "Cross-Origin-Embedder-Policy", value: "require-corp" }] },
      { source: "/_next/static/:path*", headers: [{ key: "Cross-Origin-Embedder-Policy", value: "require-corp" }] },
      { source: "/playground-runtime/:path*", headers: [{ key: "Cache-Control", value: "public, max-age=3600" }] },
    ];
  },
};

export default nextConfig;
