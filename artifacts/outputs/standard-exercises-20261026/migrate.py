import copy
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
before = json.loads((ROOT / 'before.json').read_text())
after = copy.deepcopy(before)
customs = {e['id']: e for e in before['customEx']}
mapping = {}
rows = []
for old, e in customs.items():
    match = re.match(r'对应 openGym (\d+)：([^。]+)', e['desc'])
    assert match, (old, e['desc'])
    new = match[1]
    standard = json.loads((REPO / 'catalogue/exercises' / (new + '.json')).read_text())
    assert standard['id'] == new
    assert standard['name'].lower() == match[2].lower(), (old, standard['name'], match[2])
    mapping[old] = new
    rows.append({'oldID': old, 'oldName': e['n'], 'standardID': new,
                 'standardName': standard['name'], 'description': e['desc']})

# Preserve separate blocks when one session used different loading modes (e.g.
# bodyweight and bands). Changing their identity must not merge or drop sets.
changed_entries = 0
for workout in after['workouts']:
    for entry in workout['entries']:
        old = entry['id']
        if old not in mapping:
            continue
        entry['id'] = mapping[old]
        assert entry['target']['id'] == old
        entry['target']['id'] = mapping[old]
        gym = re.search(r'健身房：([^。]+)', customs[old]['desc'])
        if gym:
            entry['note'] = '健身房：' + gym[1] + '。\n' + entry.get('note', '')
        changed_entries += 1

# The newest recorded weight wins when gym-specific IDs share a standard ID.
# Existing standard-ID entries win equal-date ties. All original values remain
# recoverable in before.json and the collision audit.
weights = {k: copy.deepcopy(v) for k, v in before['exWeights'].items() if k not in mapping}
weight_collisions = []
for old, value in before['exWeights'].items():
    if old not in mapping:
        continue
    new = mapping[old]
    existing = weights.get(new)
    if existing is not None:
        weight_collisions.append({'oldID': old, 'standardID': new, 'candidate': value, 'existing': existing})
    if existing is None or value.get('d', '') > existing.get('d', ''):
        weights[new] = copy.deepcopy(value)
after['exWeights'] = weights

# Keep all former exercise descriptions, gym-specific cautions and user notes
# as notes on the actual built-in exercise, rather than retaining custom copies.
notes = {k: v for k, v in before.get('exNotes', {}).items() if k not in mapping}
for old, e in customs.items():
    new = mapping[old]
    parts = [e['desc'], before.get('exNotes', {}).get(old, '')]
    addition = '\n'.join(p for p in parts if p)
    notes[new] = '\n\n'.join(p for p in [notes.get(new, ''), addition] if p)
after['exNotes'] = notes
after['customEx'] = []

# Fail closed on unexpected references instead of silently dropping a setting.
def references(value, path=''):
    out = []
    if isinstance(value, dict):
        for key, child in value.items():
            if key in mapping:
                out.append(path + '/' + key)
            out += references(child, path + '/' + key)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            out += references(child, path + '/' + str(index))
    elif isinstance(value, str) and value in mapping:
        out.append(path)
    return out

assert not references(after), references(after)
allowed = {'workouts', 'customEx', 'exWeights', 'exNotes'}
for key in before.keys() | after.keys():
    if key not in allowed:
        assert before.get(key) == after.get(key), key
for old_workout, new_workout in zip(before['workouts'], after['workouts']):
    assert len(old_workout['entries']) == len(new_workout['entries'])
    for old_entry, new_entry in zip(old_workout['entries'], new_workout['entries']):
        restored = copy.deepcopy(new_entry)
        restored['id'] = old_entry['id']
        restored['target']['id'] = old_entry['target']['id']
        if 'note' in old_entry:
            restored['note'] = old_entry['note']
        else:
            restored.pop('note', None)
        assert restored == old_entry
    assert {k:v for k,v in old_workout.items() if k != 'entries'} == {k:v for k,v in new_workout.items() if k != 'entries'}

report = {
    'customBefore': len(customs), 'customAfter': 0,
    'standardTargets': len(set(mapping.values())), 'migratedEntries': changed_entries,
    'workouts': len(after['workouts']), 'routines': len(after['routines']),
    'sets': sum(len(e['sets']) for w in after['workouts'] for e in w['entries']),
    'allSetPayloadsUnchanged': True, 'allTargetsValidatedAgainstCatalogue': True,
    'unresolvedCustomReferences': references(after), 'weightCollisions': weight_collisions,
}
for name, data in [('migrated.json', after), ('mapping.json', rows), ('validation.json', report)]:
    target = ROOT / name
    target.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    target.chmod(0o600)
print(json.dumps({k:v for k,v in report.items() if k != 'weightCollisions'}, ensure_ascii=False, indent=2))
