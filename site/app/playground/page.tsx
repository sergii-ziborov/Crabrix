import { pageMetadata } from "@/lib/seo";
import { PlaygroundLoader } from "@/components/playground/loader";
import "./playground.css";
export const metadata = pageMetadata({ title: "Rust Playground — Run Rust Locally in Your Browser", description: "An anonymous Rust Playground with local browser compilation, temporary encrypted sharing, collaborative coding interviews and Crabrix source export.", path: "/playground/" });
export default function PlaygroundPage() { return <PlaygroundLoader />; }
