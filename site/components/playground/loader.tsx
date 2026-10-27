"use client";
import dynamic from "next/dynamic";
const Workspace = dynamic(() => import("./workspace"), { ssr: false, loading: () => <div className="pg-loading site-shell"><h1>Playground</h1><p>Preparing your local editor…</p></div> });
export function PlaygroundLoader() { return <Workspace />; }
