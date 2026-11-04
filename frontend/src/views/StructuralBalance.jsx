import { useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { useStore } from '../store/useStore.js'
import { exOr } from '../lib/exercises.js'
import { t, exerciseNameFor, exerciseNameClass , translateValue } from '../lib/i18n.js'
import Icon from '../components/Icon.jsx'
import { Button, Segmented } from '../components/ui.jsx'
import { exercisePicker, bwSheet } from '../sheets.jsx'
import { computeBalance, overrideKey, withOverride } from '../lib/structuralBalance.js'
import { balanceStatusView } from '../lib/structuralBalance-view.js'
import { TEMPLATES, TEMPLATE_LIST, DEFAULT_TEMPLATE_ID, EVALUATION_MODES } from '../lib/structuralBalanceTemplates.js'

const STATUS_COLOR = {
  balanced: 'var(--green)',
  borderline: 'var(--yellow)',
  weak: 'var(--red)',
  'no-data': 'var(--label-3)',
}

// A role pointed at a custom exercise since deleted (on this device or another) still names
// something rather than showing a blank line.
const exerciseName = id => (id ? exerciseNameFor(exOr(id)) : null)

export default function StructuralBalance() {
  const nav = useNavigate()
  const S = useStore(s => s.S)
  const update = useStore(s => s.update)
  // Own keys only: a synced or imported id such as "constructor" would otherwise find an
  // Object.prototype member and take the screen down.
  const templateId = Object.prototype.hasOwnProperty.call(TEMPLATES, S.balanceTemplate) ? S.balanceTemplate : DEFAULT_TEMPLATE_ID
  const template = TEMPLATES[templateId]
  const results = useMemo(() => computeBalance(S, template), [S, template])

  const setOverride = (role, exId) => update(s => {
    s.balanceOverrides = withOverride(s.balanceOverrides, overrideKey(template, role), exId)
  })
  const clearOverride = role => setOverride(role, null)
  // Headed by what a pick does here, like the routine editor's Replace (#110): the picker's own
  // heading is "Add exercise".
  const changeExercise = role => {
    const picker = exercisePicker(ex => { setOverride(role, ex.id); picker.close() }, { title: t("SWAP_EXERCISE" /* 更换动作 */) })
  }

  return <>
    <div className="hdr"><button className="iconbtn" onClick={() => nav('/stats')} aria-label={t("STATS" /* 统计 */)}><Icon name="chevronLeft" /></button>
      <div style={{ flex: 1, marginInlineStart: 12 }}><h1>{t("STRUCTURAL_BALANCE" /* 结构平衡 */)}</h1>
        <div className="sub">{t("COMPARE_YOUR_LIFTS_AGAINST_A_PUBLISHED_RATIO_TABLE_TO_FIND_THE_WEAK" /* 将你的动作成绩与已发布的比例表对比，找出最薄弱的环节。 */)}</div></div></div>

    <Segmented className="seg-range" value={templateId}
      onChange={id => update(s => { s.balanceTemplate = id })}
      options={TEMPLATE_LIST.map(tpl => ({ value: tpl.id, label: translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(tpl.label) }))} />

    <div className="card">
      {results.map(r => {
        const role = template.roles.find(role => role.id === r.roleId)
        const view = balanceStatusView(r.status, r.needsAnchor)
        // The exercise the number came from when there is one, otherwise the one this role is
        // set to — a role you just pointed at an exercise should name it, logged or not.
        const exId = r.mappedExerciseId || r.configuredExerciseId
        const name = exerciseName(exId)
        const reps = role.evaluationMode === EVALUATION_MODES.REP_COUNT
        const actual = r.status === 'no-data' ? '–' : reps ? r.current.r : `${Math.round(r.actualPct)}%`
        const valueText = `${actual} / ${r.targetPct}${reps ? '' : '%'}`
        return (
          <div key={r.roleId} className="mrow" data-role-id={r.roleId} data-status={r.status}
            style={{ flexDirection: 'column', alignItems: 'stretch', gap: 6, paddingBlock: 10 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
              {/* `.mrow .nm` keeps to one line, and its ellipsis never reaches these block lines:
                  a label is cut off mid-word instead, and what goes is its reps and "each hand" —
                  what the standard asks for. So here the name wraps. */}
              <span className="nm" style={{ minWidth: 0, whiteSpace: 'normal', overflowWrap: 'anywhere' }}>
                <span style={{ display: 'block' }}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(role.label)}</span>
                <span className="small dim" style={{ display: 'block' }}>
                  <span className={exId ? exerciseNameClass(exOr(exId)) : ''} data-exercise-name>{name}</span>{r.isOverridden ? ` · ${t("CUSTOM_A" /* 自定义 */)}` : ''}
                </span>
                {r.needsBodyweight && <span className="small" data-needs-bodyweight style={{ display: 'block', color: 'var(--label-2)' }}>
                  {t("LOG_YOUR_BODY_WEIGHT_TO_SCORE_THIS_LIFT" /* 记录你的体重以评估这个动作。 */)}
                </span>}
                {r.needsAnchor && <span className="small" data-needs-anchor style={{ display: 'block', color: 'var(--label-2)' }}>
                  {t("LOG_THE_ANCHOR_LIFT_TO_SCORE_THIS_ONE" /* 记录锚点动作以评估这个动作。 */)}
                </span>}
              </span>
              <span className="v" style={{ textAlign: 'end', flexShrink: 0 }}>
                <span style={{ color: STATUS_COLOR[r.status] }}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(view.label)}</span>
                <span className="dim small" style={{ display: 'block' }}>{valueText}</span>
              </span>
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {r.needsBodyweight && <Button size="sm" variant="ghost" icon="plus" onClick={() => bwSheet()}>{t("LOG_BODY_WEIGHT" /* 记录体重 */)}</Button>}
              <Button size="sm" variant="ghost" icon="pencil" onClick={() => changeExercise(role)}>{t("SWAP_EXERCISE" /* 更换动作 */)}</Button>
              {r.isOverridden && <Button size="sm" variant="ghost" onClick={() => clearOverride(role)}>{t("USE_DEFAULT_EXERCISE" /* 使用默认动作 */)}</Button>}
            </div>
          </div>
        )
      })}
    </div>
  </>
}
