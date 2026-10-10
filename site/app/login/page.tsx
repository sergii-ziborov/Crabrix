import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { AuthForm } from "@/components/auth-form";
import { AuthShell } from "@/components/auth-shell";
import { currentViewer, safeReturnPath } from "@/lib/auth";
export const metadata: Metadata = { title: "Sign in to Academy", robots: { index: false, follow: false } };
export default async function LoginPage({ searchParams }: { searchParams: Promise<{ next?: string; deleted?: string }> }) {
  const params = await searchParams, returnTo = safeReturnPath(params.next || "");
  if (await currentViewer()) redirect(returnTo);
  return <AuthShell title="Welcome back." description="Sign in to read complete lessons, examples and exercises.">
    {params.deleted === "1" && <p role="status" className="auth-notice">Your website account has been deleted.</p>}
    <AuthForm mode="login" returnTo={returnTo} />
    <p className="auth-switch">New here? <Link href={`/register/?next=${encodeURIComponent(returnTo)}`}>Create a free account</Link></p>
  </AuthShell>;
}
