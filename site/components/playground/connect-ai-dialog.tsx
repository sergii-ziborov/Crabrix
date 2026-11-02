"use client";

import { useEffect, useState } from "react";
import type { Awareness } from "y-protocols/awareness";
import { playgroundLink, type CreatedPlayground, type PlaygroundLink } from "@/lib/playground-session";
import download from "@/lib/mcp-download.json";

const clients = {
  "claude-code": { label: "Claude Code", status: "Plugin tested", steps: `/plugin marketplace add sergii-ziborov/crabrix-sdk\n/plugin install crabrix@crabrix`, note: "The plugin registers the MCP server. Do not add a second manual server." },
  stdio: { label: "Another client with local MCP", status: "Documented configuration, not tested for each client", steps: JSON.stringify({ mcpServers: { crabrix: { command: "npx", args: ["-y", `crabrix@${download.version}`] } } }, null, 2), note: "Needs Node.js 22 or newer. Restart the client after adding this entry." },
  remote: { label: "A client with only remote MCP", status: "Not supported yet", steps: "", note: "Crabrix has no remote MCP endpoint yet. Use a client that can start a local MCP server." },
} as const;
type Client = keyof typeof clients;

/** Builds the existing handoff format next to the user's own task. Nothing leaves this page until they paste it. */
export function aiHandoffText(task: string, link: string, mode: "edit" | "view", expiresAt: number, origin: string): string {
  const handoff = { schema: "crabrix-handoff-v1", linkType: `temporary ${mode} Playground`, link, expiresAt: new Date(expiresAt).toISOString(), mode, execution: "No code is executed by opening or handing off this link." };
  return [`${task.trim() || "Work on this Crabrix Playground."}`, "", `Connect with the Crabrix MCP server. Setup: ${origin}/ai/`, "Read the current source before changing it. Running code needs separate permission from me.", "", JSON.stringify(handoff, null, 2)].join("\n");
}

function participantNames(awareness: Awareness): string[] {
  return Array.from(awareness.getStates(), ([clientID, state]) => clientID === awareness.clientID ? null : (state as { user?: { name?: string } }).user?.name ?? null).filter((name): name is string => !!name);
}

type Props = {
  link: PlaygroundLink | null; created: CreatedPlayground | null; awareness: Awareness; sharing: boolean;
  share: () => Promise<PlaygroundLink>;
  lifetime: number; setLifetime: (seconds: number) => void;
  children?: React.ReactNode;
};

export function ConnectAIDialog({ link, created, awareness, sharing, share, lifetime, setLifetime, children }: Props) {
  const [client, setClient] = useState<Client>("claude-code"), [mode, setMode] = useState<"edit" | "view">("edit"), [task, setTask] = useState("");
  const [status, setStatus] = useState(""), [names, setNames] = useState(() => participantNames(awareness));
  useEffect(() => {
    const update = () => setNames(participantNames(awareness));
    awareness.on("change", update); update();
    return () => awareness.off("change", update);
  }, [awareness]);
  const chosen = clients[client];
  const canView = !link || link.mode === "view" || !!created;

  const copy = async () => {
    setStatus("");
    try {
      const room = await share();
      const shared = room as PlaygroundLink & Partial<CreatedPlayground>;
      const access = mode === "view" && room.mode !== "view" ? (created?.view ?? shared.view) : room.access;
      if (!access) { setStatus("Only the room's creator has its view link. Ask them for it, or hand off with edit access."); return; }
      await navigator.clipboard.writeText(aiHandoffText(task, playgroundLink({ ...room, access, mode }), mode, room.expiresAt, location.origin));
      setStatus("Copied. It contains the room's secret link, so paste it only where you want this agent to read your source.");
    } catch (error) { setStatus(error instanceof Error ? error.message : String(error)); }
  };

  return <div className="pg-dialog-body pg-connect">
    <p>Connect an agent you run yourself. It joins this room as a participant and sees the source its tools read. Your model provider sees what the agent sends it.</p>
    <label>Your AI client<select value={client} onChange={event => setClient(event.target.value as Client)}>{Object.entries(clients).map(([key, value]) => <option key={key} value={key}>{value.label}</option>)}</select></label>
    <p className="pg-field-note">{chosen.status}</p>
    {chosen.steps ? <><pre className="pg-connect-steps"><code>{chosen.steps}</code></pre><button type="button" className="pg-button" onClick={() => void navigator.clipboard.writeText(chosen.steps).then(() => setStatus("Setup copied."), () => setStatus("Select and copy the text above."))}>Copy setup</button></> : null}
    <p className="pg-field-note">{chosen.note} <a href="/ai/" target="_blank" rel="noreferrer">Full instructions and SDK</a></p>
    <fieldset><legend>Give it this room</legend>
      <label>Task (optional)<textarea value={task} rows={2} onChange={event => setTask(event.target.value)} placeholder="Split the sort into its own module and explain the change." /></label>
      <div className="pg-import-row">
        <label>Access<select value={mode} onChange={event => setMode(event.target.value as "edit" | "view")}><option value="edit" disabled={link?.mode === "view"}>Edit source</option><option value="view" disabled={!canView}>View only</option></select></label>
        {!link ? <label>Room lifetime<select value={lifetime} onChange={event => setLifetime(Number(event.target.value))}><option value={3600}>1 hour</option><option value={14400}>4 hours</option><option value={43200}>12 hours</option><option value={86400}>24 hours</option></select></label> : null}
      </div>
      <button type="button" className="pg-button pg-primary" disabled={sharing} onClick={() => void copy()}>{link ? "Copy for AI" : sharing ? "Creating room…" : "Create room and copy for AI"}</button>
      {status ? <p className="pg-field-note" role="status">{status}</p> : null}
    </fieldset>
    <fieldset><legend>In this room now</legend>
      {!link ? <p>No room yet. This draft stays on this device until you create one.</p> : names.length ? <ul className="pg-import-list-plain">{names.map((name, index) => <li key={`${name}-${index}`}>{name}</li>)}</ul> : <p>Nobody else has joined. When your agent connects it appears here, which confirms the setup worked.</p>}
      {link ? <p className="pg-field-note">Names are chosen by each participant and do not prove which AI provider is connected. To remove access for everyone, end the room in Share.</p> : null}
    </fieldset>
    {children}
  </div>;
}
