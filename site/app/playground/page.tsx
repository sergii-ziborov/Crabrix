import { pageMetadata } from "@/lib/seo";
import { PlaygroundLoader } from "@/components/playground/loader";
import "./playground.css";
export const metadata = pageMetadata({ title: "Rust Playground — Run Rust Locally in Your Browser", description: "Run Rust locally in your browser, prepare supported Cargo crates, organize source folders and code together in encrypted rooms. Live interviews, AI agents and ZIP export. No login.", path: "/playground/", modifiedDate: "2026-11-05" });
export default function PlaygroundPage() { return <PlaygroundLoader />; }
