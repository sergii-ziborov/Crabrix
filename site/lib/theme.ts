export const THEME_STORAGE_KEY = "crabrix.theme.v1";
export const LEGACY_PLAYGROUND_PREFERENCES_KEY = "crabrix.playground.preferences.v1";
export const themeOptions = [["system", "Auto"], ["light", "Light"], ["dark", "Dark"], ["amber", "Amber Circuit"], ["cyberpunk", "Cyberpunk"]] as const;
export type ThemePreference = (typeof themeOptions)[number][0];
export type ResolvedTheme = Exclude<ThemePreference, "system">;

export const isThemePreference = (value: unknown): value is ThemePreference => themeOptions.some(([key]) => key === value);
export const resolveTheme = (preference: ThemePreference, systemIsLight: boolean): ResolvedTheme => preference === "system" ? (systemIsLight ? "light" : "dark") : preference;

type StorageLike = Pick<Storage, "getItem" | "setItem">;

/** A stored site theme wins. Otherwise a valid Playground theme moves over once. */
export function readThemePreference(storage: StorageLike): ThemePreference {
  const stored = storage.getItem(THEME_STORAGE_KEY);
  if (isThemePreference(stored)) return stored;
  let legacy: unknown;
  try { legacy = JSON.parse(storage.getItem(LEGACY_PLAYGROUND_PREFERENCES_KEY) ?? "null")?.theme; } catch { /* An unreadable old preference has nothing to migrate. */ }
  if (!isThemePreference(legacy)) return "system";
  try { storage.setItem(THEME_STORAGE_KEY, legacy); } catch { /* The session still uses the chosen theme. */ }
  return legacy;
}

/** Runs before the first paint. It repeats the rules above without any module imports. */
export const themeBootstrapScript = `(function(){var d=document.documentElement,p="system",k=${JSON.stringify(THEME_STORAGE_KEY)},o=${JSON.stringify(themeOptions.map(([key]) => key))};try{var s=localStorage.getItem(k);if(o.indexOf(s)>=0)p=s;else{var l=JSON.parse(localStorage.getItem(${JSON.stringify(LEGACY_PLAYGROUND_PREFERENCES_KEY)})||"null");if(l&&o.indexOf(l.theme)>=0){p=l.theme;localStorage.setItem(k,p)}}}catch(e){}var r=p==="system"?(matchMedia("(prefers-color-scheme: light)").matches?"light":"dark"):p;d.dataset.theme=r;d.dataset.themePreference=p;d.style.colorScheme=r==="light"?"light":"dark"})()`;
