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
| 真机 | iPhone 16 Pro Max（iOS 27.0.1）已装本轮构建（930K，含全部改动），免费账号 7 天有效期 |
| 签名 | Team `S465RV3CLC`（REGer Bili / Personal Team，免费） |
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
| 模拟器里查不到键盘相关状态 | 模拟器默认接了硬件键盘，软键盘不弹出。改成强制分支或用 `-forceBounce` 这类临时开关验证 |

---

## 5. 待办

### 5.1 分享码（已完成，2026-10-22）

清单 → 紧凑 JSON → deflate → Base64URL，前缀 `TOSN1:`；二维码内容包成 `tosndos://import?c=`。
文本码因为太长已撤掉，只保留二维码。实现见 `Shared/Transfer/ListCodec.swift`、`TosnDOs/Support/QRCode.swift`。

### 5.2 还没做的（2026-10-22 收尾时）

| 事项 | 卡在哪 |
|---|---|
| **VoiceOver 实听** | 用户在图书馆不能出声，等安静环境自己戴耳机逐个听；代码层已过第一轮 |
| **Siri / Spotlight 实测** | 需要出声和真人操作。元数据已验证导出（3 个 intent + 3 条短语） |
| **iPad 版式定稿** | 720 居中已上机，等用户看过真实设备再定要不要垂直居中 |
| **手表真机安装** | 排到「手表端功能补完 + 付费账号到位」之后 |
| **键盘收起「不太跟手」** | 已保留跟手滚动 + 加了点击空白收起；手感仍偏滞，候补方案见 10.1 |
| **分享码还能更短** | 已改为「只发二维码」，文本码撤掉了，此项作废 |
| **菜单实色** | SwiftUI `Menu` 底色改不了，能做的是统一 tint，已做完 |


## 6. 已完成（别再重做）

| 模块 | 要点 |
|---|---|
| OOBE | 4 页，最后一页申请通知权限 |
| Today | 一屏看完，进度环；口径全在 `TodayScope` |
| 输入 | 自然语言日期（中/英）：`明天 3pm`、`tomorrow 3pm` |
| 模板 | 可反复拉取；`ListTemplate → TodoList` 一对一复制。**详情页本身就能加任务**（2026-10-21）：每条标题是可编辑单行 `TextField`，末尾「Add task」插入并聚焦，**回车直接建下一条**，**左滑删除**（页面已从 ScrollView 改成 `List` + `swipeActions`，不然没有原生滑动删除）；**空行不会留**（失焦即删、重复回车不叠空行）；仍保留长按删除作为替代入口。工具栏铅笔只改模板属性 |
| 例行清单 | 每天/周/月；错过会弹窗问「补最新一期 / 全补 / 不补」，最多 30 期；31 号遇短月落月末，不漂移 |
| 清单耗时 | Browse 的 Previous ToDos 显示「创建 → 最后勾完」，取消再勾会变长 |
| 分享为文本 | 任何清单都能导，`[x] / [ ]` 标注，行首不带时间戳 |
| 等待中 | 独立分组，**不计入任何数字**（progress / isFinished / doneTaskCount / openTaskCount / Today 快照 / Today 智能列表 六处都要排除） |
| watchOS | 手机推「今天剩余」快照（`updateApplicationContext`），手表镜像到本地库，勾选回传；口径同样走 `TodayScope` |
| 本地化 | 四语言 205 条，占位符已校验一致 |
| 无障碍 | Dynamic Type（`ScaledFont.swift`）、VoiceOver 标签、深色模式 |
| 键盘收起 | `TaskListView` 挂 `KeyboardDismissScroll`（`TosnDOs/Support/`）：`scrollDismissesKeyboard(.interactively)` + 软键盘在屏时才 `scrollBounceBehavior(.always)`，所以任务不满一屏也能拖一下收键盘，键盘没弹时列表不会乱弹 |
| 空状态 | 没任务时卡片显示 ✓ `Nothing due today`，且**不画进度环**（`remaining + done == 0` 时不渲染），避免「全清了」配 0% 环的矛盾 |
| URL scheme | `TosnDOs/Info.plist` 只放 `CFBundleURLTypes`（`tosndos`），靠 `GENERATE_INFOPLIST_FILE = YES` 与自动生成的键合并；该文件已加进同步组例外集，否则会 `Multiple commands produce Info.plist` |
| 录入键 | 保持 `submitLabel(.done)`。试过改文案：iOS 根本没有「Add」返回键，`.return` 在多行框会变换行（会坏），`.go` 能用但用户觉得 Done 就行——**这类标签判断以后先问用户**，别自己换 |
| 键盘收起 | 两条路并存：拖动跟手收（`.interactively`）+ **点击列表任意空白收起**（`dismissKeyboardOnTap`，走 `resignFirstResponder`）。**注意只在 TaskListView 挂**——模板页的输入框在 List 里面，挂上会把自己点没 |
| App Intents | `TosnDOs/Intents/`：加任务（走 `NaturalDateParser`）、按名字完成任务、打开 Today；`TosnShortcuts` 三条短语。共用 `AppContainer.boot.container`，不需要 App Group。**短语里不能插 String 参数**，只能 AppEntity/AppEnum |
| 分享码 | `Shared/Transfer/ListCodec.swift`：JSON（单字母键、空字段省略）→ deflate → Base64URL，前缀 `TOSN1:`；日期存相对天数，放几天再导入也不会错。导入走 `tosndos://import?c=`，**永远新建清单** |
| 备份恢复 | `TosnDOs/Support/BackupFile.swift`：全量 JSON（清单/任务/模板/子项，带 schema 号）；设置页导出到文件，导入时弹「合并 / 覆盖」。**嵌套类型别叫 `TemplateItem`**，会和模型撞名 |
| 商店截图 | `docs/appstore/`：iPhone Today / Browse、iPad、Watch、Mac 各一张，带机身边框。合成脚本 `frame.py`（Pillow），边框由截图 alpha 的圆角半径推算，不是硬编码机型 |

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
- **零自动化测试**：没有 unit / UI test，回归全靠"四端编过 + 手点"
- 只在 iPhone 16 Pro Max（iOS 27）+ 模拟器上跑过；旧机型、iPad 真机都未实测
- VoiceOver 只做了标签和 Dynamic Type，**没跑过完整朗读流程**
- 本地化审计是脚本一次性跑的，没有 CI 守着

**产品面**
- iPad 只有第一版列宽；macOS 侧栏/多列没有专门设计
- 手表只在模拟器验证过，**真机从未安装**（等付费账号后再排）
- 数据只有「分享为文本」单向导出，**备份/恢复排进今晚**（见 5.2）
- 分享码**排进今晚**；「等待中」之外的业务形态（子任务批量、依赖）没有
- 无明显性能评估：大清单、Widget 刷新频率、CloudKit 首次同步都没压过
- 键盘收起手感偏滞，且点击空白处不收（今晚一并修，见 5.2）

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
