import type { Metadata } from "next";
import { SiteHeader } from "@/components/site-header";
import { SiteFooter } from "@/components/site-footer";
import { MailLinks } from "@/components/mail-links";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://crabrix.com"),
  title: { default: "Crabrix — Rust on iPhone and iPad", template: "%s | Crabrix" },
  description: "Learn Rust for free on the web, then compile and run it locally on iPhone and iPad with Crabrix.",
  applicationName: "Crabrix",
  authors: [{ name: "Serhii Ziborov", url: "https://crabrix.com/about/" }],
  // Normal pages are indexable by default. Explicit global index directives
  // would also be inherited by Next's automatically noindexed 404 responses.
  robots: { googleBot: { "max-image-preview": "large" } },
  openGraph: { siteName: "Crabrix", type: "website", locale: "en_US" },
  icons: { icon: "/brand/crabrix-mark.png", apple: "/brand/crabrix-mark.png" },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <SiteHeader />
        <main id="main-content">{children}</main>
        <SiteFooter />
        <MailLinks />
      </body>
    </html>
  );
}
