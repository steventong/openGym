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
xcrun simctl launch <SIMULATOR-UDID> com.opengym.native.preview
```

服务端用仓库现有 Docker Compose 启动。正常账号在网页中登录后，从「设置 → 账号 → 配对手机 App」取得一次性代码，在 iOS 设置中填写。凭据保存在 Keychain，绑定服务地址；应用不会读取 Docker 数据目录或服务端密钥。

## 本版功能

- 原生五页导航：首页、计划、训练、统计、动作库；黑色背景、绿色主色、圆角卡片参考 Web。
- 5,632 条原版动作：中文/英文搜索、身体部位/器械筛选、列表/网格、详情、中文动作步骤、Epley 估算。
- AVQueuePlayer + AVPlayerLooper 播放现有服务提供的 MP4，支持暂停/恢复、失败重试；图片和动画不重新生成。
- 账号配对、Keychain、登录续期、手动刷新、前台刷新、每 30 秒刷新。
- 计划编辑：名称、动作增删与排序、普通组的组数/次数/重量/休息时间和备注；高级参数原样保留。
- 训练排期：每周一天可以安排多个计划；单日指定计划、休息或恢复每周安排。首页按网页规则显示队列和覆盖，可合并开始多个计划。
- 历史编辑：名称、备注、日期/开始时间、时长、普通组重量/次数/完成与热身状态、动作和组的增删；重新计算训练量、个人纪录及受修正影响的已追踪重量。支持继续加载较早的历史记录。
- 普通重量/次数组训练：记录每组、添加组、组间计时、草稿持久化、完成后同步。
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

所有页面为 SwiftUI，视频为 AVPlayer。排期解析、训练量和个人纪录校正通过系统 JavaScriptCore 执行仓库已有纯函数，没有 WebView。`scripts/rules/entry.js` 只读导入原 Web 源码，esbuild 将其打包至本目录的 `OpenGym/Resources/web-rules.js`。生成文件已加入工程，日常 Xcode 构建不需要 Node。更新仓库后，在 `native-ios` 中执行 `npm ci && npm run build:rules` 重新生成，不会修改原 Web 文件。

## 当前边界

尚未实现 Web 的全部功能。暂不支持原生创建通行密钥、自动进阶算法、复杂组型参数编辑（如计时、递减、金字塔、分侧）、循环排期编辑、Apple Health、通知或完整的离线数据同步。普通训练开始时使用计划的重量和次数；不运行网页的进阶引擎。现有高级字段在同步中保留，历史记录中的高级组仍可保留并参与网页原有的统计规则。

训练草稿按「服务地址 + 账号」隔离保存，保存失败时保留；当前冷启动需要成功验证账号后才能恢复草稿。未配对时可以浏览动作；计划、体重和训练写入需要账号。测试账号中出现的记录均为模拟器验证数据。

## 验证与开发

```sh
xcodebuild -project OpenGym.xcodeproj -scheme OpenGym \
  -destination 'platform=iOS Simulator,id=<SIMULATOR-UDID>' \
  -derivedDataPath .build test
python3 scripts/build-catalogue.py
ruby scripts/generate-project.rb  # 需要 xcodeproj Ruby gem；生成的工程已随源码提供
```

`OpenGymTests` 验证动作目录完整性、服务地址限制、Web 兼容的训练格式、409 重试保留并发数据和未知字段、断网保存保留草稿，以及长时间离开后保存时不把等待时间算入训练。

编辑测试覆盖并发字段冲突、多计划和单日排期覆盖、个人纪录与训练量校正、已删除记录保护、旧记录标识和合并训练关联。本次 13 项 XCTest 通过；模拟器实际验证了计划改名/改参数、每周多选、单日休息、历史修改与改期。真实服务端读回数据通过原版网页函数校验，详见 `artifacts/editing-api-verification.json`。

可选 `node scripts/simulator-account.mjs <SIMULATOR-UDID>` 通过现有 WebAuthn API 创建独立的「iOS 模拟器测试」账号，再用正式配对接口连接 Debug App。测试会创建一份有明显测试名称的计划；不操作真实健身账号。会在本目录生成已忽略的 `.test-session.json`（0600 权限），仅供本机测试，不要分享。此脚本不会修改服务配置或后端源码。

## 授权

本目录是 openGym 的非商业原生客户端开发分支，沿用项目的 AGPL v3.0 许可。动作文字和素材保留原作者与第三方声明，参见 `OpenGym/Resources/NOTICE.txt` 和 `LICENSE.txt`。素材仅在本 openGym 客户端中使用，保留原版分辨率，不打包或提取到独立产品。商用或独立产品不能据此获得 Gym visual 的素材授权。
