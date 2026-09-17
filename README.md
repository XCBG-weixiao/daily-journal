# 日常 · Markdown 个人活动日志

以本地 Markdown 为内容源的单用户网页应用。提供月历、七日时间轴、活动年度热力图、历史与统计、图文阅读、编辑和图片上传。

## 本地运行

需要 Node.js 20.19+（当前验证版本 20.20.2）。

```sh
npm ci
npm run content:init
npm run seed:demo # 可选：仅向空目录添加示例
npm run build
npm start
```

访问 http://127.0.0.1:3000 。开发模式使用 `npm run dev`。服务只绑定本机地址，不含账号系统。

演示月份：http://127.0.0.1:3000/calendar?month=2026-09&date=2026-09-14

`content:init` 仅创建缺失的配置和活动定义，不覆盖已有内容。`seed:demo` 在 entries 或 assets 非空时拒绝执行。普通启动不会创建示例。

## 内容目录

默认 `./content`。可使用 `CONTENT_DIR=/absolute/path/to/content npm start` 指向另一目录。Next.js 支持 `.env.local`；独立初始化和示例命令需显式传入同一 `CONTENT_DIR`。

- `settings.json`：schema 版本、Asia/Shanghai 时区、周一开始。
- `activities/*.md`：活动名称、图标、颜色、允许的指标及说明。
- `entries/<UUID>.md`：一条活动或一篇日记。
- `assets/<UUID>/*`：本地 PNG、JPG、WebP 图片。

`content/` 被 Git 忽略。备份整个目录即可迁移；相对图片引用不依赖原机器路径。没有数据库，也没有必须保留的派生索引。

## 记录格式

```markdown
---
schema_version: 1
id: 10000000-0000-4000-8000-000000000001
kind: event
title: 公园晨跑
date: "2026-09-14"
started_at: "2026-09-14T08:30:00+08:00"
activity_id: running
metrics:
  duration_min: 32
  distance_km: 5.2
tags: [户外]
---

今早沿河跑了一圈。

![风景](../assets/10000000-0000-4000-8000-000000000001/morning.png)
```

文件名须与 UUID 一致。日记使用 `kind: journal`，不带 activity_id 或 metrics。时间、指标、标签、cover 可省略。封面和正文图片引用采用同一相对路径规则。完整定义位于 `src/lib/content/schema.ts`。

未知字段、错误 YAML、未知活动、重复 ID、无效或未来日期会显示问题，不自动修复原文件。存在问题时显示“数据不完整”。时间转换为上海自然日后须与 date 一致。

## 统计口径

- 一条 event 计一次；一天两次跑步为两次、一个活跃日。
- 日记提及活动不会重复计数，标签也不生成活动。
- 月统计不含网格中的相邻月份。
- 跨午夜的全部时长归入开始日。
- 缺失指标不补零；平均时长只除以实际填写时长的记录数。
- 年度色阶为未记录、1、2、3、4+ 次，悬浮显示准确数值。
- 没记录不代表没有做，不计算完成率和 streak。

## 编辑与文件一致性

网页保存成功后才提示成功，并刷新页面。外部编辑后通过导航或手动刷新读取新文件，不提供后台实时监听。读取与写入均在服务器所在机器执行。

文件采用临时文件加原子替换；网页编辑携带内容 hash，旧版本保存返回冲突。单进程内串行处理同一文件。第一版遵循单写入者约定：不要同时用外部编辑器与网页修改同一文件，不支持跨机器协作事务。

图片最大 10 MB，上传验证实际内容，仅支持 PNG / JPG / WebP。取消草稿可能留下已上传图片；不会自动回收图片，也不提供网页删除入口。图片不在 public 目录，不允许越界访问其他文件。

## 检查

```sh
npm run typecheck
npm run lint
npm test
npm run build
npm run test:e2e
```

端到端测试需要先运行 `npx playwright install chromium`。测试使用 `work/e2e-content` 的独立示例副本，不修改个人内容。运行结果见 `outputs/implementation-status.md`。
