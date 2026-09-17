import { test, expect } from "@playwright/test";
import fs from "node:fs/promises";
import path from "node:path";
const id = "00000000-0000-4000-8000-000000000002";
const root = path.resolve("work/e2e-content");
test("月历到活动、图文编辑保存、外部修改与窄屏", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("/calendar?month=2026-09&date=2026-09-14");
  await expect(page.getByText("4 次活动 · 1 篇日记")).toBeVisible();
  await expect(page.locator(".agenda img")).toHaveCount(2);
  await expect(page.locator(".agenda img").first()).toHaveJSProperty(
    "naturalWidth",
    960,
  );
  await page.screenshot({ path: "outputs/app-calendar.png", fullPage: true });
  await page
    .locator(".agenda .activity-label")
    .filter({ hasText: "跑步" })
    .first()
    .click();
  await expect(page.locator(".stats-row")).toContainText("15.2");
  await expect(page.locator("#history .entry-card")).toHaveCount(2);
  await page
    .locator("#history .entry-title")
    .filter({ hasText: "公园晨跑" })
    .click();
  await expect(page.locator(".reader-paper img")).toHaveJSProperty(
    "naturalWidth",
    960,
  );
  await page.getByRole("link", { name: "编辑记录" }).click();
  await page.getByLabel("标题", { exact: true }).fill("公园晨跑 · 已编辑");
  await page
    .getByLabel("Markdown 正文")
    .fill("编辑后的正文。\n\n![原图片](../assets/" + id + "/demo.png)");
  await page.getByRole("button", { name: "保存记录" }).click();
  await expect(page.locator("h1")).toHaveText("公园晨跑 · 已编辑");
  const raw = await fs.readFile(path.join(root, "entries", id + ".md"), "utf8");
  expect(raw).toContain("编辑后的正文");
  await fs.writeFile(
    path.join(root, "entries", id + ".md"),
    raw.replace("distance_km: 5.2", "distance_km: 6.2"),
  );
  await page.goto("/activities/running?year=2026&month=2026-09");
  await expect(page.locator(".stats-row")).toContainText("16.2");
  await page.goto("/calendar?month=2026-09&date=2026-09-14");
  await expect(page.locator(".summary-grid")).toContainText("16.2");
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: "outputs/app-mobile.png", fullPage: true });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await page.goto("/activities?year=2026");
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.screenshot({ path: "outputs/app-activities.png", fullPage: true });
  expect(errors).toEqual([]);
});
test("新增与上传真实图片、搜索、旧版本冲突保留草稿", async ({
  page,
  browser,
}) => {
  await page.goto("/entries/new?date=2026-09-14&activity=running");
  await page.getByLabel("标题", { exact: true }).fill("浏览器上传验证");
  await page.getByLabel("Markdown 正文").fill("这是一条独立测试记录。");
  await page
    .locator("input[type=file]")
    .setInputFiles(path.join(root, "assets", id, "demo.png"));
  await expect(page.getByLabel("Markdown 正文")).toHaveValue(
    /!\[demo.png\]\(\.\.\/assets\//,
  );
  await page.getByRole("button", { name: "预览", exact: true }).click();
  await expect(page.locator(".editor-preview img")).toHaveJSProperty(
    "naturalWidth",
    960,
  );
  await page.getByRole("button", { name: "保存记录" }).click();
  await expect(page.locator("h1")).toHaveText("浏览器上传验证");
  const newId = page.url().split("/").at(-1)!;
  const other = await browser.newPage();
  await other.goto(`http://127.0.0.1:3101/entries/${newId}/edit`);
  await page.getByRole("link", { name: "编辑记录" }).click();
  await page.getByLabel("标题", { exact: true }).fill("新版标题");
  await page.getByRole("button", { name: "保存记录" }).click();
  await expect(page.locator("h1")).toHaveText("新版标题");
  await other.getByLabel("标题", { exact: true }).fill("旧稿不覆盖");
  await other.getByRole("button", { name: "保存记录" }).click();
  await expect(other.locator(".form-error[role=alert]")).toContainText(
    "文件已被修改",
  );
  await expect(other.getByLabel("标题", { exact: true })).toHaveValue(
    "旧稿不覆盖",
  );
  await other.close();
  await page.goto("/search?q=新版标题");
  await expect(page.locator(".search-results")).toContainText("新版标题");
});
