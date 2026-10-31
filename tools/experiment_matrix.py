#!/usr/bin/env python3
"""Initialize the required device matrix with honest unobserved fields."""
import argparse
import json
from pathlib import Path

STRATEGIES = ['no-tweak', 'existing', 'service-only', 'minimal']
APPLICATIONS = ['SpringBoard', 'Control Center', 'Music', 'Podcasts', 'Safari', 'Third-party audio app']
FIELDS = ['device_name', 'device_classification', 'airpods_icon', 'route_selection',
          'listening_modes', 'actual_playback', 'client_compatibility_injection']


def blank_matrix():
    return {'evidence_rule': 'Unobserved is not pass. Each observation needs a build, OS, process and evidence reference.',
            'rows': [{'strategy': strategy, 'application': application,
                      'observations': dict.fromkeys(FIELDS, None), 'evidence': [], 'status': 'unverified'}
                     for strategy in STRATEGIES for application in APPLICATIONS]}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True)
    options = parser.parse_args()
    Path(options.out).write_text(json.dumps(blank_matrix(), indent=2) + '\n', encoding='utf-8')
