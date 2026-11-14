import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { stampPut } from '/app/sync-stamps.js';

// Run inside the existing API container. Authentication stays in memory there.
const record = JSON.parse(fs.readFileSync(0, 'utf8'));
const uid = 'LhEb0Tg3gzidmdnz';
assert.equal(record.id, 'D3645B7D-288A-4946-BCDF-CA7C10285826');
assert.equal(record.d, '2026-10-29');
const user = JSON.parse(fs.readFileSync('/data/db.json')).users.find(u => u.id === uid);
assert.equal(user.name, 'Steven');
assert.ok(!user.disabled);
const payload = `${uid}:${Date.now() + 120000}:${user.sv || 0}:c`;
const token = payload + '.' + crypto.createHmac('sha256', fs.readFileSync('/data/secret', 'utf8').trim()).update(payload).digest('base64url');
const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
const url = `http://127.0.0.1:${process.env.PORT || 3000}/api/data`;
const backup = '/data/backups/restore-workout-20261105-' + new Date().toISOString().replace(/[:.]/g, '-');
fs.mkdirSync(backup, { mode: 0o700 });
const save = (name, value) => fs.writeFileSync(`${backup}/${name}.json`, JSON.stringify(value, null, 2), { mode: 0o600 });
const get = async () => {
  const r = await fetch(url, { headers });
  assert.equal(r.status, 200, 'GET failed');
  return await r.json();
};
const metadata = new Set(['_rev', '_ts', '_wid', '_wids', '_unstamped', '_prior', 'deleted', 'edited', 'workouts']);
function verify(before, after) {
  assert.equal(after.workouts.length, before.workouts.length + 1);
  assert.deepEqual(after.workouts.filter(w => w.id !== record.id), before.workouts);
  assert.deepEqual(after.workouts.filter(w => w.id === record.id), [record]);
  for (const k of new Set([...Object.keys(before), ...Object.keys(after)])) {
    if (!metadata.has(k)) assert.deepEqual(after[k], before[k], `Unrelated field changed: ${k}`);
  }
  assert.deepEqual(after.edited, before.edited);
  const deletions = structuredClone(after.deleted);
  assert.ok(deletions.workouts[record.id] < 0, 'Restoration marker missing');
  assert.ok(Math.abs(deletions.workouts[record.id]) > before.deleted.workouts[record.id]);
  deletions.workouts[record.id] = before.deleted.workouts[record.id];
  assert.deepEqual(deletions, before.deleted);
}
save('restored-record', record);
let complete = false;
for (let attempt = 0; attempt < 3; attempt++) {
  const { state: before, rev } = await get();
  assert.equal(before.unit, 'kg');
  assert.ok(!before.workouts.some(w => w.id === record.id || w.d === record.d), 'Record already present; review instead of overwriting');
  assert.ok(before.deleted?.workouts?.[record.id] > 0);
  save(`before-${attempt}`, before);
  const raw = JSON.parse(fs.readFileSync(`/data/state-${uid}.json`));
  if (raw._rev !== rev || raw._wid !== before._wid) continue;
  save(`raw-before-${attempt}`, raw);
  const next = structuredClone(before);
  const insertion = next.workouts.findIndex(w => w.d > record.d || (w.d === record.d && (w.start || 0) > record.start));
  next.workouts.splice(insertion < 0 ? next.workouts.length : insertion, 0, structuredClone(record));
  const preview = structuredClone(next);
  stampPut(raw, preview, { overRead: true });
  verify(before, preview);
  const response = await fetch(url, { method: 'PUT', headers, body: JSON.stringify({ state: next, baseRev: rev, baseWid: before._wid }) });
  if (response.status === 409) continue;
  assert.equal(response.status, 200, 'PUT failed');
  const result = await response.json();
  save('put-result', result);
  const { state: after, rev: finalRev } = await get();
  save('after', after);
  verify(before, after);
  const summary = {
    status: 'restored_verified', account: user.name, origin: 'https://opengym.neltavin.com',
    id: record.id, date: record.d, name: record.name,
    entries: record.entries.length, sets: record.entries.reduce((n, e) => n + e.sets.length, 0),
    durationMinutes: (record.end - record.start) / 60000,
    previousCount: before.workouts.length, count: after.workouts.length,
    previousRev: rev, revision: finalRev, allOtherContentPreserved: true,
    restorationMarker: after.deleted.workouts[record.id], backup,
    backupSha256: crypto.createHash('sha256').update(JSON.stringify(before)).digest('hex'),
    source: 'opengym-backup-2026-11-03.json', verifiedAt: new Date().toISOString()
  };
  save('verification', summary);
  console.log(JSON.stringify(summary, null, 2));
  complete = true;
  break;
}
assert.ok(complete, 'Concurrent changes prevented restoration; backups retained');
