import { readAsset } from "@/lib/content/assets";
import { message } from "@/lib/content/repository";
export const runtime = "nodejs";
export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string; name: string }> },
) {
  try {
    const { id, name } = await params,
      result = await readAsset(id, name);
    return new Response(new Uint8Array(result.buffer), {
      headers: {
        "Content-Type": result.type,
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
      },
    });
  } catch (e) {
    return Response.json({ error: message(e) }, { status: 404 });
  }
}
