import "server-only";
import { cache } from "react";
import { cookies } from "next/headers";
import { SESSION_SECONDS, viewerForToken } from "./auth-store";

export const secureSession = (process.env.SITE_ORIGIN || "https://crabrix.com").startsWith("https:");
export const sessionCookie = secureSession ? "__Host-crabrix_session" : "crabrix_session";
export const currentViewer = cache(async () => viewerForToken((await cookies()).get(sessionCookie)?.value));

export async function saveSession(token: string) {
  (await cookies()).set(sessionCookie, token, { httpOnly: true, secure: secureSession, sameSite: "lax", path: "/", maxAge: SESSION_SECONDS });
}
export async function clearSessionCookie() {
  (await cookies()).set(sessionCookie, "", { httpOnly: true, secure: secureSession, sameSite: "lax", path: "/", maxAge: 0 });
}
export function safeReturnPath(value: string) {
  if (!/^\/learn\/(?:[a-z0-9_-]+\/)*[a-z0-9_-]*\/?$/.test(value)) return "/learn/";
  return value.split("?")[0].split("#")[0];
}
