import { pageMetadata } from "@/lib/seo";
import { PlaygroundLoader } from "@/components/playground/loader";
import "./playground.css";
export const metadata = pageMetadata({ title: "Rust Playground — Run Rust Locally in Your Browser", description: "A Rust Playground that compiles in your browser, with end-to-end encrypted rooms for people and AI agents such as Claude, Codex, Cursor and Grok, live coding interviews and source export. No login.", path: "/playground/" });
export default function PlaygroundPage() { return <PlaygroundLoader />; }
