"use client";

import { useState, type ReactNode } from "react";
import { sendAcademyEvent } from "@/lib/academy-events-client";

export type AgentClient = { id: string; name: string; body: ReactNode };

/**
 * One AI client's setup at a time. Every panel is rendered on the server, so all
 * instructions are readable without JavaScript; the buttons only choose which is shown.
 */
export function AgentSetup({ clients }: { clients: AgentClient[] }) {
  const [active, setActive] = useState(clients[0]?.id);
  return <div className="agent-setup">
    <div className="agent-setup-tabs" role="tablist" aria-label="Choose your AI client">
      {clients.map(client => <button key={client.id} type="button" role="tab" id={`agent-tab-${client.id}`}
        aria-selected={active === client.id} aria-controls={`agent-panel-${client.id}`}
        className={active === client.id ? "active" : undefined} onClick={() => { setActive(client.id); sendAcademyEvent("client_selected", client.id); }}>{client.name}</button>)}
    </div>
    {clients.map(client => <section key={client.id} role="tabpanel" id={`agent-panel-${client.id}`}
      aria-labelledby={`agent-tab-${client.id}`} hidden={active !== client.id} className="agent-setup-panel">
      <h3>{client.name}</h3>
      {client.body}
    </section>)}
  </div>;
}
