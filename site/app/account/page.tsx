import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { AuthForm } from "@/components/auth-form";
import { currentViewer } from "@/lib/auth";
import { logoutAction } from "@/app/auth-actions";
export const metadata: Metadata = { title: "Your Academy account", robots: { index: false, follow: false } };
export default async function AccountPage() {
  const viewer = await currentViewer();
  if (!viewer) redirect("/login/");
  return <div className="site-shell account-page">
    <div className="page-intro"><p className="eyebrow">Free Academy account</p><h1>Hello, {viewer.username}.</h1><p className="lede">Every lesson is open to you. Your app projects and learning progress stay on your device.</p><div className="auth-account-actions"><Link className="btn" href="/learn/">Continue learning →</Link><form action={logoutAction}><button className="btn ghost">Sign out</button></form><Link className="auth-link" href="/account/export/">Download my account data</Link></div></div>
    <div className="account-grid"><section className="auth-panel"><h2>Change password</h2><p>This signs out your other sessions and gives you a new recovery code.</p><AuthForm mode="password" username={viewer.username} /></section>
    <section className="auth-panel"><h2>Delete account</h2><p>Deletes this website account and all its sessions. Your app data is stored separately on your device.</p><AuthForm mode="delete" username={viewer.username} /></section></div>
  </div>;
}
