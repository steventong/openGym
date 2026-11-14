# 训练实时活动

开始训练后，App 通过 ActivityKit 启动一条实时活动。灵动岛紧凑区显示动作名与组数（休息时显示倒计时），展开区和锁屏卡片显示训练名称、动作、当前组、重量/次数与操作。

- **完成本组**：调用与 Apple Watch 相同的完成命令，沿用训练草稿的组型、左右侧、休息和保存逻辑。从实时活动完成动作最后一组后不启动休息，自动切换到下一个未完成动作；全部完成后显示“打开App”，回训练页保存。重复命令不会再次切换动作或误记下一组。
- **结束休息**：必须主动点击才清除休息；自然到零保留该操作，倒计时停在零。点击后在原位置显示灰色不可点击的“完成本组”，不显示保护期倒计时；5 秒保护结束后恢复可用。
- **统一组合按钮**：锁屏、灵动岛与 watchOS 直接在各自的按钮中使用 `TrainingActionLabel`，始终只有一个操作按钮。完成本组后，下一操作也有 5 秒保护；有休息时，前 5 秒保护期只显示灰色休息倒计时，隐藏下排“结束休息”图标与文字，并保留其布局空间，不额外显示保护期倒计时；保护期结束后显示“结束休息”，按钮恢复可用。“完成本组”上方不显示“准备好后开始下一组”提示。手机录入页的勾选不受该限制。展开区域为圆弧边缘保留水平和底部留白，按钮有效高度至少 44 点。组数不加“接下来”前缀，休息标签与倒计时右对齐。
- **紧凑动作名**：不设固定的 72 点宽度上限，交由系统按设备和灵动岛可用空间显示单行名称。
- **信息与全宽按钮**：训练名称／动作序号、动作名、组数／重量／次数依次排在按钮上方。组数保持绿色、重量白色、次数浅灰；三位等宽倒计时与放大的 `S` 统一放在按钮上排，下排为操作图标和文字。旧活动内容缺少新增字段时仍可解码并显示原有数据。
- **固定尺寸与按钮内状态**：不再追加独立的保存/错误提示行。同步保存时在原按钮位置显示禁用的“正在保存”；保存失败、输入未完成等用按钮短标题引导回 App，完整说明保留为辅助功能提示。完成本组、结束休息和忙碌状态使用同一个全宽、62 点高的位置；紧凑右侧在倒计时／组数间固定为 48 点，避免状态切换改变布局尺寸。
- **休息提醒**：「设置 → 系统通知」提供「休息结束通知」开关、权限状态与系统通知设置入口。默认开启，第一次在前台训练或主动开启时请求授权；每次休息按绝对结束时间安排本地通知，前台只保留声音，不显示横幅或通知中心记录；进入前台清理旧通知。调整、跳过、删除训练会更新/取消提醒，关闭开关立即取消待发提醒。通知由独立服务管理，不依赖实时活动是否启用；手表和灵动岛操作会等待提醒安排完成。
- 点击卡片打开 `opengym://workout`。训练保存成功或删除草稿后，结束实时活动并清理待发休息提醒。保存失败时保留训练。

`WorkoutActivityRuntime` 让前台页面和后台 `LiveActivityIntent` 使用同一个账号隔离的 `GymStore`，冷启动也恢复本机草稿。按钮携带账号、训练 ID、草稿版本和目标组；重复完成不会取消勾选或误记下一组，修改/重排后的旧按钮会拒绝执行并更新显示。动作计时、未填完数据、同步或本机保存错误时禁用相应完成命令。

完成/下一动作命令的版本校验排除 `nativeRest` 和 `nativeActionReadyAt`，避免调整或结束休息后、系统尚未重绘时误拒绝未变更的目标组；结束休息仍严格校验完整草稿版本，避免取消新计时。旧版实时活动载荷和手表命令保持原有校验。`LiveActivity` 日志记录 Intent 接收、命令接受结果及刷新耗时，不记录账号、训练内容或命令载荷。

工程最低版本为 iOS 26（App 与 Widget 扩展一致）。新增 `OpenGYMWidgets` 扩展（`me.itwl.opengym.widgets`），共享定义按职责位于 `Shared/Models/LiveActivity/`、`Shared/Services/LiveActivity/`、`Shared/ViewModels/LiveActivity/` 和 `Shared/Views/LiveActivity/`；重建工程运行 `scripts/generate-project.rb`，现有工程可运行 `scripts/configure-live-activity.rb`。扩展无需共享账号凭据或额外 App Group。

实现参考：[Apple Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)、[Apple 交互式实时活动](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)。按钮交互由系统按锁屏认证状态处理；专注模式、静音与通知设置可能影响声音和横幅。

## 验证（2026-11-02）

- iPhone 18 Pro / iOS 27.0 模拟器：应用和扩展编译通过；全套 XCTest 138 项通过，其中新增 `WorkoutActivityTests` 10 项。
- 虚构账号 `live-activity-qa`、回环服务 `localhost:19387`：开始训练显示紧凑/展开灵动岛；在桌面直接完成第一组后，本机草稿仅第一组变为完成，启动 15 秒休息；系统日志确认“休息结束”横幅送达。
- 已在 Device Hub 实际检查最终双按钮布局与锁屏卡片。iOS 27 模拟器的 `simctl` 截图未包含系统渲染的实时活动，视觉验收以 Device Hub 画面为准。
- 锁屏点击“结束休息”后读回确认计时已清除、完成组数不变；点击卡片返回当前训练。验收结束后通过 App 删除虚构训练，检查实时活动清理。
- 临时验收资料在忽略目录 `artifacts/live-activity/`。未发布 TestFlight，真机锁屏认证、声音及长期后台行为仍需真机验收。

## 点击与布局修复验证（2026-11-03）

- 旧实现新增的两项回归测试复现：调整/结束休息后，未变更的目标组命令被判定过期；修复后全套 158 项 XCTest 通过。随后加入自动切换动作、合入共享手表逻辑和单行数据字段，最终实时活动与手表相关 31 项测试通过，包含旧版活动内容解码回归。
- OpenGym Input QA / iOS 26.5 模拟器、虚构账号 `live-activity-qa`：灵动岛单击完成组后读回本机草稿确认对应组已完成；结束休息后可继续下一组。实测 Intent 内处理与 ActivityKit 刷新约 0.08–0.11 秒，不含系统唤醒和最终绘制时间。
- Device Hub 实际画面确认：按钮无圆弧裁切、休息时只显示结束休息、组数无前缀、计时右对齐；动作最后一组完成后直接显示下一个动作，全部完成显示“打开App”，点击返回训练页。紧凑名称已移除自定义宽度限制，但系统仍可能截断长名称。虚构训练草稿与截图保留在 `artifacts/live-activity/`，已清理模拟器中的本轮活动草稿。
- 本轮未进行真机复现验收或 TestFlight 发布；不能以模拟器结果排除真机上的其他点击延迟原因。
- 最终三行布局在模拟器的灵动岛展开区、锁屏卡片系统渲染画面中检查，42 mm Apple Watch 模拟器使用已有 Debug 预览确认单行文字、颜色和小屏适配；Watch 预览未代替真机连接验收。截图为 `island-inline-summary.png`、`lock-inline-summary.png`、`watch-inline-summary.png`。

## 2026-11-03 设置与休息通知验证

- 休息通知从 ActivityKit 协调器分离，设置提供本机持久化开关、权限提示与系统设置入口。9 项新增测试覆盖连续休息、重复发布、调整/跳过、开关持久化、授权拒绝及恢复、授权/安排期间训练变化、到期不重放与失败重试；连同实时活动和手表测试共 42 项通过。
- OpenGym Input QA / iOS 26.5 模拟器核对已配对连接信息、服务器地址、重新配对确认、表单展开及取消返回，系统通知分区与权限状态可见。本轮未实测真机横幅、锁屏声音或专注模式投递。

## 点击诊断日志

系统统一日志：subsystem `me.itwl.opengym`，category `LiveActivity`，消息前缀 `LA`。正常阶段使用 notice，失败使用 error；发布构建也会记录，不依赖 Debug 开关。消息为 JSON，包含进程 `run` / `pid`、序号 `seq` 和点击追踪 `trace`。每次调用有独立 trace；`command` 是命令 ID 的摘要，用于识别不同点击实际重放了同一个命令。合并的刷新/提醒任务保留所有相关 trace。

| 日志阶段 | 能定位的情况 |
| --- | --- |
| `runtime.initialize.*` / `draft.restore.*` / `app.*` | 冷启动、草稿恢复、版本/系统、前后台、受保护数据可用性、打开训练链接 |
| `intent.received` / `runtime.access.*` | 系统是否进入 App Intent、取得运行时是否停滞 |
| `activity.command.*` / `activity.revision.checked` | 载荷无效、版本、账号/训练不匹配、完整/排除休息后的版本校验、休息归属变化 |
| `remote.command.end` 的 `outcome` | `applied`、`duplicate_acknowledged`、`revision_mismatch`、`syncing`、`save_error`、`work_timer_running`、`invalid_set_input`、`target_mismatch`、`set_edit_failed`、`save_failed` 等具体结果 |
| `remote.set.*` / `draft.save.*` / `remote.receipt.saved` / `remote.auto_advance` | 对应组是否执行、每次写入和回执是否成功、是否自动换动作；规则异常另记 `*.rules.failed` / `draft.mutation.failed` |
| `intent.reminders.*` / `reminder.*` | 等待通知服务、权限查询/授权、安排提醒、跳过/取消原因、异步期间休息变更、失败与耗时 |
| `intent.refresh.*` / `activity.flush.*` / `activity.reconcile.*` | 刷新排队/合并、投影状态和载荷大小、发布的按钮命令摘要 |
| `activity.request.*` / `activity.update.*` / `activity.end.*` | ActivityKit 调用开始/返回；未变化而跳过、活动权限关闭、后台无匹配活动、旧/重复活动结束 |
| `intent.finished` | 本次调用返回及总耗时；有 begin 无 end 时，结合进程变化和系统日志排查等待、挂起或终止 |

日志只记录布尔状态、动作/组索引、完成计数、固定原因码、摘要和耗时；不记录账号/训练 ID 原文、服务器地址、凭据、训练名称、动作名称、重量次数、完整命令或 NSError userInfo/错误描述。错误保留 domain/code。

复现时记下时间（含时区）、锁屏或灵动岛、是否正在休息及是否刚修改训练。尽快通过 Mac“控制台”收集对应 iPhone 的日志，按上述 subsystem/category 筛选并保留前后约两分钟；系统控制留存，日志不保证永久保存。模拟器可用：

```sh
xcrun simctl spawn <SIMULATOR-UDID> log show --last 10m --style compact \
  --predicate 'subsystem == "me.itwl.opengym" AND category == "LiveActivity"'
```

证据边界：按压动画由系统绘制，App 无法记录动画前的每次物理触摸，也无法获知此次点击来自锁屏还是灵动岛。缺少 `intent.received` 还需排除日志采集遗漏；`activity.update.end` 仅证明 ActivityKit 调用返回，不能证明系统界面已重绘。若出现 `intent.unexpected_widget_process`，说明 Intent 意外在扩展执行，未修改训练。

诊断补充验证（2026-11-03）：全套 188 项 XCTest 通过；新增用例覆盖跨点击关联/重复去重、具体拒绝码、真实文件写入失败、合并提醒保留多个 trace 和日志不含敏感原文。Release 模拟器构建通过；系统默认日志查询（未开启 info/debug）读回命令与启动/刷新记录，测试样本保存在 `artifacts/live-activity/diagnostics-events.json`。本轮 Mac 锁定，未追加新的界面按钮点击验收，未进行真机复现。

## 2026-11-04 共享组合按钮

`Shared/Models/Training/TrainingActionTiming.swift` 定义 5 秒保护和休息待结束状态；绝对截止时间 `nativeActionReadyAt` 保存于手机训练草稿，经 WatchConnectivity 与 ActivityKit 同步。两个文字操作在手机执行层再次校验，不能跨端绕过；重复完成回执不会延长保护。手机行内勾选沿用原编辑路径。

`Shared/Views/Timer/` 提供 `TrainingCountdownText`，`Shared/Views/TrainingAction/` 提供双行标签 `TrainingActionLabel`。手表和 Live Activity 直接在各自的 `Button`／`Link` 中声明标签，不再通过泛型控件闭包转发；手表负责保护到期刷新，Live Activity 使用系统 stale 状态。旧单行按钮和手表专用标签已经移除；完成本组、结束休息、处理中及连接／重试都使用这套标签。休息状态上排显示标签和三位等宽秒数，下排保留操作图标及文字；单位字号为 20 点（手表按整体比例缩放）。所有状态的禁用配色来自同一处，5 秒保护、调用方禁用和父级 `.disabled` 都显示灰色。

系统日期文本驱动数字更新，不用整页 `TimelineView`；watchOS 10 回退仅在数字子视图内计时。App/Watch 仅在保护到期时更新按钮可用性；Live Activity 使用 `actionReadyAt` 作为 stale date，并直接使用 `context.isStale` 解除保护状态，避免依赖视图归档时求值的 `Date()` 而一直灰色。系统 stale 状态可能延迟数分钟，因此协调器还在保护截止时主动重新发布活动；短时后台任务覆盖这 5 秒，结束或切换训练时取消旧刷新。执行层仍按绝对时间验证。保护到期前灰色不可点击，标题与填充色采用短暂过渡，尊重减少动态效果设置。

锁屏与展开灵动岛改用全宽 62 点按钮，倒计时统一放在按钮内部；紧凑／最小灵动岛沿用适合其空间的数字／图标。`Shared/Views/LiveActivity/WorkoutActivityContent.swift` 承载实际 WidgetKit 内容，也用于原生尺寸验证。中英文、296／347／384 点宽度、休息／完成／保护／忙碌状态的高度测试通过；展开内容为顶部系统区域额外预留 36 点，整体不超过 160 点。53 项训练按钮、手表遥控与 Live Activity 测试通过，截图在忽略目录 `artifacts/shared-action-layout/`。这轮验证覆盖模拟器和原生内容渲染，尚未完成真实锁屏／灵动岛系统容器及真机验收。

最终倒计时统一使用大写 `S`（如 `90S`、`5S`、`0S`），包括动作计时的暂停状态；训练总时长的正计时保留原格式。共享按钮相关 62 项 XCTest 最终通过，重构阶段全套 213 项通过，iOS/Widget 与 watchOS 构建通过。手表模拟器验证灰色保护倒计时、到期恢复与休息自然到零不切换；证据在 `artifacts/shared-training-action/`。本轮 Device Hub 未能连接新模拟器画面，锁屏的系统动画和 stale-date 重绘仍需真机验收，未发布 TestFlight。

## 2026-11-05 点击后持续占位块

在系统托管的 Live Activity 中复现完成组后整块内容成为占位块。系统 `WidgetRenderer_Activities` 日志明确报告 `Errors.noType(...OpenGymWidgets.TrainingCountdownSecondsStyle...)`：普通 App 内可以运行的自定义 `DiscreteFormatStyle` 不能由系统渲染进程解码。原来的同进程 SwiftUI 尺寸测试无法覆盖这个问题。

后续真机排查确认 `Date.ComponentsFormatStyle.timeDuration` 与 `TimeDataSource.dateRange(endingAt:)` 仍不兼容：格式器试图移动数据源固定的上界，触发 `Misconfigured Text(_:format:)` 并导致内容空白。此前仅检查 `noType` 的验证不充分。最终 `TrainingCountdownText` 在 Live Activity 中改用系统 `Text(timerInterval:countsDown:showsHours:)`，经用户同意采用 `1:30` 格式；App／Watch 使用仅刷新数字子视图的 Timeline 保留秒数和大写 `S`。保留 62 pt 大按钮、配色和操作文案。到期区间钳制到零，补充到期布局检查。

`WorkoutActivityTests.testSystemRendererAfterCompletingSet` 是仅限模拟器的显式集成探针：在 QA 模拟器为 App 设置 `OpenGymActivityRendererQA=true` 后运行，创建测试活动，执行完成组及结束休息，再结束活动。普通测试默认跳过；验证后应删除该开关。需同时检查系统渲染日志，不能仅把 ActivityKit 更新成功当作画面成功。修复前解码错误、修复后 iOS 26.5 的系统日志保存在忽略目录 `artifacts/live-activity-render-fix/`。

### 真机恢复与最终验证

真机曾在活动请求成功、授权开启的情况下始终处于 `stale`。协调器现在仅把未来的五秒保护截止时间作为 stale date；已过期的截止时间转为 nil。是否需要更新同时比较训练状态、stale date 和 relevance score，训练数据相同时也能恢复活动元数据。

本轮 33 项原生回归通过，1 项手动系统渲染探针按默认设置跳过。真机构建成功并更新安装到已连接的 iPhone 17 Pro Max；用户确认展开后内容正常显示。保留当前大尺寸；Watch 与 Live Activity 的独立外观设计按用户要求留待以后。
