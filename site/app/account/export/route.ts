import { currentViewer } from "@/lib/auth";
export async function GET() {
  const viewer = await currentViewer();
  if (!viewer) return new Response("Sign in first.", { status: 401, headers: { "Cache-Control": "no-store" } });
  return Response.json({ username: viewer.username, createdAt: new Date(viewer.createdAt).toISOString(), websiteLearningProgress: "Not collected" }, { headers: {
    "Cache-Control": "private, no-store", "Content-Disposition": "attachment; filename=crabrix-account.json",
  } });
}
