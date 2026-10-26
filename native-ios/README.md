# openGym Native iOS

openGym 的 SwiftUI 原生开发版本。仅在 `native-ios/` 内新增代码；沿用现有后端协议，不修改 Web、Android 或服务端。

## 运行

- iOS 17+；Xcode 15+（本次以 Xcode 27.1 / iPhone 17 Pro，iOS 26.5 验证）。
- 打开 `OpenGym.xcodeproj`，选择 `OpenGym` scheme 和 iPhone 模拟器，Run。
- 不需要 Swift Package、CocoaPods 或 Capacitor。模拟器使用本机服务 `http://localhost:8080`。
- 真机请填写可访问的 HTTPS 服务地址，选择自己的 Signing Team；`localhost` 在真机上指手机本身。
- 必须保留模拟器的 ad-hoc 签名和 `OpenGym.entitlements`；不要用 `CODE_SIGNING_ALLOWED=NO`，否则 Keychain 无法保存配对凭据。

```sh
xcodebuild -project OpenGym.xcodeproj -scheme OpenGym \
  -destination 'platform=iOS Simulator,id=<SIMULATOR-UDID>' \
  -derivedDataPath .build build
xcrun simctl install <SIMULATOR-UDID> .build/Build/Products/Debug-iphonesimulator/OpenGym.app
xcrun simctl launch <SIMULATOR-UDID> me.itwl.opengym
```

服务端用仓库现有 Docker Compose 启动。正常账号在网页中登录后，从「设置 → 账号 → 配对手机 App」取得一次性代码，在 iOS 设置中填写。凭据保存在 Keychain，绑定服务地址；应用不会读取 Docker 数据目录或服务端密钥。

## 本版功能

- 原生五页导航：首页、计划、训练、统计、动作库；黑色背景、绿色主色、圆角卡片参考 Web。
- 5,632 条原版动作：中文/英文搜索、身体部位/器械筛选、列表/网格、详情、中文动作步骤、Epley 估算。
- AVQueuePlayer + AVPlayerLooper 播放现有服务提供的 MP4，支持暂停/恢复、失败重试；图片和动画不重新生成。
- 账号配对、Keychain、登录续期、手动刷新、前台刷新、每 30 秒刷新。
- 计划编辑：名称、动作增删与排序、组数/次数/重量/休息时间和备注；支持热身、计时、有氧、分侧、金字塔、递减、Rest-pause、最后一组力竭和相邻动作超级组。
- 计划删除：进入计划编辑页，在底部点击「删除训练计划」并确认；同步清理每周与单日排期，循环跳过已删除计划，保留历史和正在进行的训练。删除失败时保留编辑页，可重试。
- 训练排期：每周一天可以安排多个计划；单日指定计划、休息或恢复每周安排。首页按网页规则显示队列和覆盖，可合并开始多个计划。
- 历史编辑：名称、备注、日期/开始时间、时长、普通组重量/次数/完成与热身状态、动作和组的增删；重新计算训练量、个人纪录及受修正影响的已追踪重量。支持继续加载较早的历史记录。
- 原生高级训练：逐组/逐侧记录，编辑递减重量和次数、Rest-pause 小组、RIR/RPE；超级组按轮切换和休息。计时支持暂停、恢复、提前完成，草稿和计时可跨重启恢复。
- 循环排期：编辑循环名称与顺序、移入移出计划、进度显示、重新开始一轮、切回固定周；保留外部队列的归属规则，完成一轮后按网页版规则自动续轮。
- 体重记录与折线图、真实训练历史、完成组数、12 周活动图。

## 协议

| 操作 | 现有接口 |
| --- | --- |
| 服务状态 | `GET /api/health` |
| 手机配对 | `POST /api/pair/redeem` |
| 账号/续期 | `GET /api/me` |
| 读取状态 | `GET /api/data` |
| 保存状态 | `PUT /api/data`，携带 `baseRev`、已有的 `baseWid` |
| 动作图片 | `/exercise-media/still/{id}.webp` |
| 动作动画 | `/exercise-media/clip/{id}.mp4` |

每次写入先读取最新完整 JSON，只更改对应记录，保留客户端不认识的字段。遇到 HTTP 409，重新读取后重放狭义、幂等的操作，最多尝试三次。训练使用稳定 UUID 去重。服务端负责同步时间戳，iOS 不伪造 `stamped:true`。不静默覆盖冲突，不自动改变网页的重量单位。

编辑使用原始值、本地修改和最新服务端值进行三方比较。未修改的字段保留远端的新值；同一字段冲突时阻止保存并保留表单。数组结构发生并发修改时也拒绝覆盖，避免旧动作顺序覆盖新动作或新训练组。取消编辑不会写入服务端。

动作目录没有单独的服务端 API；`scripts/build-catalogue.py` 从现有 `catalogue/exercises` 和 `catalogue/i18n/zh.json` 生成 App 内的 JSON。它只读取原仓库，输出到 `native-ios/OpenGym/Resources`。图片和视频仍由原服务提供。

## 复用的计算规则

所有页面为 SwiftUI，视频为 AVPlayer。排期解析、训练组生成、训练量、个人纪录、分侧聚合、超级组和循环流转，通过系统 JavaScriptCore 执行仓库已有纯函数，没有 WebView。`scripts/rules/entry.js` 与 `advanced.js` 只读导入原 Web 源码，esbuild 将其打包至本目录的 `OpenGym/Resources/web-rules.js`。生成文件已加入工程，日常 Xcode 构建不需要 Node。更新仓库后，在 `native-ios` 中执行 `npm ci && npm run build:rules` 重新生成，不会修改原 Web 文件。

## 当前边界

尚未实现 Web 的全部功能。暂不支持原生创建通行密钥、所有进阶策略的原生设置界面、后台训练提醒或所有数据类型的离线写入。开始训练调用网页的组生成和处方规则，沿用服务器保存的进阶配置。计时的到期结算在训练界面运行或返回时完成；后台不承诺声音或通知。原版配置和扩展字段在同步中保留。

训练草稿、历史编辑表单和账号缓存按「服务地址 + 账号」隔离保存。输入通过原子文件替换立即写入，并保留上一份可读副本；空白数字、未完成的小数和备注原文都保留在本机。冷启动可先恢复本机账号、训练和历史编辑，再尝试联网。本机写入失败会明确提示，提交前必须先成功落盘。卸载 App 或设备损坏不在本机文件恢复能力范围内。

历史编辑关闭后保留草稿；提交使用版本检查和三方合并，读取服务器确认后才归档本次草稿。断网、409、服务器已写入但响应丢失都保留待提交内容。统计页显示本机草稿／待同步标记，可重新提交。完成训练使用固定记录 ID 和固定结束时间重试，成功后保留本机归档。计划编辑仍使用在线保存。未配对时可以浏览动作，服务器写入需要有效账号。

训练与历史编辑一次显示一个动作，菜单显示序号、名称和完成状态。保存入口在右上角菜单；组间倒计时属于产生它的动作卡片，切换后计时继续。本次动作备注、计划备注及同一动作 ID 的上次训练分别显示，不跨健身房独立 ID 混合历史。计划排序按钮点击区域为至少 72 × 48 pt。

「设置 → Apple 健康」提供体重读取授权和同步开关。仅请求 bodyMass 读取权限，使用 anchored query、observer 和 background delivery；样本与查询位置先一起落盘，再同步到当前 openGym 账号。每天最后一次测量参与显示，支持 kg/lb 转换、重复同步去重、已确认的 HealthKit 删除和手动记录保护。关闭开关停止后续同步，保留已有数据；系统读取权限在健康 App 管理。iOS 不公开读取授权是否被拒绝，因此空结果不能显示为“已授权”或用于删除既有体重。HealthKit entitlement、后台交付 entitlement 与读取说明已加入工程，真机签名需支持这些能力。

2026-10-26：模拟器验证单动作切换、卡片内倒计时、菜单保存、历史编辑重启恢复与健康设置入口。自动化测试覆盖本机故障、断网、响应丢失、重复提交、并发修改及体重合并。真实 HealthKit 授权和后台唤醒尚需真机验证，模拟器不能证明后台交付效果。

## 验证与开发

```sh
xcodebuild -project OpenGym.xcodeproj -scheme OpenGym \
  -destination 'platform=iOS Simulator,id=<SIMULATOR-UDID>' \
  -derivedDataPath .build test
python3 scripts/build-catalogue.py
ruby scripts/generate-project.rb  # 需要 xcodeproj Ruby gem；生成的工程已随源码提供
```

`OpenGymTests` 验证动作目录完整性、服务地址限制、Web 兼容的训练格式、409 重试保留并发数据和未知字段、断网保存保留草稿，以及长时间离开后保存时不把等待时间算入训练。

编辑测试覆盖并发字段冲突、多计划和单日排期覆盖、个人纪录与训练量校正、已删除记录保护、旧记录标识和合并训练关联。上一阶段 13 项 XCTest 通过；模拟器实际验证了计划改名/改参数、每周多选、单日休息、历史修改与改期。真实服务端读回数据通过原版网页函数校验，详见 `artifacts/editing-api-verification.json`。

高级组型增量验证见 `OpenGymTests/AdvancedTests.swift`。模拟器已经通过界面完成包含计时、双侧递减、Rest-pause、金字塔和有氧的训练，并保存至现有接口。原版网页函数读回训练量为 1740，与原生端一致；继续完成循环 B 后，下一轮正确从 2026-10-24 开始。证据位于 `artifacts/advanced-verification.json`、`advanced-saved-workout.json` 和 `rotation-next-pass.png`。

本阶段最终 22 项 XCTest 全部通过。Mac 在高级配置表单最后的“完成 / 保存”点击前锁屏，此一条界面保存流程尚未最终补验；配置规则、训练记录保存及循环流转已分别通过测试和上述模拟器操作验证。

可选 `node scripts/simulator-account.mjs <SIMULATOR-UDID>` 通过现有 WebAuthn API 创建独立的「iOS 模拟器测试」账号，再用正式配对接口连接 Debug App。测试会创建一份有明显测试名称的计划；不操作真实健身账号。会在本目录生成已忽略的 `.test-session.json`（0600 权限），仅供本机测试，不要分享。此脚本不会修改服务配置或后端源码。

## 授权

本目录是 openGym 的非商业原生客户端开发分支，沿用项目的 AGPL v3.0 许可。动作文字和素材保留原作者与第三方声明，参见 `OpenGym/Resources/NOTICE.txt` 和 `LICENSE.txt`。素材仅在本 openGym 客户端中使用，保留原版分辨率，不打包或提取到独立产品。商用或独立产品不能据此获得 Gym visual 的素材授权。
