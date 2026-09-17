import { isLocalWriteRequest } from "@/lib/content/request-origin";
import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { ConflictError, message, saveEntry } from "@/lib/content/repository";
export async function POST(request: NextRequest) {
  if (!isLocalWriteRequest(request))
    return NextResponse.json({ error: "请求来源无效" }, { status: 403 });
  try {
    const input = z
      .object({
        meta: z.unknown(),
        body: z.string().max(2_000_000),
        expectedHash: z.string().nullable(),
      })
      .strict()
      .parse(await request.json());
    const entry = await saveEntry(input.meta, input.body, input.expectedHash);
    return NextResponse.json({ id: entry.id, hash: entry.hash });
  } catch (e) {
    return NextResponse.json(
      { error: message(e) },
      { status: e instanceof ConflictError ? 409 : 400 },
    );
  }
}
