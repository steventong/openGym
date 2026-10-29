import { cascadeWeight } from '../../../frontend/src/lib/history.js';
import { loadKindFor, baseWeightFor, inventoryFor, rowLoad, ownsPlates } from '../../../frontend/src/lib/plates.js';
import { registerCustom } from '../../../frontend/src/lib/exercises.js';

export function cascadeNativeWeight(input) {
  const { sets, index, side, target = {} } = JSON.parse(input);
  const row = sets[index];
  if (!row) throw Error('训练组不存在。');
  const source = side ? row.sides?.[side] : row;
  if (!source) throw Error('训练侧不存在。');
  source.weightOrigin = 'manual';
  // Literal incomplete input is a manual exception too. Never overwrite hidden unfinished text.
  for (let i = index + 1; i < sets.length; i++) {
    const inputs = sets[i]._nativeInputs || {};
    for (const [path] of Object.entries(inputs)) {
      if (path === 'both.w') sets[i].weightOrigin = 'manual';
      if (path === 'L.w' && sets[i].sides?.L) sets[i].sides.L.weightOrigin = 'manual';
      if (path === 'R.w' && sets[i].sides?.R) sets[i].sides.R.weightOrigin = 'manual';
    }
  }
  return JSON.stringify(cascadeWeight(sets, index, source.w, side, target.backoffStep));
}
export function nativePlateInfo(input) {
  const { state = {}, target = {}, weight } = JSON.parse(input);
  registerCustom(state.customEx || []);
  const kind = loadKindFor(state, target), base = baseWeightFor(state, target.id);
  return JSON.stringify({ load: rowLoad(kind, weight, base, inventoryFor(state)), base, custom: ownsPlates(state) });
}
