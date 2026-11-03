# 训练实时活动

开始训练后，App 通过 ActivityKit 启动一条实时活动。灵动岛紧凑区显示动作名与组数（休息时显示倒计时），展开区和锁屏卡片显示训练名称、动作、当前组、重量/次数与操作。

- **完成本组**：调用与 Apple Watch 相同的完成命令，沿用训练草稿的组型、左右侧、休息和保存逻辑。从实时活动完成动作最后一组后不启动休息，自动切换到下一个未完成动作；全部完成后显示“打开App”，回训练页保存。重复命令不会再次切换动作或误记下一组。
- **结束休息**：清除当前休息计时。锁屏卡片保留完成按钮；灵动岛若延迟刷新到期状态，可先点“结束休息”再完成本组。倒计时到零不会倒数成负数。
- **灵动岛按钮**：休息中只显示“结束休息”；系统标记倒计时到期或主动结束休息后，才显示“完成本组”或“下一个动作”。展开区域为圆弧边缘保留水平和底部留白，按钮有效高度至少 44 点。组数不加“接下来”前缀，休息标签与倒计时右对齐。
- **紧凑动作名**：不设固定的 72 点宽度上限，交由系统按设备和灵动岛可用空间显示单行名称。
- **三行布局**：训练标题与休息标签同一行，动作标题与倒计时同一行，组数/重量/次数与按钮同一行。组数保持绿色、重量白色、次数浅灰；Apple Watch 同步采用这一单行彩色训练信息。旧活动内容缺少新增字段时仍可解码并显示原有数据。
- **固定尺寸与按钮内状态**：不再追加独立的保存/错误提示行。同步保存时在原按钮位置显示禁用的“正在保存”；保存失败、输入未完成等用按钮短标题引导回 App，完整说明保留为辅助功能提示。灵动岛主按钮、休息按钮和忙碌状态均为 104×44 点；倒计时消失后保留 76 点宽和相同字号的隐藏占位，紧凑右侧在倒计时/组数间固定为 48 点，避免组件显隐改变布局尺寸。
- **休息提醒**：「设置 → 系统通知」提供「休息结束通知」开关、权限状态与系统通知设置入口。默认开启，第一次在前台训练或主动开启时请求授权；每次休息按绝对结束时间安排本地通知，前台支持横幅和声音。调整、跳过、删除训练会更新/取消提醒，关闭开关立即取消待发提醒。通知由独立服务管理，不依赖实时活动是否启用；手表和灵动岛操作会等待提醒安排完成。
- 点击卡片打开 `opengym://workout`。训练保存成功或删除草稿后，结束实时活动并清理待发休息提醒。保存失败时保留训练。

`WorkoutActivityRuntime` 让前台页面和后台 `LiveActivityIntent` 使用同一个账号隔离的 `GymStore`，冷启动也恢复本机草稿。按钮携带账号、训练 ID、草稿版本和目标组；重复完成不会取消勾选或误记下一组，修改/重排后的旧按钮会拒绝执行并更新显示。动作计时、未填完数据、同步或本机保存错误时禁用相应完成命令。

完成/下一动作命令的版本校验排除 `nativeRest`，避免调整或结束休息后、系统尚未重绘时误拒绝未变更的目标组；结束休息仍严格校验完整草稿版本，避免取消新计时。旧版实时活动载荷和手表命令保持原有校验。`LiveActivity` 日志记录 Intent 接收、命令接受结果及刷新耗时，不记录账号、训练内容或命令载荷。

工程最低版本仍为 iOS 17。新增 `OpenGymWidgets` 扩展（`me.itwl.opengym.widgets`），共享定义在 `Shared/LiveActivity/`；重建工程运行 `scripts/generate-project.rb`，现有工程可运行 `scripts/configure-live-activity.rb`。扩展无需共享账号凭据或额外 App Group。

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
