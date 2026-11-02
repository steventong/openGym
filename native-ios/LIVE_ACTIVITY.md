# 训练实时活动

开始训练后，App 通过 ActivityKit 启动一条实时活动。灵动岛紧凑区显示动作名与组数（休息时显示倒计时），展开区和锁屏卡片显示训练名称、动作、当前组、重量/次数与操作。

- **完成本组**：调用与 Apple Watch 相同的完成命令，沿用训练草稿的组型、左右侧、休息和保存逻辑。动作最后一组按现有规则不启动休息，显示“下一个动作”；全部完成后回 App 保存训练。
- **结束休息**：清除当前休息计时。即使系统延迟刷新过期状态，“完成本组”仍可操作；倒计时到零不会倒数成负数。
- **休息提醒**：第一次在前台训练时请求系统通知权限；按绝对结束时间安排本地通知。调整、跳过、删除训练会更新/取消提醒；系统通知权限与实时活动权限相互独立。
- 点击卡片打开 `opengym://workout`。训练保存成功或删除草稿后，结束实时活动并清理待发休息提醒。保存失败时保留训练。

`WorkoutActivityRuntime` 让前台页面和后台 `LiveActivityIntent` 使用同一个账号隔离的 `GymStore`，冷启动也恢复本机草稿。按钮携带账号、训练 ID、草稿版本和目标组；重复完成不会取消勾选或误记下一组，修改/重排后的旧按钮会拒绝执行并更新显示。动作计时、未填完数据、同步或本机保存错误时禁用相应完成命令。

工程最低版本仍为 iOS 17。新增 `OpenGymWidgets` 扩展（`me.itwl.opengym.widgets`），共享定义在 `Shared/LiveActivity/`；重建工程运行 `scripts/generate-project.rb`，现有工程可运行 `scripts/configure-live-activity.rb`。扩展无需共享账号凭据或额外 App Group。

实现参考：[Apple Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)、[Apple 交互式实时活动](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)。按钮交互由系统按锁屏认证状态处理；专注模式、静音与通知设置可能影响声音和横幅。

## 验证（2026-11-02）

- iPhone 18 Pro / iOS 27.0 模拟器：应用和扩展编译通过；全套 XCTest 138 项通过，其中新增 `WorkoutActivityTests` 10 项。
- 虚构账号 `live-activity-qa`、回环服务 `localhost:19387`：开始训练显示紧凑/展开灵动岛；在桌面直接完成第一组后，本机草稿仅第一组变为完成，启动 15 秒休息；系统日志确认“休息结束”横幅送达。
- 已在 Device Hub 实际检查最终双按钮布局与锁屏卡片。iOS 27 模拟器的 `simctl` 截图未包含系统渲染的实时活动，视觉验收以 Device Hub 画面为准。
- 锁屏点击“结束休息”后读回确认计时已清除、完成组数不变；点击卡片返回当前训练。验收结束后通过 App 删除虚构训练，检查实时活动清理。
- 临时验收资料在忽略目录 `artifacts/live-activity/`。未发布 TestFlight，真机锁屏认证、声音及长期后台行为仍需真机验收。
