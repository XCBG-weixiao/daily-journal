import { isLocalWriteRequest } from "@/lib/content/request-origin";
import { NextRequest, NextResponse } from "next/server";
import { uploadAsset } from "@/lib/content/assets";
import { message } from "@/lib/content/repository";
export const runtime = "nodejs";
export async function POST(request: NextRequest) {
  if (!isLocalWriteRequest(request))
    return NextResponse.json({ error: "请求来源无效" }, { status: 403 });
  if (Number(request.headers.get("content-length")) > 11 * 1024 * 1024)
    return NextResponse.json({ error: "图片超过 10 MB" }, { status: 413 });
  try {
    const data = await request.formData(),
      file = data.get("file"),
      id = data.get("id");
    if (!(file instanceof File) || typeof id !== "string")
      throw new Error("缺少图片或记录 ID");
    if (file.size > 10 * 1024 * 1024) throw new Error("图片超过 10 MB");
    return NextResponse.json(
      await uploadAsset(id, Buffer.from(await file.arrayBuffer())),
    );
  } catch (e) {
    return NextResponse.json({ error: message(e) }, { status: 400 });
  }
}
