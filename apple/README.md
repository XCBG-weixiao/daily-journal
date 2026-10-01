# 日常 · Mac 原生应用

Mac 客户端已实现原网页的日记功能，最低 macOS 15。使用 SwiftUI / AppKit 原生界面，内容保存在你选择的 Markdown 文件夹中，不需要启动 Node.js 服务。

## 直接使用

本机构建结果为 `apple/build/日常.app`，双击打开即可，也可复制到“应用程序”文件夹。

- **打开已有日记库**：选择包含 `settings.json`、`activities`、`entries` 和 `assets` 的原内容目录。首次连接真实目录前，请先备份整个目录。
- **新建日记库**：选择空文件夹，创建配置及跑步、羽毛球、阅读三个默认活动。不会自动添加示例日记。
- **写一条记录**：点击右上角新建，或按 `⌘N`；支持日记、活动、可选时间、指标、标签、封面和 Markdown 正文。`⌘S` 保存。
- **添加图片**：点击“添加图片”或拖入正文编辑区。支持 PNG / JPG / WebP，最多 10 MB、4000 万像素，保留原图。取消草稿后已导入的图片不自动清理。
- **外部编辑**：可以使用其他编辑器修改 Markdown；返回应用或 `⌘R` 刷新。如果正在编辑的文件已被修改，保存会报冲突并保留草稿，请重新打开记录后合并。
- **管理活动**：沿用原项目的 `activities/*.md` 定义方式，编辑活动文件后刷新。

## 已实现

| 功能 | Mac 操作 |
| --- | --- |
| 月历 | 周一开始的 42 格月历、每日记录、当月统计、今天与月份切换 |
| 七日时间轴 | 按天分组，前后七天切换，指定日期新增 |
| 活动 | 年度热力图，悬浮显示次数，活动详情中点击日期查看历史 |
| 历史与统计 | 活动月历、月份/日期筛选、年度指标、每月次数、星期分布、平均时长 |
| 搜索 | 搜索标题、正文、标签；全部记录支持日记/活动筛选 |
| 图文阅读 | 原生多栏阅读，Markdown 标题、列表、任务列表、代码、表格及本地图片 |
| 编辑 | Markdown / 分栏 / 预览，原生文本编辑、光标位置插图、取消未保存修改确认 |
| 文件访问 | 沙盒文件选择器、持久目录授权、协调读写、原子保存、内容 hash 校验、文件问题列表 |

保持 schema_version=1、UUID 文件名、上海时区、相对图片引用和原统计口径。未知字段、重复 YAML 字段、无效日期、未来记录和未知活动会明确报错，不修复原文件。无效文件不计入统计，并显示“数据不完整”。

## 构建

构建脚本使用当前 `xcrun` 指向的 macOS SDK。本机已验证的命令：

```sh
MACOS_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk apple/scripts/build-mac.sh
open apple/build/日常.app
```

安装完整 Xcode 后通常直接执行 `apple/scripts/build-mac.sh`。当前这台机器的默认 27.0 SDK 缺少 SwiftUI 宏插件，因此明确选择已安装的 26.5 SDK；脚本不会自动切换 SDK。默认构建 Release，可用 `BUILD_CONFIGURATION=debug` 调试。

也可用 Xcode 打开 `DailyJournal.xcodeproj`，选择 **DailyJournalMac** scheme。旧的 `DailyJournalProbeMac` / `DailyJournalProbeiPhone` 仍为独立同步验证工具。Xcode target 尚未在完整 Xcode 中执行构建；本次应用由 Swift Package 构建并打包。

产物为本机 ad-hoc 签名、开启文件沙盒的 `.app`，已通过 `codesign --verify --strict`。本地构建使用不需要付费会员；这不是 App Store 或 Developer ID 公证分发包。构建默认针对当前 Mac 架构，当前产物为 Apple Silicon。

依赖锁定在 `Package.resolved`：Yams 6.2.2、MarkdownUI 2.4.1，以及其底层依赖。YAML 解析显式使用与网页一致的 YAML 1.2 标量规则；Markdown 图片只允许读取所选日记库的 `assets`，不加载外部图片。

## 验证

安装网页依赖后，在仓库根目录运行：

```sh
npm ci
MACOS_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk apple/scripts/check-mac.sh
npm test
```

检查使用临时目录与仓库示例；`work/native-compat` 是生成的互操作测试数据，不修改个人日记。`JournalChecks` 是可直接执行的检查程序，不依赖当前 Command Line Tools 缺少的 XCTest。

2026-09-30 验证结果：

- 44 项原生与双向格式检查通过：全部 8 条原示例、真实保存/重读、旧版本冲突、外部删除、日期/统计、YAML 1.2、图片解码/限制、符号链接边界、网页写回后原生读取。
- 原网页 13 项测试通过；网页原有解析器与 schema 能读取 Mac UI 实际保存的日记、图片路径和全部示例。
- 本机已实际打开沙盒 `.app`，通过文件选择器打开示例副本，检查月历、历史、多栏图文阅读、表格/任务列表预览、新增保存、已有记录编辑、图片选择与导入保存。
- 重启授权恢复的进一步 UI 检查遇到 macOS ScreenCaptureKit 采集失败，未将此项标为通过；未验证 macOS 15 真机、Intel 架构、iCloud 跨设备同步及离线文件驱逐。

## iCloud 与 iPhone 状态

iPhone 暂缓。Mac 本地日记库可以独立使用。

选择 iCloud Drive 内的日记文件夹后，由系统负责同步；应用不创建专用 iCloud 容器。已下载文件可离线使用，未下载文件显示不可用或数据不完整。工具栏菜单提供“下载 iCloud 文件”，也可在 Finder 下载并保留本地副本。保存成功只代表本机落盘，不代表另一台设备已收到。

系统暴露文件冲突版本时，采用最后修改版本，时间相同保留系统当前版本；不会自动合并正文。该跨设备分支仍待真机验证。同步验证工程的操作步骤见 [SYNC-PROBE.md](SYNC-PROBE.md)。
