# OpenGym iOS 项目快捷按钮

此模组维护在 `OpenGYM-iOS/skills/opengym-project-actions/`，只用于 OpenGym iOS 项目，不修改全局配置。支持模组界面扩展的 Claude Code 桌面端和终端会在输入框上方显示两个按钮。

- **提交代码**：检查改动、执行必要验证、生成提交说明，提交并推送当前分支；不创建或切换分支，不强推或改写历史。
- **内部TF打包**：复用提交指令，确认当前分支已成功推送后才调用全局 `apple-app-release` skill，执行内部 TestFlight 构建与上传。提交或推送失败、技能不可用时停止，不提交外部测试审核、App Store 审核或正式发布。

按钮只在点击时发送指令。加载模组不会自动提交、推送或打包；现有权限审批仍然生效。忙碌时指令由引擎排队执行，不覆盖输入框草稿。发布流程仍由全局技能维护，本项目不保存其副本。

## 项目级发现

本地配置仅在 iOS 项目目录使用一个符号链接：

- `OpenGYM-iOS/.claude/skills -> ../skills`。

仓库忽略 `.claude/` 目录，这个发现链接只保存在本机。重新克隆后，如对应路径尚不存在，可在 `OpenGYM-iOS` 目录创建：

```bash
mkdir -p .claude
```

```bash
ln -s ../skills .claude/skills
```

项目级发现会在新会话启动时读取目录；以 `OpenGYM-iOS` 为工作目录重新打开项目会话即可加载。若已有 `.claude/skills` 目录或链接，保留已有内容，仅将本模组接入该目录，不要覆盖。父目录不需要创建发现链接。

## 维护与验证

按钮文案和指令位于 `hooks/register.tsx`，测试位于 `tests/buttons.test.tsx`。在 `OpenGYM-iOS` 目录运行：

```bash
claude plugin validate skills/opengym-project-actions
```

```bash
claude plugin test skills/opengym-project-actions
```

引擎生成的 `.claude-plugin/types/` 仅供本机编辑器使用，不纳入版本控制。
