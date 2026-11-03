"use client";

import { useEffect, useState } from "react";
import type { Awareness } from "y-protocols/awareness";
import type { CreatedPlayground, PlaygroundLink } from "@/lib/playground-session";
import { agentLink, fetchAgentAccess } from "@/lib/playground-agent";
import download from "@/lib/mcp-download.json";

const AGENT_LINK_PLACEHOLDER = "<agent link>";
const SERVER = "crabrix-room";
const LIFETIMES: [number, string][] = [[3600, "1 hour"], [14400, "4 hours"], [43200, "12 hours"], [86400, "24 hours"]];
/** crabrix_connect takes agent links from 0.5.0; before that only the remote MCP works with them. */
const LOCAL_TAKES_AGENT_LINKS = Number(download.version.split(".")[0]) > 0 || Number(download.version.split(".")[1]) >= 5;

/** `install` puts the client's one-click install button in the step, before `codeLabel` and `code`. */
type Step = { text: React.ReactNode; install?: true; codeLabel?: React.ReactNode; code?: (url: string) => string };
type Way = { title: string; steps: Step[] };
type Guide = { label: string; ways: Way[]; local?: React.ReactNode; note?: string };

/** One remote MCP server per room, named the same in every client. */
const cursorInstall = (url: string) => `cursor://anysphere.cursor-deeplink/mcp/install?name=${SERVER}&config=${encodeURIComponent(btoa(JSON.stringify({ url })))}`;

// Setup per agent, checked against each vendor's MCP documentation in November 2026.
const guides = {
  claude: {
    label: "Claude",
    ways: [
      { title: "Claude app: claude.ai, desktop or mobile", steps: [
        { text: <>Open <b>Customize → Connectors</b>, press <b>+</b> and choose <b>Add custom connector</b>.</> },
        { text: <>Name it <code>Crabrix room</code> and paste the agent link as its URL.</>, code: url => url },
        { text: <>In a chat, turn on <b>Crabrix room</b> under Connectors and give Claude the task.</> },
      ] },
      { title: "Claude Code", steps: [{ text: "Run this in your terminal, then start a new session:", code: url => `claude mcp add --transport http ${SERVER} ${url}` }] },
    ],
    local: <>With the Crabrix plugin in Claude Code (<code>/plugin marketplace add sergii-ziborov/crabrix-sdk</code>, then <code>/plugin install crabrix@crabrix</code>), skip the setup and paste the agent link into the chat.</>,
  },
  codex: {
    label: "Codex",
    ways: [{ title: "Codex CLI, IDE extension or app", steps: [
      { text: "Run this in your terminal:", code: url => `codex mcp add ${SERVER} --url ${url}` },
      { text: <>Or add it to <code>~/.codex/config.toml</code>:</>, code: url => `[mcp_servers.${SERVER}]\nurl = "${url}"` },
    ] }],
    local: <>With Crabrix MCP added once (<code>codex mcp add crabrix -- npx -y crabrix@{download.version}</code>), skip the setup and paste the agent link into the chat.</>,
  },
  cursor: {
    label: "Cursor",
    ways: [{ title: "Cursor", steps: [
      { text: <>Press <b>Add to Cursor</b> and confirm in Cursor.</>, install: true, codeLabel: <>Or add this to <code>~/.cursor/mcp.json</code>:</>, code: url => JSON.stringify({ mcpServers: { [SERVER]: { url } } }, null, 2) },
      { text: <>In Agent chat, check that <b>{SERVER}</b> is on under MCP and give the task.</> },
    ] }],
    local: <>With Crabrix MCP in Cursor (<code>npx -y crabrix@{download.version}</code>), skip the setup and paste the agent link into the chat.</>,
  },
  grok: {
    label: "Grok",
    ways: [{ title: "grok.com", steps: [
      { text: <>Open <b>Connectors</b>, choose <b>New connector → Custom</b>.</> },
      { text: "Paste the agent link as the server URL and save.", code: url => url },
      { text: "In a chat, turn the connector on and give Grok the task." },
    ] }],
    note: "Custom connectors may need a paid Grok plan.",
  },
  other: {
    label: "Other",
    ways: [{ title: "Any client with remote MCP", steps: [{ text: "Add the agent link as a remote MCP server (Streamable HTTP, no sign-in).", code: url => url }] }],
    local: <>A client that runs local MCP servers can use <code>npx -y crabrix@{download.version}</code> (Node.js 22+) and take the agent link in the chat.</>,
  },
} satisfies Record<string, Guide>;
type AgentName = keyof typeof guides;

/** The user's task with the room's agent link. Nothing leaves this page until they paste it. */
export function aiHandoffText(task: string, link: string, mode: "edit" | "view", expiresAt: number, origin: string): string {
  const handoff = { schema: "crabrix-handoff-v1", linkType: `temporary ${mode} Playground agent link`, link, expiresAt: new Date(expiresAt).toISOString(), mode, execution: "No code is executed by opening or handing off this link." };
  return [`${task.trim() || "Work on this Crabrix Playground."}`, "", `Agent link: ${link}`, "If the crabrix-room MCP server is connected, use its tools. Otherwise call crabrix_connect with this link (Crabrix MCP 0.5.0 or newer), or add the link as a remote MCP server (Streamable HTTP).", `Setup: ${origin}/ai/`, "Read the current source before changing it. Running code needs separate permission from me.", "", JSON.stringify(handoff, null, 2)].join("\n");
}

function participantNames(awareness: Awareness): string[] {
  return Array.from(awareness.getStates(), ([clientID, state]) => clientID === awareness.clientID ? null : (state as { user?: { name?: string } }).user?.name ?? null).filter((name): name is string => !!name);
}

/** The person token whose agent counterpart has the chosen mode, or null when this tab does not hold it. */
function personAccess(room: PlaygroundLink, created: CreatedPlayground | null, mode: "edit" | "view"): string | null {
  if (mode === "edit") return room.mode === "edit" ? room.access : null;
  return room.mode === "view" ? room.access : created?.view ?? (room as Partial<CreatedPlayground>).view ?? null;
}

function Segmented<T extends string | number>({ label, value, options, onChange }: { label: string; value: T; options: [T, string, boolean?][]; onChange: (value: T) => void }) {
  return <div className="pg-segmented-field"><span>{label}</span><div className="pg-segmented" role="radiogroup" aria-label={label}>
    {options.map(([option, text, disabled]) => <button key={String(option)} type="button" role="radio" aria-checked={value === option} disabled={disabled} onClick={() => onChange(option)}>{text}</button>)}
  </div></div>;
}

type Agent = { key: string; url: string; mode: "edit" | "view"; expiresAt: number };
type Props = {
  link: PlaygroundLink | null; created: CreatedPlayground | null; awareness: Awareness; sharing: boolean;
  share: () => Promise<PlaygroundLink>;
  lifetime: number; setLifetime: (seconds: number) => void;
  children?: React.ReactNode;
};

export function ConnectAIDialog({ link, created, awareness, sharing, share, lifetime, setLifetime, children }: Props) {
  const [name, setName] = useState<AgentName>("claude"), [mode, setMode] = useState<"edit" | "view">(link?.mode === "view" ? "view" : "edit"), [task, setTask] = useState("");
  const [status, setStatus] = useState(""), [names, setNames] = useState(() => participantNames(awareness));
  const [agent, setAgent] = useState<Agent | null>(null);
  useEffect(() => {
    const update = () => setNames(participantNames(awareness));
    awareness.on("change", update); update();
    return () => awareness.off("change", update);
  }, [awareness]);
  const guide: Guide = guides[name];
  const canView = !link || link.mode === "view" || !!created;
  const current = link && agent?.key === `${link.id}:${mode}` ? agent : null;
  const url = current?.url ?? AGENT_LINK_PLACEHOLDER;

  const resolve = async (room: PlaygroundLink): Promise<Agent | null> => {
    const key = `${room.id}:${mode}`;
    if (agent?.key === key) return agent;
    const access = personAccess(room, created, mode);
    if (!access) { setStatus("Only the room's creator has its view link. Ask them for it, or connect the agent with edit access."); return null; }
    const result = await fetchAgentAccess(room.id, access);
    const next = { key, url: agentLink(room, result.access, location.origin), mode: result.mode, expiresAt: result.expiresAt };
    setAgent(next);
    return next;
  };

  // Shows the real link in the setup once a room exists.
  useEffect(() => {
    if (!link || agent?.key === `${link.id}:${mode}` || !personAccess(link, created, mode)) return;
    let live = true;
    fetchAgentAccess(link.id, personAccess(link, created, mode)!).then(result => { if (live) setAgent({ key: `${link.id}:${mode}`, url: agentLink(link, result.access, location.origin), mode: result.mode, expiresAt: result.expiresAt }); }, error => { if (live) setStatus(error instanceof Error ? error.message : String(error)); });
    return () => { live = false; };
  }, [link, created, mode, agent?.key]);

  /** Creates the room when there is none yet, so every copy carries a working link. */
  const withAgent = async (use: (next: Agent) => Promise<void> | void) => {
    setStatus("");
    try {
      const next = await resolve(await share());
      if (next) await use(next);
    } catch (error) { setStatus(error instanceof Error ? error.message : String(error)); }
  };
  const copy = (text: (next: Agent) => string, done: (next: Agent) => string) => withAgent(async next => { await navigator.clipboard.writeText(text(next)); setStatus(done(next)); });
  const linkWarning = (next: Agent) => `The agent link contains the room's key, so give it only to an agent you want to ${next.mode === "edit" ? "read and edit" : "read"} your source.`;
  const creating = sharing ? "Creating room…" : null;

  return <div className="pg-dialog-body pg-connect">
    <p>Give an AI agent its own link to this room. It joins as a participant and reads{mode === "edit" ? " and edits" : ""} the files. People keep using the links in Share; both end with the room.</p>
    <div className="pg-agent-picker" role="tablist" aria-label="AI agent">
      {(Object.keys(guides) as AgentName[]).map(key => <button key={key} type="button" role="tab" aria-selected={name === key} onClick={() => setName(key)}>{guides[key].label}</button>)}
    </div>

    <section className="pg-connect-section" aria-labelledby="pg-agent-link-heading">
      <h3 id="pg-agent-link-heading"><span className="pg-step-number">1</span>Agent link</h3>
      <div className="pg-connect-options">
        <Segmented label="Access" value={mode} onChange={setMode} options={[["edit", "Edit", link?.mode === "view"], ["view", "View only", !canView]]} />
        {!link ? <Segmented label="Room lifetime" value={lifetime} onChange={setLifetime} options={LIFETIMES.map(([seconds, text]) => [seconds, text])} /> : null}
      </div>
      {current ? <div className="pg-copy-field"><input readOnly aria-label={`Agent link, ${current.mode === "edit" ? "edit" : "view only"}`} value={current.url} onFocus={event => event.target.select()} /><button type="button" className="pg-button" onClick={() => void copy(next => next.url, next => `Agent link copied. ${linkWarning(next)}`)}>Copy</button></div>
        : <button type="button" className="pg-button pg-primary" disabled={sharing} onClick={() => void withAgent(() => setStatus("The room is ready. Its agent link is filled into the setup below."))}>{creating ?? (link ? "Get agent link" : "Create room and get agent link")}</button>}
      <p className="pg-field-note">{link ? `Expires with the room, ${new Date(link.expiresAt).toLocaleString()}.` : "No room exists until you ask for a link. People and agents then share its lifetime."}</p>
    </section>

    <section className="pg-connect-section" role="tabpanel" aria-labelledby="pg-agent-setup-heading">
      <h3 id="pg-agent-setup-heading"><span className="pg-step-number">2</span>Connect {guide.label}</h3>
      {guide.ways.map(way => <div key={way.title} className="pg-connect-way">
        {guide.ways.length > 1 ? <h4>{way.title}</h4> : null}
        <ol className="pg-connect-steps-list">{way.steps.map((step, index) => <li key={index}><div>
          <span>{step.text}</span>
          {step.install ? <button type="button" className="pg-button pg-primary pg-install-button" disabled={sharing} onClick={() => void withAgent(next => { location.href = cursorInstall(next.url); setStatus("Cursor asks you to confirm the new MCP server."); })}>{creating ?? "Add to Cursor"}</button> : null}
          {step.codeLabel ? <span>{step.codeLabel}</span> : null}
          {step.code ? <div className="pg-code-copy"><pre><code>{step.code(url)}</code></pre><button type="button" className="pg-button" disabled={sharing} onClick={() => void copy(next => step.code!(next.url), () => "Copied with this room's agent link.")}>Copy</button></div> : null}
        </div></li>)}</ol>
      </div>)}
      {guide.note ? <p className="pg-field-note">{guide.note}</p> : null}
      {guide.local && LOCAL_TAKES_AGENT_LINKS ? <details className="pg-connect-local"><summary>Crabrix MCP already installed?</summary><p>{guide.local} The key then stays on your computer.</p></details> : null}
      <p className="pg-field-note">Connected this way, the agent works through the Crabrix server, which decrypts this room&rsquo;s source while it is connected. <a href="/ai/" target="_blank" rel="noreferrer">Full instructions and SDK</a></p>
    </section>

    <section className="pg-connect-section" aria-labelledby="pg-agent-task-heading">
      <h3 id="pg-agent-task-heading"><span className="pg-step-number">3</span>Give it the task</h3>
      <label>Task (optional)<textarea value={task} rows={2} onChange={event => setTask(event.target.value)} placeholder="Split the sort into its own module and explain the change." /></label>
      <button type="button" className="pg-button pg-primary" disabled={sharing} onClick={() => void copy(next => aiHandoffText(task, next.url, next.mode, next.expiresAt, location.origin), next => `Copied. ${linkWarning(next)} Paste it into the agent's chat.`)}>{creating ?? (link ? "Copy message for the agent" : "Create room and copy message for the agent")}</button>
      {status ? <p className="pg-field-note" role="status">{status}</p> : null}
    </section>

    <fieldset><legend>In this room now</legend>
      {!link ? <p>No room yet. This draft stays on this device until you create one.</p> : names.length ? <ul className="pg-import-list-plain">{names.map((person, index) => <li key={`${person}-${index}`}>{person}</li>)}</ul> : <p>Nobody else has joined. When your agent connects it appears here, which confirms the setup worked.</p>}
      {link ? <p className="pg-field-note">Names are chosen by each participant and do not prove which AI provider is connected. To remove access for everyone, end the room in Share.</p> : null}
    </fieldset>
    {children}
  </div>;
}
