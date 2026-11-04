import { Component } from 'react'
import { useStore } from '../store/useStore.js'
import { t } from '../lib/i18n.js'
import Icon from './Icon.jsx'
import { Button } from './ui.jsx'

/**
 * Last line of defence: one bad render used to blank the whole app, with no way back —
 * a workout referencing an exercise the build doesn't know would white-screen and, since
 * the running workout is persisted, do it again on every reload.
 *
 * Sits inside #app so the tab bar stays usable; the shell keys this subtree on the route,
 * so switching tabs re-mounts it and clears the error by itself.
 */
export default class ErrorBoundary extends Component {
  constructor(props) { super(props); this.state = { failed: false } }
  static getDerivedStateFromError() { return { failed: true } }
  componentDidCatch(err) { console.error('openGym render error:', err) }

  render() {
    if (!this.state.failed) return this.props.children
    const active = useStore.getState().S.active
    return (
      <div className="narrow">
        <div className="empty" style={{ marginTop: '18vh' }}>
          <div className="ico"><Icon name="info" /></div>
          <div style={{ fontWeight: 600, marginBottom: 6 }}>{t("SOMETHING_WENT_WRONG" /* 出了点问题 */)}</div>
          {t("THIS_SCREEN_COULD_NOT_BE_DRAWN_YOUR_DATA_IS_SAFE_ON_THIS" /* 此页面无法显示。你的数据仍安全保存在本设备上。 */)}
        </div>
        <Button variant="primary" icon="reset" onClick={() => location.reload()}>{t("RELOAD_OPENGYM" /* 重新加载 openGym */)}</Button>
        {active && <>
          <div style={{ height: 8 }} />
          <Button variant="danger" icon="trash" onClick={() => {
            useStore.getState().update(s => { s.active = null })
            location.reload()
          }}>{t("DISCARD_THE_RUNNING_WORKOUT" /* 放弃进行中的训练 */)}</Button>
        </>}
      </div>
    )
  }
}
