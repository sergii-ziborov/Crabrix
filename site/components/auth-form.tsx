"use client";
import Link from "next/link";
import { useActionState, useState } from "react";
import { changePasswordAction, deleteAccountAction, loginAction, recoverAction, registerAction, type AuthState } from "@/app/auth-actions";

type Mode = "register" | "login" | "recover" | "password" | "delete";
const actions = { register: registerAction, login: loginAction, recover: recoverAction, password: changePasswordAction, delete: deleteAccountAction };
const labels = { register: "Create free account", login: "Sign in", recover: "Recover account", password: "Update password", delete: "Delete my account" };

export function AuthForm({ mode, returnTo = "/learn/", username }: { mode: Mode; returnTo?: string; username?: string }) {
  const [state, action, pending] = useActionState<AuthState, FormData>(actions[mode], {});
  const [copied, setCopied] = useState(false);
  const [saved, setSaved] = useState(false);
  if (state.recoveryCode) return <div className="recovery-success" role="status">
    <span className="auth-success-icon" aria-hidden="true">✓</span>
    <h2>{mode === "register" ? "Your Academy is ready." : "Your account is ready."}</h2>
    <p>Save your private recovery code in your password manager. It is shown once and lets you reset your password. Keep your username too.</p>
    <code className="recovery-code">{state.recoveryCode}</code>
    <button className="btn ghost" type="button" onClick={async () => {
      try { await navigator.clipboard.writeText(state.recoveryCode!); setCopied(true); }
      catch { setCopied(false); }
    }}>{copied ? "Copied" : "Copy recovery code"}</button>
    <label className="auth-check"><input type="checkbox" checked={saved} onChange={(event) => setSaved(event.target.checked)} /><span>I have saved my username and recovery code.</span></label>
    {saved && <Link className="btn" href={state.returnTo || "/learn/"}>Continue learning →</Link>}
    <p className="auth-note">A new code replaces the previous one after every password change or recovery.</p>
  </div>;

  return <form action={action} className="auth-form">
    <input type="hidden" name="returnTo" value={returnTo} />
    {username && <input type="hidden" name="username" value={username} />}
    {["register", "login", "recover"].includes(mode) && <label>Username
      <input name="username" autoComplete="username" required minLength={3} maxLength={32} pattern="[a-zA-Z][a-zA-Z0-9_]{2,31}" placeholder="your_username" spellCheck={false} autoCapitalize="none" aria-describedby="username-help" />
      <small id="username-help">3–32 letters, numbers or underscores. Start with a letter.</small>
    </label>}
    {mode === "recover" && <label>Recovery code<input name="recoveryCode" required maxLength={64} autoComplete="off" spellCheck={false} placeholder="The private code you saved" /></label>}
    {mode === "password" && <label>Current password<input type="password" name="currentPassword" autoComplete="current-password" required minLength={12} maxLength={128} /></label>}
    <label>{["password", "recover"].includes(mode) ? "New password" : "Password"}
      <input type="password" name="password" autoComplete={["login", "delete"].includes(mode) ? "current-password" : "new-password"} required minLength={12} maxLength={128} aria-describedby="password-help" />
      <small id="password-help">At least 12 characters. Password managers and paste are welcome.</small>
    </label>
    {["register", "recover", "password"].includes(mode) && <label>Confirm password<input type="password" name="confirm" autoComplete="new-password" required minLength={12} maxLength={128} /></label>}
    {mode === "register" && <label className="auth-check"><input type="checkbox" name="terms" required /><span>I am at least 16, accept the <Link href="/terms/" target="_blank">Terms of Use</Link> and have read the <Link href="/privacy/" target="_blank">Privacy Policy</Link>.</span></label>}
    {mode === "delete" && <label>Type DELETE to confirm<input name="confirmation" required pattern="DELETE" autoComplete="off" /></label>}
    {state.error && <p className="auth-error" role="alert">{state.error}</p>}
    <button className={`btn ${mode === "delete" ? "danger" : ""}`} disabled={pending}>{pending ? "Please wait…" : labels[mode]}</button>
    {mode === "login" && <Link className="auth-link" href={`/recover/?next=${encodeURIComponent(returnTo)}`}>Forgot your password?</Link>}
    {mode === "register" && <p className="auth-note">No email required. You will receive a private recovery code after registration.</p>}
  </form>;
}
