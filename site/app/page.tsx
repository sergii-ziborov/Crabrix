import { pageMetadata } from "@/lib/seo";
import { StructuredData } from "@/components/structured-data";
import { legacyMain } from "@/lib/legacy";
import { ScreenshotGalleries } from "@/components/screenshot-galleries";

export const metadata = pageMetadata({"title": "Rust Compiler for iPhone, iPad & Duo", "description": "Compile Rust locally on iPhone, iPad and iPhone Duo. Explore supported Cargo projects, 742 illustrated lessons and 46 code examples with Crabrix.", "path": "/"});

export default function HomePage() {
  const [beforeGallery, afterGallery] = legacyMain("index").split("<!-- screenshot-galleries -->");
  return <>
    <StructuredData data={{ "@context": "https://schema.org", "@graph": [
      { "@type": "WebSite", name: "Crabrix", url: "https://crabrix.com/", inLanguage: "en" },
      { "@type": "SoftwareApplication", name: "Crabrix", url: "https://crabrix.com/",
        applicationCategory: "DeveloperApplication", operatingSystem: "iOS 18 or later; iPadOS 18 or later",
        description: "A native Rust editor, local compiler and offline learning Academy for iPhone, iPad and iPhone Duo.",
        downloadUrl: "https://apps.apple.com/app/id6809502653", softwareHelp: "https://crabrix.com/support/",
        featureList: ["Local Rust compilation", "Supported Cargo dependencies", "742 lessons and steps", "46 code examples"],
      },
    ] }} />
    <div className="home-page legacy-page">
      <div dangerouslySetInnerHTML={{ __html: beforeGallery }} />
      <ScreenshotGalleries />
      <div dangerouslySetInnerHTML={{ __html: afterGallery }} />
    </div>
  </>;
}
