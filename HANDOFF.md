# Tos'n DOs — 交接文档

> 换 session 先读第 1 节（30 秒）。第 2 节是构建命令，第 3 节是改代码前必须知道的约定，
> 第 4 节是踩过的坑。其余按需查。

---

## 1. 当前位置

| 项 | 状态 |
|---|---|
| 仓库 | <https://github.com/LycoRiko/tosn-dos>（public，`main`） |
| 平台 | iOS 18+ / iPadOS 18+ / macOS 15+ / watchOS 10+，Xcode 26.1.1 |
| 构建 | 四端全部 `BUILD SUCCEEDED`（iOS / iPad / macOS / watchOS） |
| 真机 | iPhone 16 Pro Max（iOS 27.0.1）已装 `Tos'n DOs 1.0 (1)`，免费账号 7 天有效期 |
| 签名 | Team `S465RV3CLC`（REGer Bili / Personal Team，免费） |
| 版本 | Bundle `com.rikomiyazaki.TosnDOs`（`.widget` / `.watchkitapp`） |

**下一个该做的**：分享码（见 5.1）。之后依次是 URL scheme、iPad 横屏适配、两条编译器告警。

**开工前必看**：
- 构建**必须**带 `-disable-sandbox`，否则宏插件必挂（第 2、4 节）
- `devbuild.sh`、`project.pbxproj.1`、`build/` 是本机专有文件，已 git 忽略，**别提交、别删**

**需要用户拍板的两件事**：
1. README 的 Credits 写着「running DeepSeek-V4.1-Flash」，但 10-19 凌晨换过其他模型，改不改由他定
2. 免费账号导致真机上 Widget 读不到数据；要不要上付费账号

---

## 2. 构建 / 运行

```bash
cd "/Users/reg/WorkBuddy/Tos'n DOs"

# 公共参数：少了这个宏插件起不来
FLAGS="SWIFT_ENABLE_EXPLICIT_MODULES=NO OTHER_SWIFT_FLAGS=\$(inherited)\ -disable-sandbox"
# 每个平台用独立 -derivedDataPath，别共用（平台切换会打架）

# iOS（会连带编 watch 并嵌进 .app/Watch）
xcodebuild -project TosnDOs.xcodeproj -scheme TosnDOs \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  -derivedDataPath /tmp/dd-ios $FLAGS build

# iPad（同一个 binary）
xcodebuild -project TosnDOs.xcodeproj -scheme TosnDOs \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' -configuration Debug \
  -derivedDataPath /tmp/dd-ios $FLAGS build

# macOS（产物里不该有 Contents/Watch）
xcodebuild -project TosnDOs.xcodeproj -scheme TosnDOs \
  -destination 'platform=macOS' -configuration Debug \
  -derivedDataPath /tmp/dd-mac $FLAGS build

# watchOS 单独编
xcodebuild -project TosnDOs.xcodeproj -scheme TosnDOsWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' -configuration Debug \
  -derivedDataPath /tmp/dd-watch $FLAGS build
```

**跑模拟器**：`xcrun simctl boot "iPhone 17 Pro"` → `install booted <app>` → `launch booted com.rikomiyazaki.TosnDOs`

**真机测试包**：`./devbuild.sh` → `build/ipa/TosnDOs.ipa`。
脚本会临时把 `project.pbxproj.1`（裁剪版）换进去，archive 完用 `trap` 无条件还原。装配：
`xcrun devicectl device install app --device 00008140-000C64CE2E00401C build/ipa/TosnDOs.ipa`

---

## 3. 改代码前必须知道

1. **工程文件是手写 pbxproj**，用 `PBXFileSystemSynchronizedRootGroup` 按文件夹同步。
   新增 `.swift` 一般不用改 pbxproj；`Info.plist` / `.entitlements` 已在 exception set 里排除。
2. **`#if` 不能写进 `App.body: some Scene`**，会报 unexpected tokens。已拆成按平台的 `mainScene`。
3. **macOS 免签**：`CODE_SIGN_ENTITLEMENTS[sdk=macosx*] = ""`，且 macOS 用本地存储（无 iCloud）。
4. **跨平台 API**（`insetGrouped`、`.topBarTrailing`、`presentationDetents`、`TabView(.page)`）
   只走 `Compat.swift` 的 shim 或 `#if os(iOS)`。
5. **Liquid Glass** 收敛在 `Glass.swift`：26+ 用 `.glassEffect`，旧系统 `.ultraThinMaterial`。
   业务视图里不要直接写 material。
6. **本地化**：所有文案进 `Shared/Localizable.xcstrings`（205 条 × 简中/繁中/日/英）,
   用 `String(localized:)` 或 SwiftUI 字面量。中文/英文日期解析在 `NaturalDateParser`。
7. **新增模型字段必须带默认值**（SwiftData 轻量迁移 + CloudKit 前提），否则老库打开会退到内存库,
   表现是「App 空了但数据还在」。
8. **`Shared/` 是 App / Widget / Watch 的唯一公共区**。`TaskQuery` 依赖 App 独有类型，Widget 拿不到。
9. **「今天」只有一处定义**：`Shared/TodayScope.swift`。App、Widget、Watch 都读它，不许各写一套。
10. **真机裁剪分流**：`project.pbxproj.1` 里给三个 target 各加了
    `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*] = build/TosnDOsDevice.entitlements`（空文件）。
    仓库版 `project.pbxproj` **没有**这 6 行——免费账号拿不到 App Group / iCloud，只能这样兜底。
11. **watch 的 embedding 依赖加了 `platformFilter = ios`**。否则 macOS 构建会去编 watch，报
    「requires a development team」。别删这两处 platformFilter。

---

## 4. 踩过的坑（现象 → 解法）

| 现象 | 原因 / 解法 |
|---|---|
| `swift-plugin-server … malformed response`，满屏 | 宏插件在嵌套沙箱里跑不了。构建加 `-disable-sandbox`（编译器自带开关），一次解决 |
| `No Accounts: Add an account` + `No profiles` | CLI 读不到 Xcode 的账号令牌。让用户在 Xcode 里连真机 ⌘R 一次，生成描述文件后 CLI 就能签 |
| `Signing for "TosnDOsWatch" requires a development team`（macOS 构建） | watch 依赖在 macOS 也触发。给 BuildFile + TargetDependency 加 `platformFilter = ios` |
| `Multiple commands produce '.app'` | watch target 缺 `PRODUCT_NAME = $(TARGET_NAME)` |
| watch destination 列不出来 | 项目级 `SUPPORTED_PLATFORMS` 不含 watchos；watch target 显式设 `watchos watchsimulator` |
| `-exportArchive` 报 `expected one {} but found …` | Xcode 26 不接受任何 `method` 值。改为手动打包：`Payload/` + `zip`（archive 里的 .app 已签好） |
| 设备 `connected (no DDI)`、手机无弹窗 | 设备上「开发者模式」没开：设置 → 隐私与安全性 → 开发者模式 → 重启确认 |
| 真机装完 Widget 没数据 | 免费账号没有 App Group，属预期。要完整功能得上付费账号 |
| `Localizable.xcstrings` 突然几千行 diff | Xcode GUI 重排格式（`xcodebuild` 不会）。提交一次即可，别反复还原 |
| 例行清单不弹窗 / 只算 1 期 | 模板缺 `repeatStart`，锚点退回 `createdAt`。真实路径由设置重复规则时写入 |

---

## 5. 待办

### 5.1 分享码（建议下一个做）

把清单导出成码/串，别人导入即得同一张清单。**本地 Deflate + Base64URL，不上云**。
与「分享为文本」共用序列化格式（`TosnDOs/Support/ListShareText.swift`），别写成纯展示文本。
参考过 WakeUp 课程表的做法；服务端短口令方案已否决。

### 5.2 其余

1. **URL scheme**：`CFBundleURLTypes` 缺失，所以 `onOpenURL` 和 Widget 的 `widgetURL` 是死代码。
   要新建 `TosnDOs/Info.plist` 并关掉 `GENERATE_INFOPLIST_FILE`。
2. **iPad 横屏**：`NavigationSplitView` 需要 `.balanced` + 侧栏默认收起。
3. **两条告警**：`TemplateDetailView.swift:33`、`TemplateLibraryView.swift:84`。
4. **手表真机安装**：Xcode 里设备切到 `REG's Apple Watch` 按 ⌘R。

---

## 6. 已完成（别再重做）

| 模块 | 要点 |
|---|---|
| OOBE | 4 页，最后一页申请通知权限 |
| Today | 一屏看完，进度环；口径全在 `TodayScope` |
| 输入 | 自然语言日期（中/英）：`明天 3pm`、`tomorrow 3pm` |
| 模板 | 可反复拉取；`ListTemplate → TodoList` 一对一复制 |
| 例行清单 | 每天/周/月；错过会弹窗问「补最新一期 / 全补 / 不补」，最多 30 期；31 号遇短月落月末，不漂移 |
| 清单耗时 | Browse 的 Previous ToDos 显示「创建 → 最后勾完」，取消再勾会变长 |
| 分享为文本 | 任何清单都能导，`[x] / [ ]` 标注，行首不带时间戳 |
| 等待中 | 独立分组，**不计入任何数字**（progress / isFinished / doneTaskCount / openTaskCount / Today 快照 / Today 智能列表 六处都要排除） |
| watchOS | 手机推「今天剩余」快照（`updateApplicationContext`），手表镜像到本地库，勾选回传；口径同样走 `TodayScope` |
| 本地化 | 四语言 205 条，占位符已校验一致 |
| 无障碍 | Dynamic Type（`ScaledFont.swift`）、VoiceOver 标签、深色模式 |

**已知取舍**（都经用户追认，改动前先问）：
- 等待中的任务不进 Today，即使到期日是今天
- 结束等待 = 勾选即完成，或编辑页 `Stop waiting`
- 手表只在启动和回传后拉快照；手机侧除勾选外的写操作不主动推

---

## 7. 协作偏好

- **业务逻辑先问**，不要自己拍板；纯实现细节自己定。
- **改完必须四端编译**再汇报，不要只说"应该能跑"。
- **界面文案**：不要 SRE/运维黑话，不要罗嗦，别解释用户看得见的东西。
- **不加没要求的开关/页面/预设内容**。
- **残留物零容忍**：临时钩子、调试参数、死代码，交付前删干净并 grep 确认。
- 用户会亲自 inspect 代码；注释写"为什么"，不写"做了什么"。
- 每轮改动都要回写本文档。
