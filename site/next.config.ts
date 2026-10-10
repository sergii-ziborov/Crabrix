import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  trailingSlash: true,
  images: { unoptimized: true },
  poweredByHeader: false,
  outputFileTracingIncludes: { "/*": ["./content/courses.json", "./*.html"], "/learn-media/*": ["./content/learn-media/**/*.png"] },
  outputFileTracingExcludes: { "/*": ["./auth-data/**/*", "./tests/**/*"] },
  experimental: { serverActions: { bodySizeLimit: "16kb" } },
  async redirects() {
    return ["about", "technology", "support", "privacy", "terms"].map((route) => ({ source: `/${route}.html`, destination: `/${route}/`, permanent: true }));
  },
  async headers() {
    return [{ source: "/:path*", headers: [
      { key: "X-Content-Type-Options", value: "nosniff" },
      { key: "X-Frame-Options", value: "DENY" },
      { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
      { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
    ] }];
  },
};

export default nextConfig;
