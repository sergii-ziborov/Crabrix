"use client";

import { useEffect } from "react";

export function MailLinks() {
  useEffect(() => {
    function openDraft(event: MouseEvent) {
      const target = event.target;
      if (!(target instanceof Element)) return;
      const button = target.closest<HTMLButtonElement>("[data-mail]");
      if (!button) return;
      const encoded = button.dataset.mail;
      if (!encoded) return;
      const to = atob(encoded);
      const form = button.dataset.form ? document.getElementById(button.dataset.form) : null;
      const area = form?.querySelector<HTMLSelectElement>("[name=area]")?.value;
      const message = form?.querySelector<HTMLTextAreaElement>("[name=message]")?.value.trim();
      const subject = area ? `Crabrix — ${area}` : button.dataset.subject || "Crabrix support";
      const query = new URLSearchParams({ subject });
      if (message) query.set("body", message);
      window.location.href = `mailto:${to}?${query.toString()}`;
    }
    document.addEventListener("click", openDraft);
    return () => document.removeEventListener("click", openDraft);
  }, []);
  return null;
}
