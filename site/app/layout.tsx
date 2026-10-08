import type { Metadata } from "next";
import { SiteHeader } from "@/components/site-header";
import { SiteFooter } from "@/components/site-footer";
import { MailLinks } from "@/components/mail-links";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://crabrix.com"),
  title: { default: "Crabrix — Rust on iPhone and iPad", template: "%s | Crabrix" },
  description: "Learn Rust for free on the web, then compile and run it locally on iPhone and iPad with Crabrix.",
  openGraph: { siteName: "Crabrix", type: "website" },
  icons: { icon: "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'%3E%3Ctext y='.9em' font-size='90'%3E%F0%9F%A6%80%3C/text%3E%3C/svg%3E" },
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
