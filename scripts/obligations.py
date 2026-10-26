"""Required proof inventory and theory reachability, separate from run results."""
import json
import re
from pathlib import Path

IDENTITY_FIELDS = ('id', 'slug', 'kind', 'law', 'arity', 'module', 'theorems')


def required_inventory(path):
    data = json.loads(Path(path).read_text(encoding='utf8'))
    obligations = data['obligations']
    if not obligations or len({item['slug'] for item in obligations}) != len(obligations):
        raise RuntimeError('Required obligations must have unique group identities')
    return obligations


def check_registration(required, registered):
    expected = {item['slug']: item for item in required}
    actual = {item['slug']: item for item in registered}
    if set(expected) != set(actual):
        raise RuntimeError('Required group identities differ from catalog registration: '
                           f'missing={sorted(set(expected) - set(actual))}, '
                           f'extra={sorted(set(actual) - set(expected))}')
    for slug, item in actual.items():
        for field in IDENTITY_FIELDS:
            if item.get(field) != expected[slug].get(field):
                raise RuntimeError(f'Required obligation identity changed: {slug}.{field}')


def coverage(required, registered, accepted=()):
    wanted = {item['slug'] for item in required}
    present = {item['slug'] for item in registered}
    supported = {item['slug'] for item in registered if item.get('status') == 'supported'}
    checked = set(accepted)
    missing = wanted - (supported & checked)
    return {'required': sorted(wanted), 'registered': sorted(present),
            'supported': sorted(supported), 'accepted': sorted(checked),
            'missing': sorted(missing), 'complete': not missing and present == wanted,
            'state': 'COMPLETE' if not missing and present == wanted else 'INCOMPLETE'}


def orphan_modules(directory, roots):
    sources = {f'HoldLedgerProof.{path.stem}': path
               for path in Path(directory).glob('*.lean')}
    visited = set()

    def visit(module):
        if module in visited or module not in sources:
            return
        visited.add(module)
        text = sources[module].read_text(encoding='utf8')
        for imported in re.findall(r'(?m)^(?:public\s+)?import\s+(?:all\s+)?(HoldLedgerProof\.\w+)', text):
            visit(imported)

    for root in roots:
        visit(root)
    return sorted(set(sources) - visited)
