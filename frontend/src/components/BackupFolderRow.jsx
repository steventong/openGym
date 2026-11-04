import { useEffect, useState } from 'react'
import { t } from '../lib/i18n.js'
import { backupFolder, chooseBackupFolder, resetBackupFolder, onBackupFolderChange } from '../lib/mobile.js'
import { useUI } from '../store/useUI.js'
import { Row } from './ui.jsx'

const DEFAULT_FOLDER = 'Documents/openGym'

/* Where auto-backup puts its copies on this Android phone (#161): Documents/openGym, or a folder
   chosen with the system picker — a sync app's, an SD card's. The choice is this phone's alone
   (lib/mobile.js), so it is read here and not from the synced state. When the chosen folder
   stops taking copies they go to Documents/openGym again, and this says so until the folder is
   chosen again or the default is confirmed. */
export function useBackupFolder(enabled = true) {
  const [folder, setFolder] = useState(null)
  useEffect(() => {
    if (!enabled) return undefined
    let live = true
    let off = () => {}
    try {
      backupFolder().then(f => { if (live) setFolder(f) }).catch(() => { if (live) setFolder({}) })
      off = onBackupFolderChange(f => { if (live) setFolder(f) })
    } catch (e) { setFolder({}) }
    return () => { live = false; off() }
  }, [enabled])
  return [folder, setFolder]
}

/* The Auto-backup row's subtitle names where the copies go: the chosen folder once there is one,
   not Documents/openGym regardless (Android QA). `keep` is AUTO_BACKUP_KEEP. */
export function autoBackupSubtitle(folder, keep) {
  if (folder?.uri && folder.label) return t("SAVES_A_DATED_COPY_TO_COUNT_AFTER_FINISHING_A_WORKOUT_OR_EDITING" /* 每次完成训练或修改计划后，在“{0}”中保存一份带日期的副本，并保留最新的 {1} 份。 */, folder.label, keep)
  if (folder?.uri) return t("SAVES_A_DATED_COPY_TO_THE_FOLDER_YOU_CHOSE_AFTER_FINISHING_A" /* 每次完成训练或修改计划后，在你选择的文件夹中保存一份带日期的副本，并保留最新的 {0} 份。 */, keep)
  return t("SAVES_A_DATED_COPY_TO_DOCUMENTS_OPENGYM_AFTER_FINISHING_A_WORKOUT_OR" /* 完成训练或编辑计划后，会在「文档/openGym」中保存一份带日期的副本，并保留最近的 {0} 份。可以让同步应用指向该文件夹，或手动复制出来。 */, keep)
}

export default function BackupFolderRow() {
  const [folder, setFolder] = useBackupFolder()
  if (!folder) return null

  const choose = async () => {
    try {
      const next = await chooseBackupFolder()
      if (next) setFolder(next)
    } catch (e) { useUI.getState().toast(t("THIS_FOLDER_CAN_T_BE_USED_FOR_BACKUPS" /* 此文件夹无法用于备份。 */)) }
  }
  const useDefault = async () => { setFolder(await resetBackupFolder()) }

  return <>
    <Row icon="folder" iconTint="var(--blue)" title={t("BACKUP_FOLDER" /* 备份文件夹 */)}
      subtitle={folder.uri ? (folder.label || t("CHOSEN_FOLDER" /* 所选文件夹 */)) : DEFAULT_FOLDER} accessory="chevron" onClick={choose} />
    {folder.lost && <Row icon="warning" iconTint="var(--orange)" className="backup-lost"
      title={folder.lostLabel
        ? t("OPENGYM_CAN_NO_LONGER_WRITE_TO_COUNT_SO_COPIES_GO_TO_DOCUMENTS" /* openGym 无法再写入“{0}”，所以副本会重新保存到 Documents/openGym。重新选择该文件夹即可改回。 */, folder.lostLabel)
        : t("OPENGYM_CAN_NO_LONGER_WRITE_TO_THE_CHOSEN_FOLDER_SO_COPIES_GO" /* openGym 无法再写入所选文件夹，所以副本会重新保存到 Documents/openGym。重新选择该文件夹即可改回。 */)} />}
    {(folder.uri || folder.lost) && <Row icon="reset" iconTint="var(--label-3)" title={t("USE_DEFAULT_FOLDER" /* 使用默认文件夹 */)}
      subtitle={DEFAULT_FOLDER} onClick={useDefault} />}
  </>
}
