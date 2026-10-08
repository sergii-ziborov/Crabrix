import type { Metadata } from "next";
import { legacyMain } from "@/lib/legacy";

export const metadata: Metadata = {
  title: "A real Rust compiler on your iPhone and iPad",
  description: "Write Rust, learn from 742 lessons and Atlas steps, and compile and run locally on iPhone and iPad.",
};

export default function HomePage() {
  return <div className="home-page legacy-page" dangerouslySetInnerHTML={{ __html: legacyMain("index") }} />;
}
