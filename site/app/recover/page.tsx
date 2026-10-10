import type { Metadata } from "next";
import Link from "next/link";
import { AuthForm } from "@/components/auth-form";
import { AuthShell } from "@/components/auth-shell";
import { safeReturnPath } from "@/lib/auth";
export const metadata: Metadata = { title: "Recover your Academy account", robots: { index: false, follow: false } };
export default async function RecoverPage({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  return <AuthShell title="Get back to learning." description="Use your username and saved recovery code to choose a new password.">
    <AuthForm mode="recover" returnTo={safeReturnPath((await searchParams).next || "")} />
    <p className="auth-note">No recovery code? We cannot reset an account without proof of access. You can create a new free account; your app projects and progress remain on your device.</p>
    <p className="auth-switch"><Link href="/login/">Back to sign in</Link></p>
  </AuthShell>;
}
