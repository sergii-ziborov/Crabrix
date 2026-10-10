"use server";
import { cookies, headers } from "next/headers";
import { redirect } from "next/navigation";
import { changeAccountPassword, consumeLimit, deleteAccount, endSession, loginAccount, recoverAccount, registerAccount } from "@/lib/auth-store";
import { clearSessionCookie, currentViewer, safeReturnPath, saveSession, sessionCookie } from "@/lib/auth";

export type AuthState = { error?: string; recoveryCode?: string; returnTo?: string };
const field = (form: FormData, name: string) => String(form.get(name) || "");
async function guard(form: FormData, kind: string) {
  const request = await headers();
  if (request.get("origin") !== (process.env.SITE_ORIGIN || "https://crabrix.com")) throw new Error("Please submit this form from Crabrix.");
  const ip = request.get("x-real-ip") || "direct";
  consumeLimit(`ip:${kind}:${ip}`, kind === "register" ? 6 : 20);
  consumeLimit(`user:${kind}:${field(form, "username").trim().toLowerCase()}`, 8);
  if (kind === "register") consumeLimit("register:global", 50);
}
function failure(error: unknown): AuthState {
  const message = error instanceof Error ? error.message : "";
  const known = /^(Use |Sign-in is busy|Too many attempts|That username|The username|The current password|The password|This recovery code|Your password changed|Please |Passwords do not match)/;
  return { error: known.test(message) ? message : "We could not complete that request. Please try again." };
}
export async function registerAction(_state: AuthState, form: FormData): Promise<AuthState> {
  try {
    await guard(form, "register");
    if (await currentViewer()) throw new Error("Please sign out before creating another account.");
    if (form.get("terms") !== "on") throw new Error("Please accept the Terms of Use and read the Privacy Policy.");
    if (field(form, "password") !== field(form, "confirm")) throw new Error("Passwords do not match.");
    const account = await registerAccount(field(form, "username"), field(form, "password"));
    await saveSession(account.token);
    return { recoveryCode: account.recoveryCode, returnTo: safeReturnPath(field(form, "returnTo")) };
  } catch (error) { return failure(error); }
}
export async function loginAction(_state: AuthState, form: FormData): Promise<AuthState> {
  try {
    await guard(form, "login");
    const session = await loginAccount(field(form, "username"), field(form, "password"));
    await saveSession(session.token);
  } catch (error) { return failure(error); }
  redirect(safeReturnPath(field(form, "returnTo")));
}
export async function recoverAction(_state: AuthState, form: FormData): Promise<AuthState> {
  try {
    await guard(form, "recover");
    if (field(form, "password") !== field(form, "confirm")) throw new Error("Passwords do not match.");
    const session = await recoverAccount(field(form, "username"), field(form, "recoveryCode"), field(form, "password"));
    await saveSession(session.token);
    return { recoveryCode: session.recoveryCode, returnTo: safeReturnPath(field(form, "returnTo")) };
  } catch (error) { return failure(error); }
}
export async function changePasswordAction(_state: AuthState, form: FormData): Promise<AuthState> {
  try {
    await guard(form, "password");
    const viewer = await currentViewer();
    if (!viewer) throw new Error("Please sign in again.");
    if (field(form, "password") !== field(form, "confirm")) throw new Error("Passwords do not match.");
    const session = await changeAccountPassword(viewer.id, field(form, "currentPassword"), field(form, "password"));
    await saveSession(session.token);
    return { recoveryCode: session.recoveryCode, returnTo: "/learn/" };
  } catch (error) { return failure(error); }
}
export async function deleteAccountAction(_state: AuthState, form: FormData): Promise<AuthState> {
  try {
    await guard(form, "delete");
    const viewer = await currentViewer();
    if (!viewer) throw new Error("Please sign in again.");
    if (field(form, "confirmation") !== "DELETE") throw new Error("Please type DELETE to confirm.");
    await deleteAccount(viewer.id, field(form, "password"));
    await clearSessionCookie();
  } catch (error) { return failure(error); }
  redirect("/login/?deleted=1");
}
export async function logoutAction() {
  if ((await headers()).get("origin") !== (process.env.SITE_ORIGIN || "https://crabrix.com")) throw new Error("Invalid origin");
  endSession((await cookies()).get(sessionCookie)?.value);
  await clearSessionCookie();
  redirect("/learn/");
}
