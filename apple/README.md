# 日常 · Apple 原生应用

当前交付为**第一阶段的文件夹同步验证工程**，不是完整日记客户端。
先验证免费签名、系统文件夹授权与 iCloud Drive 真机同步；通过后再移植日记数据层和全部界面。
原网页代码、业务数据格式和示例内容没有修改。

## 打开和安装

1. 安装完整 Xcode，首次打开并安装 iOS 平台组件。在 Xcode → Settings → Accounts 登录免费 Apple 账号。
2. 打开 `DailyJournal.xcodeproj`。
3. 在两个 target 的 Signing & Capabilities 中选择自己的 Personal Team。若现有 Bundle Identifier 无法注册，在对应 target 中修改为自己唯一的标识，后续重新安装保持不变。
4. 运行 `DailyJournalProbeMac` scheme，目标选择 My Mac。
5. 连接并解锁 iPhone，完成信任与开发者模式设置。运行 `DailyJournalProbeiPhone` scheme，目标选择自己的 iPhone。

最低系统版本：macOS 15、iOS 18。工程无第三方依赖；iOS target 不启用应用专用 iCloud capability。
Mac target 使用沙盒、用户选择文件夹读写和 app-scope bookmark 权限。
免费签名到期后通过同一工程、账号和 Bundle Identifier 重新安装；不要先删除应用。

## 验证操作

先在 iCloud Drive 创建独立的空文件夹，例如 `DailyJournal-Probe`，不要选真实的 `content` 目录。
两端需登录同一 iCloud 账号、开启 iCloud Drive。

1. Mac 选择文件夹，点击“初始化验证目录”。此操作只创建验证标识和 `probe.md`。
2. 等文件出现在 iPhone 的“文件”应用中，在 iPhone 验证工具选择同一文件夹，确认读到相同文字。
3. Mac 修改文字并保存；iPhone 刷新后检查文字。再反向操作。
4. 完全退出两端应用并重新打开，确认不用重新选择文件夹也能读取。
5. 确认文件已下载到本机后，两端断网，分别验证读取、编辑和保存；恢复网络后核对另一端。
6. 两端断网修改同一文件，在不同时间保存；联网后验证最终正文采用修改时间较晚的版本。修改时间相同时保留系统当前版本。
7. 在“文件”应用中移除测试文件的本地下载，断网打开工具：应明确提示文件不可用。联网后使用“请求下载 iCloud 文件”并刷新。
8. 移动或删除测试文件夹，验证权限/文件错误可见且不会创建替代目录；重新选择后验证恢复。
9. 免费签名更新安装后，确认原 iCloud Drive 文件仍存在，并检查目录授权是否恢复；若系统撤销授权，通过文件选择器重新授权。

“已保存”仅表示本地写入成功；系统报告“已上传”也不表示另一端已下载。
文件刷新不会覆盖编辑区，需点击“将磁盘内容载入编辑区”载入另一端的新文字。
冲突采用最后修改版本，因此较早版本的改动会被舍弃；本工具不自动合并。

## 代码与检查

- `Sources/ProbeCore`：协调读写、测试目录校验、下载请求、按修改时间解决文件版本冲突。
- `Sources/ProbeApp`：双端 SwiftUI 界面、目录授权 bookmark、文件变化通知、前台刷新。
- `Tests/ProbeCoreTests`：真实临时文件读写、拒绝覆盖非空目录、拒绝符号链接、冲突时间策略。

安装完整 Xcode 后，可在该目录运行：

```sh
swift test
xcodebuild -project DailyJournal.xcodeproj -scheme DailyJournalProbeMac -configuration Debug -derivedDataPath build/mac CODE_SIGNING_ALLOWED=NO build
xcodebuild -project DailyJournal.xcodeproj -scheme DailyJournalProbeiPhone -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/ios CODE_SIGNING_ALLOWED=NO build
```

模拟器和未签名构建不能代替 Personal Team 真机验证。Swift Package 可用于本地编译检查，但目录沙盒授权必须以 Xcode 的 app target 实测。

## 当前验证状态

2026-09-23：仓库已拉取；Xcode 工程与 entitlement 的 plist 语法检查通过。
使用系统 Swift 编译器运行临时文件检查，以下五项通过：协调读写与重新打开、拒绝重复初始化、拒绝非空个人目录、拒绝符号链接越界写入、最后修改时间选择及同时间保留当前版本。

本机只有 Command Line Tools，未安装完整 Xcode。`swift test` 因缺少 XCTest 无法执行；默认 SDK 的 SwiftUI 构建还缺少 SwiftUIMacros 插件。
改用本机已安装的 macOS 26.5 SDK 后，Mac Swift Package 程序编译通过：

```sh
swift build --product DailyJournalProbe --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
```

尚未验证 iPhone 编译与安装、沙盒书签恢复、iCloud 冲突版本 API 的实际行为、双端离线同步及签名更新。
**在真机验证通过前，不将同步路线视为已验证，不开始完整日记功能迁移。**

后续工作仍为：兼容原 Markdown/YAML 数据层与统计口径；月历、时间轴、热力图、历史统计、搜索、图文阅读和编辑；图片添加和相对引用；两端完整回归。
