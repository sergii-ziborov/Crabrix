import type { Metadata } from "next";
import Link from "next/link";
import { AuthForm } from "@/components/auth-form";
import { AuthShell } from "@/components/auth-shell";
import { safeReturnPath } from "@/lib/auth";
export const metadata: Metadata = { title: "Create your free Academy account", robots: { index: false, follow: false } };
export default async function RegisterPage({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  const returnTo = safeReturnPath((await searchParams).next || "");
  // Keep this page mounted after registration so the one-time recovery code is visible.
  return <AuthShell title="Start learning for free." description="Choose a username and password. Every course is included.">
    <AuthForm mode="register" returnTo={returnTo} />
    <p className="auth-switch">Already have an account? <Link href={`/login/?next=${encodeURIComponent(returnTo)}`}>Sign in</Link></p>
  </AuthShell>;
}
