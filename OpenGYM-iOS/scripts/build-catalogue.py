"""Rebuild the bundled exercise catalogue from an openGym catalogue checkout.

The app ships Resources/catalogue.json and never reads the catalogue over the network. Run this
only when you want to pick up catalogue changes, then rebuild the app:

    python3 scripts/build-catalogue.py /path/to/openGym

The source directory must contain catalogue/exercises/*.json and catalogue/i18n/zh.json.
"""
from pathlib import Path
import json, sys

if len(sys.argv) != 2:
    sys.exit(__doc__)
source = Path(sys.argv[1]).expanduser().resolve()
out = Path(__file__).resolve().parents[1] / 'Resources'
zh = json.loads((source / 'catalogue/i18n/zh.json').read_text())
items = []
for p in sorted((source / 'catalogue/exercises').glob('*.json')):
    e = json.loads(p.read_text())
    if 'id' not in e or 'name' not in e: continue
    t = zh.get(e['id'], {})
    items.append(dict(id=e['id'], name=t.get('name', e['name']), english=e['name'], bodyPart=e['bodyPart'], equipment=e['equipment'], target=e['target'], category=e.get('category', 'strength'), instructions=t.get('instructions', e.get('instructions', [])), englishInstructions=e.get('instructions', []), description=e.get('description', '')))
(out / 'catalogue.json').write_text(json.dumps(items, ensure_ascii=False, separators=(',', ':')))
print(f'Wrote {len(items)} catalogue entries to {out / "catalogue.json"}.')
