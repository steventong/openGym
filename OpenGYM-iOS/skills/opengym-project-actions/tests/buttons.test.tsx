import { expect, test } from 'claude-code/testing'

const BAND = {
  plugin: 'project-actions',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 10,
    bodyColumns: 80,
    scroll: { offset: 0, bodyRows: 10 },
    view: {},
  },
} as const

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: 两个按钮保留原有内容，点击后只发送对应指令`, async ($, on) => {
    const submitted: string[] = []
    on('ui.render', ($, e) => {
      const { Text } = $.ui.resolve(e)
      return <Text>原有内容</Text>
    })
    on('prompt.submit', (_, e) => {
      submitted.push(e.text)
      expect(e.origin.kind).toBe('plugin')
      if (e.origin.kind === 'plugin') expect(e.origin.asUser).toBe(true)
      return { text: e.text, origin: e.origin }
    })

    const ui = await $.ui.mount({ ...BAND, surface })
    expect((await ui.find({ key: 'commit-and-push' }))?.text).toBe('提交代码')
    expect((await ui.find({ key: 'internal-testflight' }))?.text).toBe('内部TF打包')
    expect((await ui.find({ type: 'Text', text: /原有内容/ }))?.text).toBe('原有内容')
    expect(submitted).toHaveLength(0)

    await ui.press({ key: 'commit-and-push' })
    expect(submitted).toHaveLength(1)
    expect(submitted[0]).toContain('然后推送当前分支；不要创建或切换分支')
    expect(submitted[0]).toContain('不强推、不改写历史、不推送其他分支，失败即停止')

    await ui.press({ key: 'internal-testflight' })
    expect(submitted).toHaveLength(2)
    expect(submitted[1]!.startsWith(`${submitted[0]}\n\n`)).toBe(true)
    expect(submitted[1]).toContain('仅在确认当前分支已成功推送后')
    expect(submitted[1]).toContain('apple-app-release')
    expect(submitted[1]).toContain('提交或推送失败、技能不可用时立即停止')
    expect(submitted[1]).toContain('不提交外部测试审核、App Store 审核或正式发布')
    expect(submitted[1]).toContain('构建、上传和 TestFlight 处理状态')
    await ui.unmount()
  })

  test(`${surface}: 问卷占用时不覆盖问卷`, async ($, on) => {
    on('ui.render', ($, e) => {
      const { Text } = $.ui.resolve(e)
      return <Text>问卷内容</Text>
    })
    const ui = await $.ui.mount({
      ...BAND,
      surface,
      props: { ...BAND.props, hasSurvey: true },
    })
    expect(await ui.find({ key: 'commit-and-push' })).toBeUndefined()
    expect(await ui.find({ key: 'internal-testflight' })).toBeUndefined()
    expect((await ui.find({ type: 'Text' }))?.text).toBe('问卷内容')
    await ui.unmount()
  })
}
