import Link from "next/link";
import { notFound } from "next/navigation";
import { pageMetadata, pageUrl, breadcrumbs } from "@/lib/seo";
import { StructuredData } from "@/components/structured-data";
import { SyntaxCode } from "@/components/SyntaxCode";
import { CopyText } from "@/components/copy-text";
import { AgentSetup } from "@/components/agent-setup";
import { ACADEMY_MCP_URL, ACADEMY_SDK_VERSION, FEEDBACK_MAIL, learningPrompts } from "@/lib/ai-learning";
import { academyPath, learningPaths, teachingContractVersion } from "@/lib/academy";
import { aiLearningEnabled } from "@/lib/flags";
import { AIFeedback, AIPageView } from "@/components/ai-learning-client";

export const metadata = pageMetadata({
  title: "Learn Rust with Your AI Agent — Claude, Codex and Cursor with Crabrix Academy",
  description: "Connect Claude, Claude Code, Codex or Cursor to Crabrix Academy. Your agent teaches from real Rust lessons and exercises, and you write the code. Free, no account.",
  path: "/learn/with-ai/",
});

export default function LearnWithAIPage() {
  if (!aiLearningEnabled()) notFound();
  const paths = learningPaths();
  const cursorConfig = `{\n  "mcpServers": {\n    "crabrix-academy": {\n      "url": "${ACADEMY_MCP_URL}"\n    }\n  }\n}`;
  const clients = [
    { id: "claude", name: "Claude", body: <>
      <p>In Claude on the web, desktop or mobile: <strong>Customize → Connectors → + → Add custom connector</strong>. Name it <em>Crabrix Academy</em> and paste this URL:</p>
      <SyntaxCode language="shell" code={ACADEMY_MCP_URL} /><CopyText text={ACADEMY_MCP_URL} label="Copy URL" event="instructions_copied" detail="claude" />
      <p>No sign-in. Then start a chat with one of the prompts below. A connector you add on the web is also available in the Claude app on your phone or tablet.</p></> },
    { id: "claude-code", name: "Claude Code", body: <>
      <p>Add the Academy as a remote MCP server:</p>
      <SyntaxCode language="shell" code={`claude mcp add --transport http crabrix-academy ${ACADEMY_MCP_URL}`} />
      <CopyText text={`claude mcp add --transport http crabrix-academy ${ACADEMY_MCP_URL}`} event="instructions_copied" detail="claude-code" />
      <p>Or install the Crabrix plugin ({ACADEMY_SDK_VERSION} or newer). It adds a local Academy server, the <code>crabrix-learn-rust</code> skill and the shared Playground; an existing installation keeps its handoff skill and rooms.</p>
      <SyntaxCode language="shell" code={"/plugin marketplace add sergii-ziborov/crabrix-sdk\n/plugin install crabrix@crabrix"} /></> },
    { id: "codex", name: "Codex", body: <>
      <SyntaxCode language="shell" code={`codex mcp add crabrix-academy --url ${ACADEMY_MCP_URL}`} />
      <CopyText text={`codex mcp add crabrix-academy --url ${ACADEMY_MCP_URL}`} event="instructions_copied" detail="codex" />
      <p>To run the Academy locally instead (Node.js 22 or newer), add <code>codex mcp add crabrix-academy -- npx -y crabrix@{ACADEMY_SDK_VERSION} academy</code>. Your existing <code>crabrix</code> server for Playground rooms stays as it is.</p></> },
    { id: "cursor", name: "Cursor", body: <>
      <p>Add this server to <code>~/.cursor/mcp.json</code>, then restart Cursor:</p>
      <SyntaxCode language="json" code={cursorConfig} /><CopyText text={cursorConfig} label="Copy JSON" event="instructions_copied" detail="cursor" /></> },
    { id: "other", name: "Other MCP client", body: <>
      <p>Add a remote MCP server with Streamable HTTP and no authentication:</p>
      <SyntaxCode language="shell" code={ACADEMY_MCP_URL} /><CopyText text={ACADEMY_MCP_URL} label="Copy URL" event="instructions_copied" detail="other" />
      <p>Clients that run local servers can start the same read-only tools with <code>npx -y crabrix@{ACADEMY_SDK_VERSION} academy</code> (Node.js 22 or newer). Playground rooms keep using the <code>crabrix</code> server you may already have.</p></> },
  ];
  return (
    <div className="site-shell with-ai-page">
      <StructuredData data={{ "@context": "https://schema.org", "@graph": [
        { "@type": "WebPage", name: "Learn Rust with Your AI Agent", url: pageUrl("/learn/with-ai/"), inLanguage: "en",
          isPartOf: { "@type": "WebSite", name: "Crabrix", url: pageUrl("/") } },
        breadcrumbs([{ name: "Crabrix", path: "/" }, { name: "Learn Rust", path: "/learn/" }, { name: "Learn with AI", path: "/learn/with-ai/" }]),
      ] }} />
      <AIPageView page="with-ai" />
      <nav className="breadcrumbs" aria-label="Breadcrumbs"><Link prefetch={false} href="/learn">Learn</Link><span>/</span><span>Learn with AI</span></nav>
      <div className="page-intro">
        <p className="eyebrow">Optional · free · no account</p>
        <h1>Learn Rust with your AI agent.</h1>
        <p className="lede">Your AI tutor. Crabrix Academy. Real Rust code. Connect Claude, Codex, Cursor or another MCP client to the Academy: your agent teaches from the real lessons and exercises, and you write the code and run it in Crabrix.</p>
        <p className="card-meta">AI is optional. Every lesson, exercise and the Playground work exactly as before without it.</p>
      </div>

      <section className="unit-panel" aria-labelledby="three-ways">
        <h2 id="three-ways">Three ways to learn, one Academy</h2>
        <div className="catalog-grid">
          <div className="course-card"><span className="card-kicker">On your own</span><h3>Crabrix Academy</h3><p>Lessons, quick checks and compiler labs on the web and in the app. Progress stays on your device.</p><Link prefetch={false} href="/learn/">Browse the courses →</Link></div>
          <div className="course-card"><span className="card-kicker">With your agent</span><h3>AI-assisted</h3><p>Read a lesson here and ask your agent about it: every lesson has a <em>Learn this lesson with AI</em> prompt.</p></div>
          <div className="course-card"><span className="card-kicker">Agent first</span><h3>In Claude, Codex or Cursor</h3><p>Your agent finds lessons through Crabrix Academy MCP, explains them and gives you exercises.</p></div>
        </div>
      </section>

      <section className="unit-panel" id="connect" aria-labelledby="connect-heading">
        <h2 id="connect-heading">Connect your agent</h2>
        <p>The Academy server is read-only and public: it serves lessons, exercises, examples and learning paths. It never sees your progress, your projects or your Playground rooms.</p>
        <AgentSetup clients={clients} />
      </section>

      <section className="unit-panel" aria-labelledby="prompts">
        <h2 id="prompts">Start with a prompt</h2>
        <div className="prompt-list">
          {learningPrompts.map(prompt => <div className="prompt-card" key={prompt.id}>
            <h3>{prompt.title}</h3><blockquote>{prompt.text}</blockquote><CopyText text={prompt.text} label="Copy prompt" event="prompt_copied" detail={prompt.id} />
          </div>)}
        </div>
      </section>

      <section className="unit-panel" aria-labelledby="paths">
        <h2 id="paths">Learning paths</h2>
        <p>A path is another way through the same lessons. A lesson you finished anywhere counts on every path that contains it. Ask your agent for a path by name.</p>
        <div className="lesson-list">
          {paths.map(path => {
            const first = (academyPath(path.id)?.steps as { url: string; title: string }[] | undefined)?.[0];
            return <a className="lesson-link path-link" key={path.id} href={first?.url ?? "/learn/"}>
              <span>{path.title}</span><small>{path.steps.length} lessons · {path.audience}</small></a>;
          })}
        </div>
        <p>Coming from another language? <Link prefetch={false} href="/learn/rust-for-c-developers/">Rust for C Developers</Link> and <Link prefetch={false} href="/learn/rust-for-nodejs-developers/">Rust for Node.js Developers</Link> put your current habits next to Rust.</p>
      </section>

      <section className="unit-panel" aria-labelledby="continue">
        <h2 id="continue">Continue where you left off</h2>
        <p>Your progress stays where you earned it. Nothing is synchronised between the Crabrix app, this website and your agent automatically, so you choose what your agent may know:</p>
        <ul className="learning-state-steps">
          <li><strong>From the Crabrix app</strong> (iPhone and iPad, in the next app version): <em>Learn → Learn with AI → Continue learning</em>. Switch on <em>Include my completed lessons</em>, then copy or share your learning state and paste it into your agent with the <em>Continue learning</em> prompt. It works from a phone alone.</li>
          <li><strong>From a backup file</strong>, on a computer: with the local Academy server (<code>npx -y crabrix@{ACADEMY_SDK_VERSION} academy</code>), ask your agent to read your <code>.crabrixprogress</code> file. It is read on your computer and is not uploaded by Crabrix.</li>
          <li><strong>Without either</strong>: tell your agent which lesson you are on. It assumes nothing else.</li>
        </ul>
        <p>Your agent can keep its notes in the same file: your path, mode, current lesson, a short summary and what to review. Combining two files only ever adds the lessons the app recorded; an older or partial file never removes any, and the file never changes your progress in the app. It holds no code, room links, passwords or keys. Format: <a href="/api/academy/v1/learning-state.schema.json">AI Learning State v1</a>.</p>
      </section>

      <section className="unit-panel" aria-labelledby="honest">
        <h2 id="honest">What your agent can and cannot do</h2>
        <ul>
          <li>It teaches from real Crabrix lessons and links each one, so you can always read the original.</li>
          <li>It gives hints before solutions and shows a full solution only when you ask for it.</li>
          <li>Its review is an AI review. Only Crabrix checks in the app record a lesson as passed, and the agent cannot change your progress.</li>
          <li>It knows what you have finished only if you tell it. Nothing is synchronised between your devices and your agent automatically.</li>
          <li>Code runs on your device: in the Playground or the app, and through an agent only after you allow it there.</li>
          <li>Whatever you paste into a chat goes to your agent&rsquo;s model provider under its own terms.</li>
        </ul>
        <p className="card-meta">Agents follow the <a href="/api/academy/v1/teaching-contract.md">Crabrix teaching contract</a> (version {teachingContractVersion()}). Developers can read the public <a href="/api/academy/v1/index.json">Academy API</a>.</p>
      </section>

      <AIFeedback mode="always" mail={FEEDBACK_MAIL} />
    </div>
  );
}
