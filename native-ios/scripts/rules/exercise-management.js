import { defaultConfig, buildSets, cleanupSg, pairAdjacent, unpairSuperset } from '../../../frontend/src/lib/history.js';
import { registerCustom } from '../../../frontend/src/lib/exercises.js';
import { hasCompletedWork } from '../../../frontend/src/lib/workout-model.js';
import { replaceSlotExercise } from '../../../frontend/src/lib/routines.js';

// Remap by occurrence, never by exercise ID: a session may contain the same ID twice.
export function manageTrainingExercises(input) {
  const { active, state = {}, action, index, direction, id, history = false } = JSON.parse(input);
  const s = { unit: 'kg', workouts: [], routines: [], exWeights: {}, customEx: [], ...state };
  registerCustom(s.customEx);
  let entries = active.entries || [];
  const order = entries.map((_, i) => i);
  const current = entries[index];
  let selected = active.cur || 0, invalidated = null;
  if (action === 'pair' || action === 'unpair') {
    if (!current || active.nativeTimer) return JSON.stringify(active);
    entries = action === 'pair' ? pairAdjacent(entries,index,index+direction) : unpairSuperset(entries,index);
  } else if (action === 'move') {
    const to = index + direction;
    if (!current || ![-1, 1].includes(direction) || to < 0 || to >= entries.length) return JSON.stringify(active);
    [entries[index], entries[to]] = [entries[to], entries[index]];
    [order[index], order[to]] = [order[to], order[index]];
  } else if (action === 'remove') {
    if (!current) return JSON.stringify(active);
    entries.splice(index, 1); order.splice(index, 1);
  } else if (action === 'add' || action === 'replace') {
    if (!id || (action === 'replace' && (!current || current.id === id))) return JSON.stringify(active);
    if (history && action === 'replace') {
      // A historical correction intentionally reassigns recorded sets, preserving literal input.
      entries[index] = { ...current, id, target: replaceSlotExercise(current.target || {}, id, s, current.rid) };
      for (const key of ['plan', 'planned', 'topW']) delete entries[index][key];
    } else {
      const target = { id, ...defaultConfig(id) };
      const past = { ...s, workouts: s.workouts.filter(w => !active.start || Number(w.start || 0) < active.start) };
      const replacement = { id, target, sets: buildSets(past, target, { preferLast: true }) };
      if (history) replacement.sets = replacement.sets.map(row => ({ ...row, done: true }));
      if (action === 'replace') {
        if (current.rid) replacement.rid = current.rid;
        if (current.noProg === true) replacement.noProg = true;
        // Include partially completed sides; these must never be silently relabelled.
        if ((current.sets || []).some(hasCompletedWork)) {
          let insertAt = index + 1;
          while (current.sg && entries[insertAt]?.sg === current.sg) insertAt++;
          entries.splice(insertAt, 0, replacement); order.splice(insertAt, 0, null);
          selected = insertAt;
        } else {
          const metadata = Object.fromEntries(Object.entries(current).filter(([key]) =>
            !['id', 'target', 'plan', 'planned', 'carried', 'sets', 'topW'].includes(key)));
          entries[index] = { ...metadata, ...replacement }; invalidated = index; selected = index;
        }
      } else {
        entries.push(replacement); order.push(null); selected = entries.length - 1;
      }
    }
  } else return JSON.stringify(active);
  // Reordering/removal can dissolve a group; keep entry and target metadata consistent.
  cleanupSg(entries);
  entries.forEach(e => {
    if (!e.sg && e.target) {
      e.target = { ...e.target };
      for (const key of ['sg', 'sgName', 'sgRest']) delete e.target[key];
    }
  });
  for (const key of ['nativeTimer', 'nativeRest']) {
    const timer = active[key];
    if (!timer) continue;
    const next = order.indexOf(timer.entry);
    if (next < 0 || timer.entry === invalidated) delete active[key];
    else active[key] = { ...timer, entry: next };
  }
  const levels = {};
  order.forEach((old, next) => {
    if (old != null && old !== invalidated && active.nativeHighWater?.[old] != null) levels[next] = active.nativeHighWater[old];
  });
  active.nativeHighWater = levels;
  if (action === 'move' || action === 'remove') {
    const mapped = order.indexOf(selected);
    selected = mapped < 0 ? Math.min(selected, entries.length - 1) : mapped;
  }
  active.cur = Math.max(0, selected);
  active.entries = entries;
  delete active.nativeFinishAt;
  return JSON.stringify(active);
}

export function replaceNativeRoutineExercise(input) {
  const { slot, id, state, rid } = JSON.parse(input);
  registerCustom(state.customEx || []);
  return JSON.stringify(replaceSlotExercise(slot, id, state, rid));
}
