"""Stable English asset names shared by the catalogue and PNG asset generators."""
from collections import defaultdict
from pathlib import Path
import json
import re
import unicodedata


def slug(text):
    ascii_text = unicodedata.normalize('NFKD', text).encode('ascii', 'ignore').decode()
    return re.sub(r'[^a-z0-9]+', '-', ascii_text.lower()).strip('-')


def asset_names(root):
    entries = {p.stem: json.loads(p.read_text()) for p in (root / 'catalogue/exercises').glob('*.json')}
    groups = defaultdict(list)
    for source in sorted((root / 'catalogue/media/thumbnails').glob('*.webp')):
        entry = entries[source.stem]
        base = entries[entry['variantOf']] if 'variantOf' in entry else entry
        name = slug(base['name']) + ('-female' if 'variantOf' in entry else '')
        groups[name].append((source.stem, base))
    result = {}
    for name, variants in sorted(groups.items()):
        targets = {base['target'] for _, base in variants}
        for index, (identifier, base) in enumerate(variants):
            if len(targets) == len(variants) and len(variants) > 1:
                suffix = '-' + slug(base['target'])
            else:
                # Some source records have identical names, equipment and target muscles.
                # Keep their distinct drawings without putting database IDs in asset names.
                suffix = '' if index == 0 else '-alternate' + ('' if index == 1 else '-' + chr(96 + index))
            result[identifier] = 'ExerciseThumbnails/' + name + suffix
    if len(set(result.values())) != len(result):
        raise ValueError('Duplicate thumbnail asset names; give the conflicting variants distinct English names')
    return result


if __name__ == '__main__':
    print(json.dumps(asset_names(Path(__file__).resolve().parents[2]), sort_keys=True))
