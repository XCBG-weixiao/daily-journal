import fs from "node:fs/promises";
import path from "node:path";
import { encode } from "../src/lib/content/markdown";
const root = path.resolve(process.env.CONTENT_DIR ?? "./content");
for (const dir of ["entries", "assets", "activities"])
  await fs.mkdir(path.join(root, dir), { recursive: true });
const files: Record<string, string> = {
  "settings.json": JSON.stringify(
    { schema_version: 1, timezone: "Asia/Shanghai", week_starts_on: 1 },
    null,
    2,
  ),
};
for (const [id, name, icon, color, metrics] of [
  ["running", "跑步", "🏃", "#3D8060", ["duration_min", "distance_km"]],
  ["badminton", "羽毛球", "🏸", "#7963B4", ["duration_min"]],
  ["reading", "阅读", "📖", "#B78030", ["duration_min", "pages"]],
] as const) {
  files[`activities/${id}.md`] = encode(
    { schema_version: 1, id, name, icon, color, metrics },
    `记录每一次${name}。\n`,
  );
}
for (const [file, text] of Object.entries(files)) {
  try {
    await fs.writeFile(path.join(root, file), text, { flag: "wx" });
    console.log("已创建", file);
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code !== "EEXIST") throw e;
    console.log("保留现有文件", file);
  }
}
