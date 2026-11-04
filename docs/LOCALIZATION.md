# 跨端文案规范

跨端文案编辑源位于仓库根目录 `localization/en.json` 和 `localization/zh.json`。两份文件必须包含完全相同的 key。原有其他语言也迁入同目录 JSON，继续保留。

覆盖客户端包括 Web、Android/Capacitor、iPhone/iPad、Apple Watch、实时活动，以及管理后台、教练设置、推送通知、健康授权说明和原生训练规则的校验提示。应用主页、计划、训练、统计、动作库及其编辑、弹窗、空状态、无障碍说明均通过此体系读取。

## Apple 标准资源

SwiftUI、Watch 和 Widget 使用 `native-ios/Localization/Localizable.xcstrings`，可直接在 Xcode String Catalog 编辑器中查看中英文和中文注释。iPhone 与 Watch 的权限说明分别放在各自的 `InfoPlist.xcstrings`。

共享 JSON 在构建前转换为标准 String Catalog，Xcode 编译生成系统本地化资源。Apple App 包不再包含 `en.json` / `zh.json`；`L10n` 仅保留账号语言选择和 Foundation API 的薄封装，使用 `String(localized:bundle:locale:)` 查询、`String(format:locale:arguments:)` 格式化。没有自定义 JSON 读取器或占位符解析器。

JSON 的 `{0}`、`{1}` 转换为标准 `%1$@`、`%2$@`，支持译文调整语序。需要文字百分号时，生成器按标准格式转义。跨端修改仍编辑共享 JSON 并重新生成，避免原生与网页产生两套文案。

## Key 与引用

- key 只使用大写英文字母和下划线，例如 `REST_COMPLETE`、`MEASUREMENT_CHEST`。
- 引用处附中文注释，描述文案含义；不要把中文正文写进组件。
- 一句话使用一个模板，通过 `{0}`、`{1}` 传入变量，避免拼接语言片段。
- 用户填写的计划名、动作名、备注、聊天内容不做自动翻译。动作目录继续按稳定的动作 ID 管理双语名称和教学步骤；ID、接口字段、枚举值不属于翻译 key。
- 同一含义复用 key；不同语境分别命名，即便英文相同。例如 `CHEST_A` 表示胸部，`MEASUREMENT_CHEST` 表示胸围。

```js
t('REST_COMPLETE' /* 休息结束 */)
t('SET_COUNT_OF_COUNT' /* 第几组，共几组 */, current, total)
```

```swift
L10n.text("REST_COMPLETE" /* 休息结束 */)
L10n.text("SET_COUNT_OF_COUNT" /* 第几组，共几组 */, current, total)
```

`translateValue` 仅适配目录、旧数据和服务端返回的已有标签。兼容映射位于 `localization/metadata/`，新界面文案应直接使用大写 key。`frontend/src/locales/*.js` 仅保留旧工具与测试所需的适配导出，实际翻译在 JSON 中。

## 语言与术语

原生端在“设置 → 训练偏好与单位”选择中文或英文，保存到账号 `lang`，和网页使用相同偏好。无偏好时跟随设备语言。手表收到快照时同步语言；实时活动使用快照携带的语言。中文显示中文动作名及英文副标题，英文显示英文名称，动作步骤随之切换；自定义内容保留原文。教练的新请求携带所选语言，已保存的聊天和建议正文不被重写。

统一术语：训练计划（routine）、训练（workout）、工作组、热身组、递减组（drop set）、减重组（Back-off）、休息暂停组（rest-pause）、训练量、估算 1RM。RIR、RPE 保留通用缩写，解释使用中文。身体部位与围度指标分开处理。

## 生成与检查

首次安装依赖：

```sh
npm ci --prefix frontend
npm ci --prefix native-ios
```

修改 JSON 或共享规则后运行：

```sh
npm run generate:localization
npm run check:localization
```

生成命令更新 Apple `InfoPlist.xcstrings` / `Localizable.xcstrings`、Android `localization.xml`、服务端推送文案和原生 JavaScript 规则包。不要手工维护这些生成结果。Apple、Android 系统资源必须遵循平台规定的资源命名；其文案仍来自大写 JSON key。

检查覆盖 key 格式、双语完整性、非空值、占位符、引用处中文注释、JSX 硬编码、原生中文硬编码，以及生成资源是否与 JSON 一致。前端构建和 CI 都会执行检查。检查不能替代语言审校或小屏幕视觉验收。

验证可使用 `TZ=UTC npm test --prefix frontend`，避免已有日期夹具依赖执行机器时区。原生现有测试用中文运行，`LocalizationTests` 另验证中英文切换、语境区分、变量替换、动作名称/步骤和旧手表快照兼容性。
