from pathlib import Path
import json, shutil
from thumbnail_assets import asset_names
root=Path(__file__).resolve().parents[2]
out=root/'native-ios/OpenGym/Resources'
zh=json.loads((root/'catalogue/i18n/zh.json').read_text())
thumbnails=asset_names(root)
items=[]
for p in sorted((root/'catalogue/exercises').glob('*.json')):
    e=json.loads(p.read_text())
    if 'id' not in e or 'name' not in e: continue
    t=zh.get(e['id'],{})
    items.append(dict(id=e['id'],name=t.get('name',e['name']),english=e['name'],thumbnailAsset=thumbnails[e['id']],bodyPart=e['bodyPart'],equipment=e['equipment'],target=e['target'],category=e.get('category','strength'),instructions=t.get('instructions',e.get('instructions',[])),englishInstructions=e.get('instructions',[]),description=e.get('description','')))
(out/'catalogue.json').write_text(json.dumps(items,ensure_ascii=False,separators=(',',':')))
shutil.copy(root/'NOTICE.md',out/'NOTICE.txt')
shutil.copy(root/'LICENSE',out/'LICENSE.txt')
print(f'Prepared {len(items)} original catalogue entries; videos download on demand into Documents/workout-videos.')
