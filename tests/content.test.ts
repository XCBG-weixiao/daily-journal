import { beforeEach, afterEach, describe, it, expect } from "vitest";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import {
  snapshot,
  saveEntry,
  ConflictError,
  hash,
} from "../src/lib/content/repository";
import { encode } from "../src/lib/content/markdown";
import { parseMeta, Activity, Entry } from "../src/lib/content/schema";
import { summarize, ordered } from "../src/lib/content/aggregate";
import { monthDays, yearDays, localDate } from "../src/lib/content/dates";
import { uploadAsset, readAsset } from "../src/lib/content/assets";
const now = new Date("2026-09-17T12:00:00+08:00");
const activity: Activity = {
  schema_version: 1,
  id: "running",
  name: "跑步",
  icon: "🏃",
  color: "#3D8060",
  metrics: ["duration_min", "distance_km"],
  body: "",
};
const id = "10000000-0000-4000-8000-000000000001";
const meta = {
  schema_version: 1 as const,
  id,
  kind: "event" as const,
  title: "晨跑",
  date: "2026-09-14",
  activity_id: "running",
  metrics: { duration_min: 32, distance_km: 5.2 },
};
let root: string;
let old: string | undefined;
beforeEach(async () => {
  old = process.env.CONTENT_DIR;
  root = await fs.mkdtemp(path.join(os.tmpdir(), "journal-test-"));
  process.env.CONTENT_DIR = root;
  for (const dir of ["entries", "activities", "assets"])
    await fs.mkdir(path.join(root, dir));
  await fs.writeFile(
    path.join(root, "settings.json"),
    JSON.stringify({
      schema_version: 1,
      timezone: "Asia/Shanghai",
      week_starts_on: 1,
    }),
  );
  const { body, ...a } = activity;
  await fs.writeFile(path.join(root, "activities/running.md"), encode(a, body));
});
afterEach(async () => {
  if (old === undefined) delete process.env.CONTENT_DIR;
  else process.env.CONTENT_DIR = old;
  await fs.rm(root, { recursive: true, force: true });
});
describe("统计和日期", () => {
  it("同日多次按次数计算，日记不重复计数，缺失不是零", () => {
    const e = (m: object): Entry => ({ ...meta, ...m, body: "", hash: "" });
    const records = [
      e({ date: "2026-09-13", metrics: { duration_min: 42, distance_km: 7 } }),
      e({}),
      e({ metrics: { duration_min: 20, distance_km: 3 } }),
      e({ kind: "journal", activity_id: undefined, metrics: undefined }),
    ];
    expect(summarize(records)).toMatchObject({
      count: 3,
      days: 2,
      sums: { duration_min: 94, distance_km: 15.2, pages: null },
    });
    const s = summarize([
      e({ metrics: { duration_min: 0 } }),
      e({ metrics: {} }),
    ]);
    expect(s.averageDuration).toBe(0);
    expect(s.samples.duration_min).toBe(1);
  });
  it("42 格月份、闰年和可能的 54 周布局", () => {
    expect(monthDays("2026-09")).toHaveLength(42);
    expect(monthDays("2026-09")[0]).toBe("2026-08-31");
    expect(yearDays(2024).filter(Boolean)).toHaveLength(366);
    expect(yearDays(2024)).toContain("2024-02-29");
    expect(yearDays(2012)).toHaveLength(378);
    expect(yearDays(2025).filter(Boolean)).toHaveLength(365);
  });
  it("时区、跨午夜开始日、未来和无效日期校验", () => {
    expect(localDate(new Date("2026-09-13T18:00:00Z"))).toBe("2026-09-14");
    expect(
      parseMeta(
        { ...meta, started_at: "2026-09-13T18:00:00Z" },
        [activity],
        now,
      ).date,
    ).toBe("2026-09-14");
    expect(
      parseMeta(
        {
          ...meta,
          started_at: "2026-09-14T23:30:00+08:00",
          metrics: { duration_min: 90 },
        },
        [activity],
        now,
      ).date,
    ).toBe("2026-09-14");
    for (const patch of [
      { date: "2026-02-30" },
      { date: "2026-09-18" },
      { started_at: "2026-09-13T00:00:00Z" },
      { started_at: "2026-09-18T08:00:00+08:00" },
      { unknown: true },
      { activity_id: "missing" },
      { metrics: { pages: 3 } },
    ])
      expect(() => parseMeta({ ...meta, ...patch }, [activity], now)).toThrow();
  });
  it("无时间在后，同一时刻按 ID 稳定排序", () => {
    const e = (m: object): Entry => ({ ...meta, ...m, body: "", hash: "" });
    const a = e({ id: "b", started_at: "2026-09-14T09:00:00+08:00" }),
      b = e({ id: "a", started_at: "2026-09-14T09:00:00+08:00" }),
      c = e({ id: "c" });
    expect(ordered([c, a, b]).map((e) => e.id)).toEqual(["a", "b", "c"]);
  });
});
describe("真实文件读写", () => {
  it("保存、重新读取、外部修改与删除", async () => {
    const saved = await saveEntry(meta, "正文\n\n第二段", null, now);
    expect(saved.id).toBe(id);
    expect((await snapshot(now)).entries[0].body).toContain("第二段");
    const updated = await saveEntry(
      { ...meta, title: "修改标题" },
      "保留正文",
      saved.hash,
      now,
    );
    expect(updated.hash).not.toBe(saved.hash);
    await fs.writeFile(
      path.join(root, "entries", id + ".md"),
      encode({ ...meta, metrics: { distance_km: 10 } }, "外部编辑"),
    );
    expect(summarize((await snapshot(now)).entries).sums.distance_km).toBe(10);
    await fs.unlink(path.join(root, "entries", id + ".md"));
    expect((await snapshot(now)).entries).toHaveLength(0);
  });
  it("拒绝重复新建、旧版本保存和并发覆盖", async () => {
    const saved = await saveEntry(meta, "original", null, now);
    await expect(
      saveEntry(meta, "duplicate", null, now),
    ).rejects.toBeInstanceOf(ConflictError);
    const results = await Promise.allSettled([
      saveEntry(meta, "one", saved.hash, now),
      saveEntry(meta, "two", saved.hash, now),
    ]);
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect(results.filter((r) => r.status === "rejected")).toHaveLength(1);
  });
  it("写入失败不会产生成功返回", async () => {
    await fs.rm(path.join(root, "entries"), { recursive: true });
    await expect(saveEntry(meta, "failed", null, now)).rejects.toThrow();
  });
  it("错误 YAML、重复 ID、未知字段和活动可定位", async () => {
    await saveEntry(meta, "valid", null, now);
    await fs.writeFile(
      path.join(root, "entries/z-duplicate.md"),
      encode(meta, ""),
    );
    await fs.writeFile(
      path.join(root, "entries/bad.md"),
      "---\n: [broken\n---\n",
    );
    await fs.writeFile(
      path.join(root, "entries/unknown.md"),
      encode(
        { ...meta, id: "10000000-0000-4000-8000-000000000002", extra: 1 },
        "",
      ),
    );
    const data = await snapshot(now);
    expect(data.issues).toHaveLength(3);
    expect(data.issues.some((i) => i.message.includes("重复"))).toBe(true);
    expect(data.entries).toHaveLength(1);
  });
  it("正文不被二次转义", async () => {
    const body =
      "# 标题\n\n```js\nconst x = 1;\n```\n\n![图](../assets/a/b.png)\n";
    const result = await saveEntry(meta, body, null, now);
    const raw = await fs.readFile(
      path.join(root, "entries", id + ".md"),
      "utf8",
    );
    expect(raw.endsWith(body)).toBe(true);
    expect(result.hash).toBe(hash(raw));
  });
});
describe("图片文件边界", () => {
  it("图片实际解码并可读取", async () => {
    const png = await sharp({
      create: { width: 10, height: 10, channels: 3, background: "#3d8060" },
    })
      .png()
      .toBuffer();
    const upload = await uploadAsset(id, png);
    const result = await readAsset(id, upload.path.split("/").at(-1)!);
    expect(result.type).toBe("image/png");
    expect(result.buffer.equals(png)).toBe(true);
  });
  it("拒绝伪造图片、超大图片和路径越界", async () => {
    await expect(
      uploadAsset(id, Buffer.from("not an image")),
    ).rejects.toThrow();
    await expect(
      uploadAsset(id, Buffer.alloc(10 * 1024 * 1024 + 1)),
    ).rejects.toThrow("10 MB");
    await expect(readAsset(id, "../../settings.json")).rejects.toThrow();
  });
  it("符号链接不能读取或写入 assets 之外", async () => {
    const outside = await fs.mkdtemp(
      path.join(os.tmpdir(), "journal-outside-"),
    );
    try {
      await fs.symlink(outside, path.join(root, "assets", id));
      const png = await sharp({
        create: { width: 1, height: 1, channels: 3, background: "#ffffff" },
      })
        .png()
        .toBuffer();
      await fs.writeFile(path.join(outside, "image.png"), png);
      await expect(readAsset(id, "image.png")).rejects.toThrow();
      await expect(uploadAsset(id, png)).rejects.toThrow();
      expect(await fs.readdir(outside)).toEqual(["image.png"]);
    } finally {
      await fs.rm(outside, { recursive: true, force: true });
    }
  });
});

import { isLocalWriteRequest } from "../src/lib/content/request-origin";
it("本机写入来源与 Host 一致，拒绝跨站与伪造域名", () => {
  const req = (origin: string, host: string) =>
    new Request("http://localhost:3101/api/entries", {
      headers: { origin, host },
    });
  expect(
    isLocalWriteRequest(req("http://127.0.0.1:3101", "127.0.0.1:3101")),
  ).toBe(true);
  expect(
    isLocalWriteRequest(req("http://localhost:3000", "localhost:3000")),
  ).toBe(true);
  expect(
    isLocalWriteRequest(req("https://evil.example", "127.0.0.1:3101")),
  ).toBe(false);
  expect(isLocalWriteRequest(req("http://evil.example", "evil.example"))).toBe(
    false,
  );
  expect(
    isLocalWriteRequest(req("http://localhost:3001", "localhost:3000")),
  ).toBe(false);
});
