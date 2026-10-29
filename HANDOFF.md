# Tos'n DOs — 交接文档

> 换 session 先读第 1 节（30 秒）。第 2 节是构建命令，第 3 节是改代码前必须知道的约定，  
> 第 4 节是踩过的坑。其余按需查。

---

## 1. 当前位置

| 项  | 状态                                                            |
| -- | ------------------------------------------------------------- |
| 仓库 | <https://github.com/LycoRiko/tosn-dos>（public，`main`）         |
| 平台 | iOS 18+ / iPadOS 18+ / macOS 15+ / watchOS 10+，Xcode 26.1.1   |
| 构建 | 四端全部 `BUILD SUCCEEDED`（iOS / iPad / macOS / watchOS）          |
| 真机 | iPhone 16 Pro Max（iOS 27.0.1）已装本轮构建（930K，含全部改动），免费账号 7 天有效期   |
| 签名 | Team `S465RV3CLC`（REGer Bili / Personal Team，免费）              |
| 版本 | Bundle `com.rikomiyazaki.TosnDOs`（`.widget` / `.watchkitapp`） |

**下次开工看第 11 节**。第 10 节是 2026-10-22 这一天做了什么（给新读者看的话读那节就够）。

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

| 现象                                                                 | 原因 / 解法                                                                        |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| `swift-plugin-server … malformed response`，满屏                      | 宏插件在嵌套沙箱里跑不了。构建加 `-disable-sandbox`（编译器自带开关），一次解决                              |
| `No Accounts: Add an account` + `No profiles`                      | CLI 读不到 Xcode 的账号令牌。让用户在 Xcode 里连真机 ⌘R 一次，生成描述文件后 CLI 就能签                      |
| `Signing for "TosnDOsWatch" requires a development team`（macOS 构建） | watch 依赖在 macOS 也触发。给 BuildFile + TargetDependency 加 `platformFilter = ios`    |
| `Multiple commands produce '.app'`                                 | watch target 缺 `PRODUCT_NAME = $(TARGET_NAME)`                                 |
| watch destination 列不出来                                             | 项目级 `SUPPORTED_PLATFORMS` 不含 watchos；watch target 显式设 `watchos watchsimulator` |
| `-exportArchive` 报 `expected one {} but found …`                   | Xcode 26 不接受任何 `method` 值。改为手动打包：`Payload/` + `zip`（archive 里的 .app 已签好）       |
| 设备 `connected (no DDI)`、手机无弹窗                                      | 设备上「开发者模式」没开：设置 → 隐私与安全性 → 开发者模式 → 重启确认                                        |
| 真机装完 Widget 没数据                                                    | 免费账号没有 App Group，属预期。要完整功能得上付费账号                                               |
| `Localizable.xcstrings` 突然几千行 diff                                 | Xcode GUI 重排格式（`xcodebuild` 不会）。提交一次即可，别反复还原                                   |
| 例行清单不弹窗 / 只算 1 期                                                   | 模板缺 `repeatStart`，锚点退回 `createdAt`。真实路径由设置重复规则时写入                              |
| 模拟器里查不到键盘相关状态                                                      | 模拟器默认接了硬件键盘，软键盘不弹出。改成强制分支或用 `-forceBounce` 这类临时开关验证                            |

---

## 5. 待办

### 5.1 分享码（已完成，2026-10-22）

清单 → 紧凑 JSON → deflate → Base64URL，前缀 `TOSN1:`；二维码内容包成 `tosndos://import?c=`。  
文本码因为太长已撤掉，只保留二维码。实现见 `Shared/Transfer/ListCodec.swift`、`TosnDOs/Support/QRCode.swift`。

### 5.3 新功能：截屏 → 确认 → 入库（2026-10-29 提出，未开工）

**用户原话**：允许用户用快捷指令调取「阅读屏幕」（截屏这一步交给快捷指令），摘出图中的待办事项，
要求提取**时间**和**地点**，然后弹出**可编辑**的弹窗让用户确认是否加入清单。

#### 设计约束（用户 2026-10-29 明确）
- **不许交给第三方处理**：OCR、条目抽取、时间地点识别全部在设备上完成。
  不调用任何云端模型/API，不上传截图，不写日志（截图只在内存里存在到面板弹完）。
  `VNRecognizeTextRequest` 是系统框架、默认离线；这一点要在实现时显式设置
  `usesLanguageCorrection = true` 但**不要**开任何网络相关选项。
- **先只支持简体中文**：识别语言先设 `zh-Hans`（可加 `en` 作为混排兜底，但不做日文/繁中）；
  解析规则先按中文习惯写（今天/明天/周三/下午3点/点/分/号），英式表达先不管。
  UI 文案先只给中文，其他语言等稳定后再补。

#### 流程拆解
```
快捷指令：截屏  →  「从截屏添加待办」动作（我们的 App Intent）
                      ↓ 图片/文本
               OCR + 条目抽取（本机）
                      ↓ 候选：[{标题, 时间, 地点}]
               确认面板（可改、可勾选、可选清单）
                      ↓
               写入清单 → 回一条「已添加 N 条」
```

#### 两条实现路线（要选）

**A. 只收文本（省事、包小）**
快捷指令里用系统自带的「从图像中提取文本」动作，把纯文本传给我们。
- 我们的 Intent：`@Parameter var text: String`
- 优点：零新增代码依赖，几十行解析，包几乎不变
- 缺点：**丢失布局**。截图里「明天 15:00」和「地点：星巴克」分处不同行/列时，
  纯文本无法判断它们属于同一条待办，容易张冠李戴

**B. 收图片，自己 OCR（质量最好，代码多一点）**
`@Parameter var image: IntentFile` → Vision `VNRecognizeTextRequest`。
- Vision 返回每行的**归一化坐标**，可以按 y 聚类成"行块"，再按 x 判断左右栏
- 优点：能判断"时间/地点紧挨着哪条标题"，多列列表、微信聊天、网页都能处理
- 缺点：约 150–200 行；Vision 是系统框架，不增加包体积、不需要权限
- 备注：App Intents 在主 App 进程内执行，不需要 App Group 也能把结果交给 UI

**建议 B**。这个功能的价值全在"摘得准"，A 的丢失布局会让确认面板变成人工重排，等于没帮上忙。

#### 关键实现点
1. **Intent 参数与前台**：`openAppWhenRun = true`；perform 里解码 + OCR，把结果放进内存单例，
   返回后 App 前台读它并弹面板。不能直接弹自定义 UI（系统确认框不可编辑）。
2. **条目切分**：Vision 行 → 按 y 分组 → 组内按 x 排序 → 合并成"逻辑行"；
   有 checkbox 圈/方框、项目符号、编号的行优先作为候选起点。
3. **时间抽取**：直接复用 `NaturalDateParser`（已支持 今天/明天/后天/周三/下周一/10月20日/下午3点/15:30）。
   要补：时间区间（15:00–16:00）、"晚 7 点"、"下周三前"。
4. **地点抽取**：先用 `NSDataDetector` 找地址；再匹配「地点/地址/在 XX/@ XX/📍」等模式；
   识别不到就留空——**不猜**。这可能要给 `TodoItem` 加一个 `place: String?` 字段
   （带默认值，轻量迁移），而不是硬塞进 notes。
5. **确认面板**：sheet 里一列候选，每条可编辑标题、时间（日期选择器）、地点，
   左侧勾选是否导入；底部选目标清单 + 「添加」。默认全选，识别不出的字段留空。
6. **隐私**：OCR 全部本机，截图不落盘（内存处理完即释放），不写日志。

#### 分期
- **M1**：Intent 收图 + Vision OCR + 把识别到的文本行打印出来（先确认取词质量）
- **M2**：条目切分 + 时间/地点抽取 + 确认面板 + 写入
- **M3**：补时间区间的解析、加 `place` 字段、按清单默认选上次用过的
- **M4（可选）**：iOS 26 的 FoundationModels 做一次"这行是不是待办"的判断（会引入机型限制，先不做）

#### 需要用户拍板
1. 走 A 还是 B（建议 B）
2. 地点要**新加字段**还是先写进备注（建议加 `place`，否则"地点"只是备注里的一行字）
3. 一次导入**多条**还是只认一条（建议多条 + 勾选，截图里常常不止一条）
4. 是否允许它**自动记住上次用的清单**
5. 识别不出时间/地点时，是留空，还是让面板高亮提示"这条没识别到地点"

#### 5.10 崩溃修复 + 展示截图（2026-10-29 21:30）

**闪退根因（真 bug，非脚手架）**
`SharedStore.boot()` 在磁盘库打不开、退回内存库之前调了 `assertionFailure(message)`——
Debug 构建里 `assertionFailure` 会**直接 trap**。于是"库读不出来"直接变成"点开就闪退"。
- 已删掉该断言，只打印日志；`StoreBoot` 新增 `didFallbackToMemory` 供界面提示。
- 触发条件：库文件被异常删除/写坏（这次是我 `rm -rf` 目录时进程还开着）。
- 教训：**兜底路径里不许留 `assertionFailure` / `fatalError`**，那等于让兜底变成崩溃。
- 另外崩因之一在 `ShowcaseHarness`：`RootView` 的默认分支返回 `RootView()` 自己，无限递归。
  这个只影响临时脚手架，但同样值得记：路由的 default 分支**绝不能指回入口**。

**展示截图**
- `docs/showcase/`：iOS 七张（Today / Browse / Previous / Editor / Review / Templates / Settings）
  + macOS 四张（today / previous / editor / settings），全部由 `-seedShowcase` 假数据生成。
- 生成脚本用的临时脚手架已删除，`grep ShowcaseHarness` = 0。

#### 5.9 T2 / T4 / T6 已完成（2026-10-29 18:15）

**T2 设置**
- `pref.saveShotToEvidence`（默认开）：把截图存进材料。
- `pref.backupEvidenceScope` 三选一（不含 / 仅文字 / 全部），选「全部」时下方展开 `pref.optimizeImages`（默认勾选）。
- 备份导出按选择收集证据；图片经 `ImageShrink.jpeg`（长边 1600 / JPEG 0.8）压缩。schema 升到 2，旧文件照吃。

**T4 OCR + 意图**
- `TextRecognizer`：Vision `VNRecognizeTextRequest`，`zh-Hans` 主 + `en-US` 兜底，`.accurate`，全本机。
- `AddTasksFromScreenshotIntent`（`openAppWhenRun = true`）：收 `IntentFile` → OCR → 解析 → 写入 `CaptureSession`，
  由根视图弹出确认面板。已加进 `TosnShortcuts`（"From screenshot"）。
- 元数据已验证：`extract.actionsdata` 里有 `AddTasksFromScreenshotIntent`，快捷指令里能搜到。

**T6 确认面板**
- 顶部「全部 / 只要一条」二选一；每行可勾选、改标题、改日期（**只有识别到时间才给时间选择器**）、改地点。
- 空字段显示半透明 `Optional` 占位。
- 底部选目标清单，点「添加 N」才落库：没时间 → 今天；有时间 → 那天并带时间；地点写成 place 证据；
  截图按设置压到长边 1600 后存成图片证据。

**另外两处**
- 分享面板加一句「分享只发送清单结构，材料留在本机」。
- 带材料的任务被滑动删除时弹二次确认（「N 条材料会一起删除」）；没有材料仍是一步删除。

**回归**：三端编译通过；测试 **15 项**全过（新增 OCR 用例：渲染中文 → Vision 读回 → 断言取到「开会」与时间）。

#### 5.7 T3 已完成（2026-10-29 17:35，材料区块）

- `TaskEditorView` 新增 **Materials** 区块（放在 Checklist 之前）：
  已有材料逐行显示（文本可原地改；图片显示 40×40 缩略图），底部「Add a note or a link」回车即加，
  左滑删除，标题右侧显示条数。
- `TodoItem` 加 `orderedEvidences` / `evidenceCount` 两个便捷访问。
- `Compat.swift` 加 `PlatformImage` 垫片（UIImage / NSImage）与 `Image(platformImage:)`，
  图片行两端通用。
- 本地化 +7 条：Materials / Add a note or a link / Screenshots, addresses and notes… / Text / Screenshot / Place / Time。

**验证**：iOS 模拟器里用假数据（1 条文本 + 1 条地点 + 1 条时间）打开编辑页截图，
三行图标、计数、占位输入都正常。截图为看清位置临时复制了一份区块，**截完已还原**，`materialsRows` 只剩 1 处引用。

#### 5.8 2026-10-29 17:40 全量回归

- 三端编译：iOS / macOS / watchOS 全过。
- 单元测试：**14 项全过**（8 项旧 + 2 项 Evidence + 4 项解析器）。
- 模拟器冒烟：全新安装 → 启动 → 引导页正常渲染，日志无 crash / fatal。
- 脚手架（ShotHarness / -shot / -seedDemo）已删，`grep ShotHarness` = 0。

#### 5.6 T5 已完成（2026-10-29 17:05，解析器）

`TosnDOs/Support/CaptureParser.swift`（纯 Foundation，无 UI、不联网）：
- 输入 `[RecognizedLine]`（text + 归一化坐标），输出 `[CapturedTask]`（title / dueDate / hasTime / place）。
- **行还原**：按 `midY` 聚类成行（容差 = 行高 × 0.6），行内按 `minX` 排序拼接。
- **修饰行合并**：「地点：…」/ 纯时间行先并回上一条，否则它既不是候选、也找不到归属。
- **候选判定**：有项目符号（☐ □ ○ • - · ✓ 1. 1、）→ 收；含「待办/todo」→ 收；
  仅含日期 → 还要**短（≤40 字）且不含逗号**才算，避免把聊天正文当任务。
- **时间**：交给已有的 `NaturalDateParser`，它同时把时间词从句子里摘掉，剩下的正好当标题。
- **地点**：`地点/地址/位置` 前缀 → `@xx` → `NSDataDetector(.address)` → 「在/于 …（店/楼/室/号/路/街/中心/广场/大厦）」。
  返回的是值 + 文本范围，整段从标题里摘掉，不会留下「地点：」这种残留。

**测试 14 项全过**（新增 4 项）：
`gluesFragmentsOnTheSameRow`（同行碎片拼接）、`parsesChatStyleMessage`（明天下午3点 开会 + 地点行）、
`parsesBulletList`（项目符号列表 + 排除无标记长句）、`dropsProseWithoutMarkerOrDate`（带逗号的闲聊不误收）。

**这两个失败是测试先抓出来的**，不是我想象的边界：地点行原本会被整行丢弃、带「今天」的聊天正文会变任务。

#### 5.5 T1 已完成（2026-10-29 16:45）

- 新增 `Shared/Models/Evidence.swift`：`uid / kindRaw / text / imageData(.externalStorage) / createdAt / task`，
  枚举 `EvidenceKind`（文本 / 截图 / 地点 / 时间）。
- `TodoItem.evidences` 关系，`deleteRule: .cascade`，inverse `\Evidence.task`。
- `SharedStore.schema` 与测试的 `memoryContainer` 都已加 `Evidence.self`（漏一处就运行时崩）。
- 测试 +2：`deletingTaskCascadesToEvidence`（删任务连带删材料）、`evidenceKeepsKindAndSummary`。
  **共 10 个测试全过。**
- 迁移验证：旧库 5 个清单 / 14 条任务原样保留，`ZEVIDENCE` 表自动建出、0 行。
- 坑：测试包是显式文件列表，新增源文件必须同时加 PBXFileReference + PBXBuildFile + **Sources 阶段**三处；
  只加前两处会报 `cannot find 'Evidence' in scope`。

#### 5.4 证据相关的补充决策（2026-10-29 16:36）

- **分享码不带证据，但必须声明**：生成/展示分享码的面板要写一句「分享内容只含清单结构，
  不含材料（截图/文本）」，别让用户以为证据跟着走了。
- **备份证据三选一**（设置里，单选）：
  ① 不备份证据 ② 仅文字证据 ③ 所有证据（含图片）。
  选③时下方展开子选项 **Optimize images**（默认勾选，用户可取消）；
  勾选=导出前压到长边 1600px / JPEG 0.8，取消=原图。
- **删除带证据的任务要二次确认**：右滑出现「删除」后，再点一次确认，
  提示「任务与 N 条材料会一并删除」（参照 iOS 通知的清理逻辑）。无证据时保持一步删除。

#### 5.3 修订（2026-10-29 16:30，用户补充决策）

**已定**
- 走 B 路线；识别语言 `zh-Hans` 为主，`en` 兜底（"一定要有兜底"）。
- 面板顶部给一次**单条 / 多条**选择，用户选完再解析，避免全量失败。
- **新增 `Evidence` 实体**（不是给 TodoItem 加 place 字符串）：挂在任务下的材料条目，
  用来放截图、时间、地点、相关文本，便于回溯关联信息。
- 截图**不立即释放**，默认一起存进 evidences；设置里加开关可关。
- 识别不到的字段：面板显示**空条目**，占位文字 (Optional) 用半透明字体。
- 时间归属：**没时间 → 今天**；**有时间 → 带时间标签落在那一天**（dueDate + hasDueTime）。
- 截屏后**直接弹面板**，不多一次确认。

**数据模型（待实现）**
```swift
@Model final class Evidence {
    var uid: UUID = UUID()
    var kindRaw: Int = 0          // 0 文本 / 1 图片 / 2 位置 / 3 时间
    var text: String = ""         // 文本、地址、时间的人读形式
    var imageData: Data?          // @Attribute(.externalStorage)，截图
    var createdAt: Date = .now
    var task: TodoItem?
}

// TodoItem 增加
@Relationship(deleteRule: .cascade, inverse: \Evidence.task)
var evidences: [Evidence]? = []
```

**审计：会被牵动的地方**
1. `Shared/SharedStore.swift` 的 `schema` + `TosnDOsTests` 的 `memoryContainer` —— **漏加就是运行时崩**。
2. 备份 `BackupFile`：现在不含图片。若证据带截图一起导，JSON+base64 会让备份从 4KB 涨到几十 MB。**要不要导图，需拍板**。
3. `ListCodec`（分享码）：不包含 evidences —— 图片塞不进几百字符，保持只分享结构。
4. `TaskEditorView` 新增「材料」区块；`TaskRow` 或需一个回形针标记；`SettingsView` 加开关；
   新增确认面板（全新页面）。
5. iCloud：`externalStorage` 的图片会随 CloudKit 同步，付费账号后要注意流量；免费账号暂不受影响。

**建议的开工顺序（一条条来）**
- T1 模型层：`Evidence` + 关系 + 三处 schema + 迁移自检
- T2 设置开关「截图存进材料」+ 本地化
- T3 编辑器「材料」区块（加文本 / 看图片 / 删除）
- T4 Capture Intent + Vision OCR（先只打印行与坐标，验取词）
- T5 解析器：条目切分 + 时间/地点 + 单条/多条
- T6 确认面板（Optional 占位、勾选、目标清单、时间归属）
- T7 测试（解析用例 + 假截图）+ 三端编译 + 装机验证

### 5.2 还没做的（2026-10-22 收尾时）

| 事项                      | 卡在哪                                    |
| ----------------------- | -------------------------------------- |
| **VoiceOver 实听**        | 用户在图书馆不能出声，等安静环境自己戴耳机逐个听；代码层已过第一轮      |
| **Siri / Spotlight 实测** | 需要出声和真人操作。元数据已验证导出（3 个 intent + 3 条短语） |
| **iPad 版式定稿**           | 720 居中已上机，等用户看过真实设备再定要不要垂直居中           |
| **手表真机安装**              | 排到「手表端功能补完 + 付费账号到位」之后                 |
| **键盘收起「不太跟手」**          | 已保留跟手滚动 + 加了点击空白收起；手感仍偏滞，候补方案见 10.1    |
| **分享码还能更短**             | 已改为「只发二维码」，文本码撤掉了，此项作废                 |
| **菜单实色**                | SwiftUI `Menu` 底色改不了，能做的是统一 tint，已做完   |

## 6. 已完成（别再重做）

| 模块          | 要点                                                                                                                                                                                                                                        |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| OOBE        | 4 页，最后一页申请通知权限                                                                                                                                                                                                                            |
| Today       | 一屏看完，进度环；口径全在 `TodayScope`                                                                                                                                                                                                                |
| 输入          | 自然语言日期（中/英）：`明天 3pm`、`tomorrow 3pm`                                                                                                                                                                                                       |
| 模板          | 可反复拉取；`ListTemplate → TodoList` 一对一复制。**详情页本身就能加任务**（2026-10-21）：每条标题是可编辑单行 `TextField`，末尾「Add task」插入并聚焦，**回车直接建下一条**，**左滑删除**（页面已从 ScrollView 改成 `List` + `swipeActions`，不然没有原生滑动删除）；**空行不会留**（失焦即删、重复回车不叠空行）；仍保留长按删除作为替代入口。工具栏铅笔只改模板属性 |
| 例行清单        | 每天/周/月；错过会弹窗问「补最新一期 / 全补 / 不补」，最多 30 期；31 号遇短月落月末，不漂移                                                                                                                                                                                     |
| 清单耗时        | Browse 的 Previous ToDos 显示「创建 → 最后勾完」，取消再勾会变长                                                                                                                                                                                             |
| 分享为文本       | 任何清单都能导，`[x] / [ ]` 标注，行首不带时间戳                                                                                                                                                                                                            |
| 等待中         | 独立分组，**不计入任何数字**（progress / isFinished / doneTaskCount / openTaskCount / Today 快照 / Today 智能列表 六处都要排除）                                                                                                                                    |
| watchOS     | 手机推「今天剩余」快照（`updateApplicationContext`），手表镜像到本地库，勾选回传；口径同样走 `TodayScope`                                                                                                                                                                  |
| 本地化         | 四语言 205 条，占位符已校验一致                                                                                                                                                                                                                        |
| 无障碍         | Dynamic Type（`ScaledFont.swift`）、VoiceOver 标签、深色模式                                                                                                                                                                                        |
| 键盘收起        | `TaskListView` 挂 `KeyboardDismissScroll`（`TosnDOs/Support/`）：`scrollDismissesKeyboard(.interactively)` + 软键盘在屏时才 `scrollBounceBehavior(.always)`，所以任务不满一屏也能拖一下收键盘，键盘没弹时列表不会乱弹                                                             |
| 空状态         | 没任务时卡片显示 ✓ `Nothing due today`，且**不画进度环**（`remaining + done == 0` 时不渲染），避免「全清了」配 0% 环的矛盾                                                                                                                                                  |
| URL scheme  | `TosnDOs/Info.plist` 只放 `CFBundleURLTypes`（`tosndos`），靠 `GENERATE_INFOPLIST_FILE = YES` 与自动生成的键合并；该文件已加进同步组例外集，否则会 `Multiple commands produce Info.plist`                                                                                 |
| 录入键         | 保持 `submitLabel(.done)`。试过改文案：iOS 根本没有「Add」返回键，`.return` 在多行框会变换行（会坏），`.go` 能用但用户觉得 Done 就行——**这类标签判断以后先问用户**，别自己换                                                                                                                        |
| 键盘收起        | 两条路并存：拖动跟手收（`.interactively`）+ **点击列表任意空白收起**（`dismissKeyboardOnTap`，走 `resignFirstResponder`）。**注意只在 TaskListView 挂**——模板页的输入框在 List 里面，挂上会把自己点没                                                                                         |
| App Intents | `TosnDOs/Intents/`：加任务（走 `NaturalDateParser`）、按名字完成任务、打开 Today；`TosnShortcuts` 三条短语。共用 `AppContainer.boot.container`，不需要 App Group。**短语里不能插 String 参数**，只能 AppEntity/AppEnum                                                              |
| 分享码         | `Shared/Transfer/ListCodec.swift`：JSON（单字母键、空字段省略）→ deflate → Base64URL，前缀 `TOSN1:`；日期存相对天数，放几天再导入也不会错。导入走 `tosndos://import?c=`，**永远新建清单**                                                                                               |
| 备份恢复        | `TosnDOs/Support/BackupFile.swift`：全量 JSON（清单/任务/模板/子项，带 schema 号）；设置页导出到文件，导入时弹「合并 / 覆盖」。**嵌套类型别叫 `TemplateItem`**，会和模型撞名                                                                                                                |
| 商店截图        | `docs/appstore/`：iPhone Today / Browse、iPad、Watch、Mac 各一张，带机身边框。合成脚本 `frame.py`（Pillow），边框由截图 alpha 的圆角半径推算，不是硬编码机型                                                                                                                       |

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

---

## 8. 2026-10-21 这次会话做了什么

一天之内从「没有仓库」推到「手机上能跑」。

1. **上线**：`gh` 建库并推送 → <https://github.com/LycoRiko/tosn-dos>；README 占位符换成真实地址
2. **签名**：免费 Personal Team `S465RV3CLC` 写进 6 处配置；`xcodebuild` 读不到账号会话（`No Accounts`），  
   最终靠 Xcode 里 ⌘R 一次生成描述文件，之后 CLI 才能签
3. **真机链路**：`project.pbxproj.1`（裁剪 App Group / iCloud）+ `devbuild.sh` 出 IPA；  
   校园网不可达，**iPhone 热点**下 `devicectl` 走 `localNetwork` 装成功
4. **键盘**：`KeyboardDismissScroll` —— 拖列表收键盘，短列表也能拖（`.scrollBounceBehavior(.always)` 只在软键盘在屏时开）
5. **商店截图**：`docs/appstore/` 五张带机身边框，`frame.py` 从 alpha 反推圆角
6. **收尾清理**：URL scheme（`TosnDOs/Info.plist` + 同步组例外集）、两条告警、空状态文案、  
   iPad 720 列宽、本地化审计（205 条全齐）

**这一天的教训**：账号/设备/沙箱这类外部卡点，`xcodebuild` 的报错经常指向错误的地方，  
要查到设备端的 `developerModeStatus`、钥匙串里的 `find-identity`、`devicectl` 的 `tunnelState` 才看得见真相。

---

## 9. 已知局限（诚实清单）

**签名与分发**

- 免费账号：真机**没有 App Group / iCloud**，Widget 读不到数据；包 **7 天过期**，每周要重装
- 没有 App Store 资产：图标之外的隐私清单、分级、描述都还没准备
- `project.pbxproj.1` 与 `devbuild.sh` 只在本机（`.git/info/exclude`），换机器要重建

**质量保证**

- **只有逻辑层测试**：`TosnDOsTests` 8 个用例；**没有 UI 测试**，界面回归仍靠四端编过 + 手点
- 只在 iPhone 16 Pro Max（iOS 27）+ 模拟器上跑过；旧机型、iPad 真机都未实测
- **证据（Evidence）与截屏导入都还没实现**，属于 2026-10-29 新提案
- VoiceOver 只做了标签和 Dynamic Type，**没跑过完整朗读流程**
- 本地化审计是脚本一次性跑的，没有 CI 守着

**产品面**

- iPad 只有第一版列宽；macOS 侧栏/多列没有专门设计
- 手表只在模拟器验证过，**真机从未安装**（等付费账号后再排）
- 备份/恢复已完成（`.tndbackup`，合并或覆盖）；分享码已完成（只发二维码）
- 「等待中」之外的业务形态（子任务批量、依赖）没有
- 无明显性能评估：大清单、Widget 刷新频率、CloudKit 首次同步都没压过
- 键盘：跟手滚动 + 点击空白收起都已上，**用户 2026-10-29 确认手感可接受**

---

## 10. 2026-10-22 一天的工作

一天内从「没有仓库」做到「手机上能跑、四端编译通过、有 8 个单元测试」。

### 10.1 键盘（iOS）

- 拖列表收键盘：`.scrollDismissesKeyboard(.interactively)`，但因为短列表没有滚动距离，额外在  
  **软键盘在屏时**打开 `.scrollBounceBehavior(.always)`，让它能拖得动。
- **点列表任意空白也收起**：`simultaneousGesture(TapGesture)` 发 `resignFirstResponder`。  
  只能挂在任务列表上——模板页的输入框在 List 内部，挂上会把自己点没。
- 手感仍偏滞（用户反馈）。候补：换 `.immediately`（一拖就收但不跟手）、或自绘手势（和行滑动打架，风险最高）。

### 10.2 模板

- 根因修复：模板详情页原来是只读的，工具栏和底部**都**放「加入工作区」，编辑入口只在长按菜单里  
  → 用户找不到加任务的地方。典型的「入口缺失 + 重复动作」。
- 现在详情页就是编辑页：每行是单行 `TextField`，回车建下一条，左滑删除，**空行失焦即删**。
- 排版改成和主页一致（圆圈 + 标题 + meta），右滑出「设置 / 删除」，`TemplateItemSheet` 管备注/优先级/检查项。
- 模板库从 `LazyVGrid` 改 `List`（网格不支持 `swipeActions`）：紧凑行 + 多选删除。

### 10.3 首页与浏览页

- 任务行右滑 = 设置 + 删除；完成只走左边的圈（原来滑动里还有一份"完成"，属重复动作）。
- 空状态：卡片说 `Nothing due today`，下面的空提示改成 `No open tasks`（原来重复两遍）。
- 往期清单搬进二级页，按**完成日**分组（今天 / 昨天 / 10月18日），副标题显示模板名 + 耗时。
- 每组多一行「当日新增」，点进去是那天手输的任务。日期集合取**并集**（完成日 ∪ 新增日），  
  否则"只打字没完成清单"的那天会整天消失。
- Settings 从 `Form` 改 `List`，与 Browse 共用同一套容器/背景/底部留白。

### 10.4 分享与备份


- 分享：清单 → 紧凑 JSON → deflate → Base64URL，前缀 `TOSN1:`；日期存**相对天数**，放几天再导入也不会错。
  文本码太长，最终只保留**二维码**。
- 二维码内容改成深链 `tosndos://import?c=...`：**系统相机只对 URL 提示打开**，裸文本没有这个选项，
  所以完全不用写扫描器。
- macOS 不用摄像头：**把二维码图片或备份文件拖进窗口**即可导入，`CIDetector` 本机解码，
  支持 png / jpeg / heic / webp，识别失败再 2× 放大重试。
- 备份导出为 `.tndbackup`（内容仍是 JSON，`Info.plist` 已声明该 UTType），导入按内容解析，旧 `.json` 也能吃。
  导入时询问「合并 / 覆盖」。

### 10.5 App Intents
- 加任务（走自然语言日期）、按名字完成任务、打开 Today；三条 Siri 短语。
- 共用 `AppContainer.boot.container`，不需要 App Group。
- 坑：快捷指令短语里**不能插 String 参数**，只接受 AppEntity/AppEnum。

### 10.6 数据层
- `TodoList` 新增 `completedAt` 与 `sourceTemplateName`（都带默认值，轻量迁移）。
- 完成时刻收敛到一个函数 `reconcileCompletion()`：全勾且没记过 → 记一次；有未勾 → 清空。
  五个入口统一调用（勾选、模板生成、删除任务、备份恢复、码导入），避免"永远停在昨天"。

### 10.7 质量
- 新增 `TosnDOsTests`（手写 pbxproj 才有的 target，scheme 里配 `Testables`）。
- **不要用 TEST_HOST**：宿主模式会 `test runner hung before establishing connection`。
  改成把 6 个纯逻辑文件直接编进测试包，8 个测试全过：
  自然日期解析、完成时间幂等、分享码往返、垃圾码拒绝、备份往返、二维码 png/jpeg/heic 往返。
- 假数据跑过两轮截图，修掉：模板卡片被拉成大方块、往期副标题日期错、`0m` 耗时、
  底部被 tab bar 压住、相册权限在无关页面弹窗。

### 10.8 真机与分发
- 校园网不可达（客户端隔离），**开 iPhone 热点**后 `devicectl` 走 `localNetwork` 直接装。
- `build/ipa/TosnDOs.ipa` 930K，含本轮全部改动；免费账号 7 天有效期。
- 坑：`open -n app --args -seedDemo` 参数**不会传进进程**，要直接跑 `Contents/MacOS/TosnDOs`。

---

## 11. 下次开工的建议顺序

1. **无障碍第二轮**：开 Accessibility Inspector 逐屏朗读，把 label / traits / 阅读顺序过一遍
2. **Siri 与 Spotlight 实测**（需要出声）
3. **iPad 真机看版式**，定是否垂直居中
4. 之后才是新功能：通知「稍后提醒」、手表复杂功能、智能列表扩展

---

> 原第 12 节「截图 → 摘任务」已并入 5.3 / 5.4，细则以那两节为准。
