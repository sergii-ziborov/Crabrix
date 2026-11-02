"use client";

import { useCallback, useSyncExternalStore } from "react";
import { isThemePreference, readThemePreference, resolveTheme, THEME_STORAGE_KEY, themeOptions, type ThemePreference } from "@/lib/theme";

const listeners = new Set<() => void>();
let sessionPreference: ThemePreference | null = null;

function currentPreference(): ThemePreference {
  if (sessionPreference) return sessionPreference;
  try { sessionPreference = readThemePreference(localStorage); }
  catch { sessionPreference = "system"; }
  return sessionPreference;
}

function applyTheme(preference: ThemePreference) {
  const root = document.documentElement, resolved = resolveTheme(preference, matchMedia("(prefers-color-scheme: light)").matches);
  root.dataset.theme = resolved; root.dataset.themePreference = preference;
  root.style.colorScheme = resolved === "light" ? "light" : "dark";
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  const notify = () => { applyTheme(currentPreference()); for (const each of listeners) each(); };
  const storage = (event: StorageEvent) => { if (event.key === THEME_STORAGE_KEY) { sessionPreference = isThemePreference(event.newValue) ? event.newValue : "system"; notify(); } };
  const media = matchMedia("(prefers-color-scheme: light)");
  window.addEventListener("storage", storage); media.addEventListener("change", notify);
  return () => { listeners.delete(listener); window.removeEventListener("storage", storage); media.removeEventListener("change", notify); };
}

export function useThemePreference(): [ThemePreference, (value: ThemePreference) => void] {
  const preference = useSyncExternalStore(subscribe, currentPreference, () => "system" as ThemePreference);
  const set = useCallback((value: ThemePreference) => {
    sessionPreference = value;
    try { localStorage.setItem(THEME_STORAGE_KEY, value); } catch { /* Storage may be unavailable; the session keeps the choice. */ }
    applyTheme(value);
    for (const each of listeners) each();
  }, []);
  return [preference, set];
}

export function ThemeSelect({ className }: { className?: string }) {
  const [preference, setPreference] = useThemePreference();
  return <label className={className ?? "site-theme"}><span className="visually-hidden">Site theme</span>
    <select value={preference} aria-label="Site theme" onChange={event => setPreference(event.target.value as ThemePreference)}>
      {themeOptions.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
    </select>
  </label>;
}
