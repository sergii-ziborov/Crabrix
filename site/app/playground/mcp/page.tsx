import Link from "next/link";
import { pageMetadata, breadcrumbs } from "@/lib/seo";
import { StructuredData } from "@/components/structured-data";
import { SyntaxCode } from "@/components/SyntaxCode";
import download from "@/lib/mcp-download.json";
import "./mcp.css";

export const metadata = pageMetadata({ title: "Crabrix MCP — Claude Meets Your Rust Playground", description: "Ask Claude to edit a shared Rust Playground and see the changes in Crabrix on your iPhone or iPad. Download the MCP bridge. Encrypted rooms, live selections and local execution.", path: "/playground/mcp/" });

export default function PlaygroundMCPPage() {
  return <div className="site-shell mcp-page">
    <StructuredData data={breadcrumbs([{ name: "Home", path: "/" }, { name: "Playground", path: "/playground/" }, { name: "MCP", path: "/playground/mcp/" }])} />
    <section className="mcp-hero">
      <div><p className="eyebrow">Your AI. Your editor. One shared Playground.</p>
        <h1>Ask Claude.<br /><span className="mcp-gradient">See it in Crabrix.</span></h1>
        <p className="lede">Give Claude a Rust task on your computer. Watch the code appear in the same Playground on your iPhone, iPad or browser. Keep writing together, then run it on your device.</p>
        <div className="cta-row"><a className="btn" href={download.url} download>Download MCP ↓</a><a className="btn ghost" href="#setup">Set up Claude →</a></div>
        <p className="mcp-download-note">v{download.version} · {download.sizeLabel} · Node.js 22+ · no Crabrix account</p>
      </div>
      <div className="mcp-preview" aria-label="Illustration of Claude editing a shared Rust project">
        <div className="mcp-example-label">Example workflow</div>
        <div className="mcp-task"><span className="mcp-spark" aria-hidden="true">✦</span><div><strong>You ask Claude</strong><p>“Add a Fibonacci function and show me how it works.”</p></div></div>
        <div className="mcp-connection" aria-hidden="true"><span>computer</span><i /><span>encrypted room</span><i /><span>phone</span></div>
        <div className="mcp-code-window"><div className="mcp-code-title"><span>main.rs</span><span className="mcp-peer-dot">Claude · MCP</span></div>
          <SyntaxCode code={'fn fibonacci(n: u32) -> u64 {\n    let (mut a, mut b) = (0, 1);\n    for _ in 0..n {\n        (a, b) = (b, a + b);\n    }\n    a\n}\n\nfn main() {\n    println!("{}", fibonacci(10));\n}'} />
          <div className="mcp-device-action"><span>Shared source. Ready in your editor.</span><span>▶ Run locally</span></div>
        </div>
      </div>
    </section>
    <div className="mcp-facts"><div><strong>One room</strong><span>app, browser and AI together</span></div><div><strong>1 hour</strong><span>default lifetime · up to 24 hours</span></div><div><strong>Local Run</strong><span>your device executes the code</span></div></div>
    <section className="mcp-section"><div className="eyebrow">A participant in your editor</div><h2>A useful pair of hands, right where you work.</h2>
      <div className="mcp-feature-grid">
        <article className="mcp-feature"><span aria-hidden="true">⌘</span><h3>Make the change</h3><p>Claude reads a file, edits the current revision and sends the change to everyone in the room. Your phone shows the actual shared source.</p></article>
        <article className="mcp-feature"><span aria-hidden="true">↗</span><h3>Point to the code</h3><p>A named selection shows which part Claude is explaining. Human selections also reach the MCP client, including Unicode text.</p></article>
        <article className="mcp-feature"><span aria-hidden="true">◇</span><h3>Keep your place</h3><p>If another participant changes the project first, the proposed edit is rejected. Claude reads the new revision before trying again.</p></article>
      </div>
    </section>
    <section className="mcp-section"><div className="eyebrow">The actual shared editor</div><h2>Code arrives. Your tools stay local.</h2><p className="section-lede">These Simulator captures come from a four-participant check: the MCP bridge, a browser and two Crabrix apps. Each app ran its own compiler and debugger.</p>
      <div className="mcp-captures"><figure><a href="/screenshots/mcp-iphone-selection.png" target="_blank" rel="noreferrer"><img src="/screenshots/mcp-iphone-selection.png" width={1206} height={2622} alt="iPhone Simulator editor displays Claude MCP and human selections in the shared Rust source" loading="lazy" /></a><figcaption>iPhone Simulator · shared source and named selections. Open to zoom.</figcaption></figure><figure><a href="/screenshots/mcp-ipad-local-debug.png" target="_blank" rel="noreferrer"><img src="/screenshots/mcp-ipad-local-debug.png" width={2064} height={2752} alt="iPad Simulator locally debugs MCP-shared Rust and shows actual String and Vec values" loading="lazy" /></a><figcaption>iPad Simulator · String and Vec in the local debugger. Open to zoom.</figcaption></figure></div>
    </section>
    <section id="setup" className="mcp-section"><div className="eyebrow">One-time setup on your computer</div><h2>From a download to your phone.</h2>
      <ol className="mcp-steps">
        <li><div className="mcp-step-heading"><span>01</span><h3>Install the official bridge</h3></div><p>Install <strong>Node.js 22 or newer</strong>, then use the versioned download. This command installs our packaged bridge directly from Crabrix; a registry account is not required.</p>
          <SyntaxCode language="shell" code={`npm install -g https://crabrix.com${download.url}`} /><p className="mcp-small">Prefer a manual setup? <a href={download.url} download>Download the archive</a>, extract it and use <code>node /absolute/path/package/dist/cli.mjs</code> as your MCP command.</p></li>
        <li><div className="mcp-step-heading"><span>02</span><h3>Add it to Claude Code</h3></div><SyntaxCode language="shell" code="claude mcp add --transport stdio crabrix -- crabrix-mcp" />
          <p>Open Claude Code and check <code>/mcp</code>. For a desktop MCP client, add the equivalent entry to its MCP configuration and restart it:</p>
          <SyntaxCode language="json" code={'{\n  "mcpServers": {\n    "crabrix": {\n      "command": "node",\n      "args": ["/absolute/path/package/dist/cli.mjs"]\n    }\n  }\n}'} /><p className="mcp-small">Use the full path to your Node executable if your desktop app cannot find <code>node</code>. <a href="https://code.claude.com/docs/en/mcp" target="_blank" rel="noreferrer">Claude’s MCP setup guide ↗</a></p></li>
        <li><div className="mcp-step-heading"><span>03</span><h3>Share from Crabrix or the web</h3></div><p>Open a Rust project in Crabrix, choose its Playground sharing action, and create an editable temporary link. Or open the <Link href="/playground/">web Playground</Link> and choose <strong>Share</strong>. Copy the entire link, including everything after <code>#</code>.</p><p>Give that link to Claude only when you want to grant its MCP host and model access to this room’s source. View-only links allow reading; editable links allow source changes.</p></li>
        <li><div className="mcp-step-heading"><span>04</span><h3>Give Claude a task. Keep Crabrix open.</h3></div><blockquote>Connect to this Crabrix Playground: [paste your private link]. Read the current source, add a Fibonacci function, and highlight the part you changed. Preserve everyone else’s work.</blockquote><p>Claude appears as <strong>Claude · MCP</strong>. Watch its code and selection in the phone editor. Use <strong>Run</strong> or <strong>Debug</strong> there to test the result. Save a local copy in Crabrix before the room expires.</p></li>
      </ol>
    </section>
    <section className="mcp-section mcp-split"><div><div className="eyebrow">Small, temporary, shared</div><h2>Your room stays yours.</h2><p>The relay holds AES-256-GCM ciphertext in memory. The bridge decrypts locally using the key in your link fragment. Your MCP host and its model receive the source you ask them to read; their own data policies apply.</p><p>Up to four participants, 16 text files, 64 KiB per file and 128 KiB in total. No images, package archives or credentials are transferred. Rooms expire after the chosen lifetime; a server restart can end one earlier. There is no account storage.</p><p><code>crabrix_disconnect</code> removes the bridge’s participant and releases its in-memory document. It does not close the other editors. The room creator can end the room from Share.</p></div>
      <div className="mcp-scope"><h3>Included in this bridge</h3><ul><li>Connect to an authorized room</li><li>Create a Playground and get its private link</li><li>Read current source, expiry and participants</li><li>Apply changes with a revision check</li><li>Show and receive editor selections</li><li>End a room created by this bridge</li></ul><p>Ask Claude to end a bridge-created room before disconnecting if you want to close it early. An ordinary edit link does not grant ownership.</p><p>Execution stays in Crabrix or the browser. This version exposes no shell, filesystem, Git push, package installation or remote Run/Debug command.</p></div>
    </section>
    <section className="mcp-section mcp-download-panel"><div><div className="eyebrow">Crabrix Playground MCP · v{download.version}</div><h2>Bring your AI into the room.</h2><p>A bundled Node executable. No Claude subscription or API key is included.</p></div><div className="cta-row"><a className="btn" href={download.url} download>Download bridge ↓</a><Link className="btn ghost" href="/playground/">Open Playground →</Link></div>
      <details><summary>Verify your download</summary><p>SHA-256</p><code className="mcp-digest">{download.sha256}</code><p><a href={download.noticesURL}>Third-party notices</a> · <a href={download.licenseURL}>Bridge license</a></p></details>
    </section>
  </div>;
}
