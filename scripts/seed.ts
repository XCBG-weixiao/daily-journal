import fs from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";
import { encode } from "../src/lib/content/markdown";
import { settingsSchema } from "../src/lib/content/schema";
const root = path.resolve(process.env.CONTENT_DIR ?? "./content");
settingsSchema.parse(
  JSON.parse(await fs.readFile(path.join(root, "settings.json"), "utf8")),
);
for (const dir of ["entries", "assets"])
  if ((await fs.readdir(path.join(root, dir))).length)
    throw new Error("示例仅能写入空的 entries / assets；现有内容已保留。");
const data = [
  ["13", "running", "周末长跑", 7, 42, undefined, "08:00"],
  ["14", "running", "公园晨跑", 5.2, 32, undefined, "08:30"],
  ["14", "running", "傍晚轻松跑", 3, 20, undefined, "17:00"],
  ["13", "badminton", "周日羽毛球", undefined, 60, undefined, "19:00"],
  ["14", "badminton", "晚间羽毛球", undefined, 90, undefined, "19:00"],
  ["13", "reading", "睡前阅读", undefined, 25, 10, "22:00"],
  ["14", "reading", "继续读一本书", undefined, 40, 18, "22:00"],
  ["14", null, "周一小结", undefined, undefined, undefined, undefined],
] as const;
for (let i = 0; i < data.length; i++) {
  const [day, a, title, distance, duration, pages, time] = data[i],
    id = `00000000-0000-4000-8000-${String(i + 1).padStart(12, "0")}`,
    date = `2026-09-${day}`;
  const metrics = {
    ...(distance !== undefined ? { distance_km: distance } : {}),
    ...(duration !== undefined ? { duration_min: duration } : {}),
    ...(pages !== undefined ? { pages } : {}),
  };
  const meta = {
    schema_version: 1,
    id,
    kind: a ? "event" : "journal",
    title,
    date,
    ...(time ? { started_at: `${date}T${time}:00+08:00` } : {}),
    ...(a ? { activity_id: a, metrics } : {}),
    tags: ["示例", ...(a === "running" ? ["户外", "公园"] : [])],
  };
  let body =
    a === "running"
      ? "今早沿河跑了一圈，后半程状态更轻松。\n\n## 感受\n\n下次试试放慢起步速度。"
      : a === "badminton"
        ? "今天和朋友练习了高远球，也打了几局双打。"
        : a === "reading"
          ? "继续读一本喜欢的书。\n\n> 慢下来，才能看见更多。\n\n- 记住一个想法\n- 把它用在日常里"
          : "早上跑步，晚上打了羽毛球。\n\n今天最喜欢的是出门前那段安静的时间。\n\n## 明天\n\n- [ ] 提前准备运动装备";
  if (i === 1 || i === 6) {
    await fs.mkdir(path.join(root, "assets", id));
    const green = i === 1;
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="960" height="440"><rect width="960" height="440" fill="${green ? "#e3ede5" : "#f1e7d5"}"/><circle cx="720" cy="100" r="58" fill="${green ? "#bbd2a8" : "#dfb86d"}"/><path d="M0 360 Q240 100 480 340 T960 290V440H0Z" fill="${green ? "#9abb9a" : "#d4bd97"}"/><path d="M350 440Q640 230 900 440" fill="${green ? "#638b78" : "#aa8962"}"/><text x="42" y="68" fill="#38443c" font-family="sans-serif" font-size="28">${green ? "MORNING / 05.2 KM" : "SLOW READING / 18 PAGES"}</text><text x="42" y="105" fill="#556458" font-family="sans-serif" font-size="16">DEMO ILLUSTRATION</text></svg>`;
    await sharp(Buffer.from(svg))
      .png()
      .toFile(path.join(root, "assets", id, "demo.png"));
    body += `\n\n![自制示例插图，非个人照片](../assets/${id}/demo.png)\n\n*示例插图 · 用于展示图文混排*`;
  }
  await fs.writeFile(
    path.join(root, "entries", id + ".md"),
    encode(meta, body + "\n"),
    { flag: "wx" },
  );
}
console.log("已创建 8 条示例 Markdown 与 2 张本地图片。");
