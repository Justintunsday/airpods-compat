#!/usr/bin/env python3
"""Validate all shipped model representations; does not assert hardware support."""
import json
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def validate():
    source = json.loads((ROOT / 'models/airpods.json').read_text(encoding='utf-8'))
    app = json.loads((ROOT / 'app/Resources/Models.json').read_text(encoding='utf-8'))
    tweak = plistlib.loads((ROOT / 'tweak/layout/Library/Application Support/AirPodsCompat/AirPodsCompatModels.plist').read_bytes())
    assert source == app, 'app model table drifted'
    models = source['models']
    assert len(models) == len(tweak['UARP']) == 33
    assert len({m['model'] for m in models}) == len(models)
    assert len({m['productID'] for m in models}) == len(models)
    expected = {0x2036: 'A3532', 0x2030: 'A3440', 0x2037: 'A3533', 0x2032: 'A3441', 0x201b: 'A3056'}
    for pid, model in expected.items():
        assert any(m['productID'] == pid and m['model'] == model for m in models), (pid, model)
    for source_model, package_model in zip(models, tweak['UARP']):
        for key in ('model', 'productID', 'appleModelNumber', 'baseClasses', 'tier'):
            assert source_model[key] == package_model[key], (key, source_model['model'])
        assert source_model.get('alt', []) == package_model.get('alternativeAppleModelNumbers', [])
        assert source_model['display'] == tweak['DisplayNames'][str(source_model['productID'])]
        assert 0 < source_model['productID'] <= 65535
    print('Registry: 33 models, all four AirPods 5 PIDs, 0x201b target and shipped copies agree')


if __name__ == '__main__':
    validate()
