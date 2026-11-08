import type { Register } from 'claude-code'

const commitAndPushPrompt = `遵循项目规范，检查并验证当前仓库改动，仅提交本次任务相关且不含敏感信息的内容，按要求生成提交说明和归属信息，然后推送当前分支；不要创建或切换分支。优先沿用 upstream，远端不明确先询问。无改动不建空提交，但仍推送已有提交。不强推、不改写历史、不推送其他分支，失败即停止。报告提交哈希、分支和推送结果。`

const actions = [
  {
    key: 'commit-and-push',
    label: '提交代码',
    prompt: commitAndPushPrompt,
  },
  {
    key: 'internal-testflight',
    label: '内部TF打包',
    prompt: `${commitAndPushPrompt}

仅在确认当前分支已成功推送后，调用 apple-app-release skill 完成内部 TestFlight 构建与上传。提交或推送失败、技能不可用时立即停止。仅用于内部测试，不提交外部测试审核、App Store 审核或正式发布。参数遵循技能及项目规范，不明确先询问。报告版本号、构建号，以及构建、上传和 TestFlight 处理状态。`,
  },
] as const

export const register: Register = on => {
  // 只防止同一条指令尚未入队时重复点击，不保存或修改界面状态。
  const submitting = new Set<string>()

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    // 问卷占用这一区域时让出位置，其他模组已有的内容照常保留。
    const existing = await next(e)
    if (e.props.hasSurvey) return existing

    const { Box, Button } = $.ui.resolve(e)

    return (
      <Box flexDirection="column">
        {existing}
        <Box flexDirection="row" gap={1} flexWrap="wrap">
          {actions.map(action => (
            <Button
              key={action.key}
              label={action.label}
              onPress={async () => {
                if (submitting.has(action.key)) {
                  $.ui.toast('指令正在发送，请勿重复点击。')
                  return
                }

                submitting.add(action.key)
                try {
                  // 发送到当前会话，保留输入框草稿；忙碌时由引擎排队执行。
                  const result = await $.prompt.submit({
                    text: action.prompt,
                    asUser: true,
                  })
                  if (result.drop) $.ui.toast(`指令未发送：${result.drop}`)
                } catch {
                  $.ui.toast('指令发送失败，请稍后重试。')
                } finally {
                  submitting.delete(action.key)
                }
              }}
            />
          ))}
        </Box>
      </Box>
    )
  })
}
