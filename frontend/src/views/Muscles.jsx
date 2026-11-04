import { useNavigate } from 'react-router-dom'
import { t } from '../lib/i18n.js'
import MuscleExplorer from '../components/MuscleExplorer.jsx'
import { exerciseDetailSheet, addToRoutineSheet } from '../sheets.jsx'
import Icon from '../components/Icon.jsx'

export default function Muscles() {
  const nav = useNavigate()
  return <>
    <div className="hdr"><button className="iconbtn" onClick={() => nav('/library')} aria-label={t("EXERCISES" /* 动作库 */)}><Icon name="chevronLeft" /></button>
      <div style={{ flex: 1, marginInlineStart: 12 }}><h1>{t("EXPLORE_MUSCLES" /* 探索肌肉 */)}</h1><div className="sub">{t("CHOOSE_A_MUSCLE_TO_SEE_EXERCISES_THAT_TRAIN_IT" /* 选择肌群，查看对应的训练动作。 */)}</div></div></div>

    <MuscleExplorer onDetail={exerciseDetailSheet} onPlan={addToRoutineSheet} />
  </>
}
