import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import {
  MEASUREMENT_FIELDS, MEASUREMENT_KEYS, emptyMeasurement, enabledMeasurementFields,
  fromMeasurementDisplay, latestMeasurement, measurementEntryHasValues,
  measurementSeries, measurementUnit, measurementValue, normalizeMeasurementEntry,
  toMeasurementDisplay, normalizeMeasurementsState,
} from '../lib/measurements.js'
import { fmtDate, fmtNum, todayISO, uid } from '../lib/format.js'
import { t , translateValue } from '../lib/i18n.js'
import LineChart from '../components/LineChart.jsx'
import Icon from '../components/Icon.jsx'
import { Button, NumberField, Section, Segmented, SelectRow, Switch, TextField } from '../components/ui.jsx'
import { confirmSheet } from '../sheets.jsx'

// Every write leaves the list in its one-entry-per-day shape (normalizeMeasurementsState).
const update = (fn, ...rest) => useStore.getState().update(s => { fn(s); normalizeMeasurementsState(s) }, ...rest)
const toast = message => useUI.getState().toast(message)

const fieldUnit = (field, profileUnit) => field.key === 'bodyFat' ? '%' : measurementUnit(profileUnit)
const shownValue = (entry, field, profileUnit) => {
  const value = measurementValue(entry, field.key)
  if (value == null) return null
  return field.key === 'bodyFat' ? value : toMeasurementDisplay(value, profileUnit)
}

function MeasurementLog({ sourceDate, close }) {
  const S = useStore(s => s.S)
  const source = sourceDate ? S.measurements.find(e => e.d === sourceDate) : null
  const enabled = enabledMeasurementFields(S)
  const fields = [...enabled]
  // Editing must expose populated fields even if the user disabled them after logging.
  if (source) {
    for (const f of MEASUREMENT_FIELDS) {
      if (source[f.key] != null && !fields.some(x => x.key === f.key)) fields.push(f)
    }
    for (const o of source.other || []) {
      if (o.value != null && !fields.some(x => x.key === 'other:' + o.id)) {
        fields.push({ key: 'other:' + o.id, label: o.name, custom: true, group: 'Other' })
      }
    }
  }
  const [date, setDate] = useState(source?.d || todayISO())
  const [values, setValues] = useState(() => Object.fromEntries(fields.map(f => [f.key, shownValue(source, f, S.unit)])))

  const save = () => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || date > todayISO()) { toast(t("CHOOSE_A_VALID_DATE" /* 请选择有效日期 */)); return }
    if (date !== sourceDate && S.measurements.some(e => e.d === date)) {
      toast(t("THAT_DATE_ALREADY_HAS_MEASUREMENTS_EDIT_IT_INSTEAD" /* 该日期已有测量——请直接编辑。 */)); return
    }
    const base = source ? normalizeMeasurementEntry(source, S.customMeasurements) : emptyMeasurement(date, S.customMeasurements)
    base.d = date
    base.t = source && date === source.d ? source.t : (date === todayISO() ? Date.now() : new Date(date + 'T12:00:00').getTime())
    for (const field of fields) {
      const raw = values[field.key]
      const value = raw == null || raw === 0 ? null : Math.round(+raw * 10) / 10
      if (field.key === 'bodyFat' && value > 100) { toast(t("BODY_FAT_MUST_BE_BETWEEN_ZERO_AND_ONEZEROZERO" /* 体脂率必须在 0% 到 100% 之间。 */)); return }
      if (field.custom) {
        const item = base.other.find(o => o.id === field.key.slice(6))
        if (item) item.value = value == null ? null : fromMeasurementDisplay(value, S.unit)
      } else if (field.key === 'bodyFat') base.bodyFat = value
      else base[field.key] = value == null ? null : fromMeasurementDisplay(value, S.unit)
    }
    if (!measurementEntryHasValues(base)) { toast(t("ENTER_AT_LEAST_ONE_MEASUREMENT" /* 请至少输入一项测量 */)); return }
    // `t` is when the check-in was last saved: the newer one of a day wins a sync merge, the
    // way a weigh-in's does. The chart places it by its date, not by this.
    base.t = Date.now()
    update(state => {
      if (sourceDate) state.measurements = state.measurements.filter(e => e.d !== sourceDate)
      state.measurements.push(base)
    })
    close()
    toast(t("MEASUREMENTS_SAVED" /* 已保存测量 */))
  }

  return <>
    <h3>{source ? t("EDIT_MEASUREMENTS" /* 编辑测量 */) : t("LOG_MEASUREMENTS" /* 记录测量 */)}</h3>
    <div className="muted small" style={{ marginBottom: 12 }}>{t("FILL_ONLY_WHAT_YOU_MEASURED_TODAY_EMPTY_FIELDS_STAY_EMPTY" /* 只填今天量过的部位，留空的字段保持为空。 */)}</div>
    <label className="measure-date">
      <span>{t("DATE" /* 日期 */)}</span>
      <input className="field" type="date" value={date} max={todayISO()} onChange={e => setDate(e.target.value)} />
    </label>
    {fields.length ? <div className="measure-form">
      {fields.map(field => <label className="measure-field" key={field.key}>
        <span>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(field.label)}</span>
        <span className="measure-input">
          <NumberField nullable value={values[field.key]} onChange={value => setValues(v => ({ ...v, [field.key]: value }))} />
          <i>{fieldUnit(field, S.unit)}</i>
        </span>
      </label>)}
    </div> : <div className="empty small">{t("CHOOSE_AT_LEAST_ONE_MEASUREMENT_FIRST" /* 请先选择至少一个测量项。 */)}</div>}
    <div style={{ height: 14 }} />
    <Button variant="primary" onClick={save} disabled={!fields.length}>{t("SAVE" /* 保存 */)}</Button>
    <div style={{ height: 8 }} />
    <Button variant="ghost" className="dim" onClick={close}>{t("CANCEL" /* 取消 */)}</Button>
  </>
}

export function measurementLogSheet(sourceDate = null) {
  return useUI.getState().openSheet(close => <MeasurementLog sourceDate={sourceDate} close={close} />)
}

function ManageMeasurements({ close }) {
  const S = useStore(s => s.S)
  const [name, setName] = useState('')
  const groups = [...new Set(MEASUREMENT_FIELDS.map(f => f.group))]
  const toggleBuiltin = (key, on) => update(state => {
    const set = new Set(state.measurementEnabled || [])
    if (on) set.add(key); else set.delete(key)
    state.measurementEnabled = [...set]
  })
  const toggleCustom = (id, on) => update(state => {
    const item = state.customMeasurements.find(c => c.id === id)
    if (item) item.enabled = on
  })
  const add = () => {
    const clean = name.trim()
    if (!clean) return
    if (S.customMeasurements.some(c => c.name.toLowerCase() === clean.toLowerCase()) ||
      MEASUREMENT_FIELDS.some(f => f.label.toLowerCase() === clean.toLowerCase())) {
      toast(t("A_CUSTOM_MEASUREMENT_WITH_THAT_NAME_ALREADY_EXISTS" /* 已有同名的自定义测量项。 */)); return
    }
    update(state => { state.customMeasurements.push({ id: uid(), name: clean.slice(0, 60), enabled: true }) })
    setName('')
  }
  return <>
    <h3>{t("CHOOSE_MEASUREMENTS" /* 选择测量项 */)}</h3>
    <div className="muted small" style={{ marginBottom: 12 }}>{t("KEEP_THE_LOGGING_FORM_FOCUSED_ON_THE_MEASUREMENTS_YOU_ACTUALLY_TRACK" /* 让表单只保留你真正跟踪的测量项。 */)}</div>
    {groups.map(group => <Section title={translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(group)} key={group} className="measure-options">
      {MEASUREMENT_FIELDS.filter(f => f.group === group).map(field => <div className="lrow" key={field.key}>
        <span className="lrow-m"><span className="lrow-t">{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(field.label)}</span></span>
        <Switch checked={(S.measurementEnabled || []).includes(field.key)} onChange={on => toggleBuiltin(field.key, on)} />
      </div>)}
      {group === 'Other' && S.customMeasurements.map(field => <div className="lrow" key={field.id}>
        <span className="lrow-m"><span className="lrow-t">{field.name}</span><span className="lrow-s">{t("CUSTOM_A" /* 自定义 */)}</span></span>
        <Switch checked={field.enabled !== false} onChange={on => toggleCustom(field.id, on)} />
      </div>)}
    </Section>)}
    <div className="row" style={{ gap: 8, alignItems: 'stretch' }}>
      <TextField value={name} maxLength={60} placeholder={t("CUSTOM_MEASUREMENT" /* 自定义测量项 */)} onChange={e => setName(e.target.value)} onKeyDown={e => { if (e.key === 'Enter') add() }} />
      <Button icon="plus" onClick={add} disabled={!name.trim()}>{t("ADD" /* 添加 */)}</Button>
    </div>
    <div style={{ height: 14 }} />
    <Button variant="primary" onClick={close}>{t("DONE" /* 完成 */)}</Button>
  </>
}

export function manageMeasurementsSheet() {
  return useUI.getState().openSheet(close => <ManageMeasurements close={close} />)
}

export default function Measurements() {
  const nav = useNavigate()
  const S = useStore(s => s.S)
  const [range, setRange] = useState(90)
  const available = useMemo(() => {
    const out = enabledMeasurementFields(S)
    for (const field of MEASUREMENT_FIELDS) {
      if (latestMeasurement(S, field.key) && !out.some(f => f.key === field.key)) out.push(field)
    }
    for (const custom of S.customMeasurements || []) {
      const key = 'other:' + custom.id
      if (latestMeasurement(S, key) && !out.some(f => f.key === key)) out.push({ key, label: custom.name, custom: true, group: 'Other' })
    }
    return out
  }, [S])
  const fallback = available.find(f => f.key === 'waist')?.key || available[0]?.key || null
  const [selected, setSelected] = useState(fallback)
  const key = available.some(f => f.key === selected) ? selected : fallback
  const field = available.find(f => f.key === key)
  const points = key ? measurementSeries(S, key, range) : []
  const unit = key === 'bodyFat' ? '%' : measurementUnit(S.unit)
  const all = key ? measurementSeries(S, key) : []
  const latest = all.at(-1)
  const previous = all.at(-2)
  const delta = latest && previous ? Math.round((latest.y - previous.y) * 10) / 10 : null
  const recent = [...S.measurements].reverse()

  const remove = entry => confirmSheet({
    title: t("DELETE_MEASUREMENTS" /* 删除这次测量？ */),
    message: t("DELETES_THE_MEASUREMENTS_LOGGED_ON_COUNT" /* 删除 {0} 记录的测量。 */, fmtDate(entry.d, true)),
    confirmText: t("DELETE" /* 删除 */), danger: true,
    onConfirm: () => { update(state => { state.measurements = state.measurements.filter(e => e.d !== entry.d) }); toast(t("MEASUREMENTS_DELETED" /* 已删除测量 */)) },
  })

  return <div className="narrow">
    <div className="hdr">
      <button className="iconbtn" onClick={() => nav('/home')} aria-label={t("HOME" /* 首页 */)}><Icon name="chevronLeft" /></button>
      <div style={{ flex: 1, marginLeft: 10 }}><h1>{t("BODY_MEASUREMENTS" /* 身体围度 */)}</h1><div className="sub">{t("CIRCUMFERENCE_COMPOSITION" /* 围度与体成分 */)}</div></div>
      <button className="iconbtn" onClick={manageMeasurementsSheet} aria-label={t("CHOOSE_MEASUREMENTS" /* 选择测量项 */)}><Icon name="gear" /></button>
    </div>

    <div className="card">
      <div className="row between" style={{ marginBottom: 10 }}>
        <div>
          <div className="muted small">{field ? translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(field.label) : t("BODY_MEASUREMENTS" /* 身体围度 */)}</div>
          <div className="big" style={{ marginTop: 3 }}>{latest ? <>{fmtNum(latest.y)} <span className="muted" style={{ fontSize: '1rem' }}>{unit}</span></> : '–'}</div>
          {delta != null && delta !== 0 && <div className="small" style={{ marginTop: 3, color: 'var(--label-2)' }}>{delta > 0 ? '+' : ''}{fmtNum(delta)} {unit} {t("SINCE_PREVIOUS" /* 较上次 */)}</div>}
        </div>
        <Button size="sm" icon="plus" onClick={() => measurementLogSheet()}>{t("LOG" /* 记录 */)}</Button>
      </div>
      {available.length > 0 && <div className="sect-b measure-select"><SelectRow
        title={t("MEASUREMENT" /* 测量项 */)} sheetTitle={t("CHOOSE_MEASUREMENT" /* 选择测量项 */)} value={key} onChange={setSelected}
        options={available.map(f => ({ value: f.key, label: translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(f.label) }))} />
      </div>}
      <Segmented className="seg-range" value={range} onChange={setRange}
        options={[{ value: 30, label: '1M' }, { value: 90, label: '3M' }, { value: 365, label: '1Y' }, { value: 0, label: t("ALL" /* 全部 */) }]} />
      <div className="chart"><LineChart points={points} h={170} unit={unit} color="var(--teal)" /></div>
    </div>

    {!available.length && <div className="card">
      <div className="muted small">{t("CHOOSE_THE_MEASUREMENTS_YOU_WANT_TO_TRACK_THEN_LOG_YOUR_FIRST_CHECK" /* 选择你想跟踪的测量项，然后记录第一次测量。 */)}</div>
      <div style={{ height: 10 }} /><Button onClick={manageMeasurementsSheet}>{t("CHOOSE_MEASUREMENTS" /* 选择测量项 */)}</Button>
    </div>}

    <div className="row between" style={{ margin: '18px 2px 10px' }}>
      <h4 className="sec" style={{ margin: 0 }}>{t("MEASUREMENT_HISTORY" /* 测量历史 */)}</h4>
      <Button size="sm" variant="ghost" icon="gear" onClick={manageMeasurementsSheet}>{t("FIELDS" /* 字段 */)}</Button>
    </div>
    {recent.length ? <div className="list">{recent.map(entry => {
      const count = MEASUREMENT_KEYS.filter(k => entry[k] != null).length + (entry.other || []).filter(o => o.value != null).length
      const previewFields = enabledMeasurementFields(S).map(f => ({ field: f, value: shownValue(entry, f, S.unit) })).filter(x => x.value != null).slice(0, 3)
      return <div className="card measure-history" key={entry.d}>
        <div className="row between">
          <div><b>{fmtDate(entry.d, true)}</b><div className="small dim" style={{ marginTop: 2 }}>{t(count === 1 ? "COUNT_MEASUREMENT" /* {0} 项测量 */ : "COUNT_MEASUREMENTS" /* {0} 项测量 */, count)}</div></div>
          <div className="row" style={{ gap: 4 }}>
            <button className="iconbtn" onClick={() => measurementLogSheet(entry.d)} aria-label={t("EDIT" /* 编辑 */)}><Icon name="pencil" /></button>
            <button className="iconbtn" style={{ color: 'var(--red)' }} onClick={() => remove(entry)} aria-label={t("DELETE" /* 删除 */)}><Icon name="trash" /></button>
          </div>
        </div>
        {previewFields.length > 0 && <div className="measure-preview">{previewFields.map(({ field: f, value }) => <span key={f.key}>{translateValue /* 动态标签：保留原始数据值，只翻译显示文字 */(f.label)} <b>{fmtNum(value)} {fieldUnit(f, S.unit)}</b></span>)}</div>}
      </div>
    })}</div> : <div className="empty small">{t("NO_MEASUREMENTS_YET" /* 还没有测量 */)}</div>}
  </div>
}
