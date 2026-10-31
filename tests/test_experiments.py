import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'tools' / (name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class ExperimentTests(unittest.TestCase):
    def test_service_only_filters_have_no_ui_or_framework_match(self):
        with tempfile.TemporaryDirectory() as output:
            module('prepare_injection_experiment').prepare('service-only', output)
            main = plistlib.loads((Path(output) / 'AirPodsCompat.plist').read_bytes())['Filter']
            resource = plistlib.loads((Path(output) / 'AirPodsCompatResources.plist').read_bytes())['Filter']
            self.assertEqual(set(main['Executables']), {'bluetoothd', 'bluetoothuserd', 'bluetoothaudiod', 'uarpd'})
            self.assertNotIn('Bundles', main)
            self.assertEqual(resource['Executables'], ['AirPodsCompat-Disabled-Experiment'])
            controls = plistlib.loads((Path(output) / 'AirPodsCompatControls.plist').read_bytes())['Filter']
            self.assertEqual(controls['Executables'], ['AirPodsCompat-Disabled-Experiment'])

    def test_matrix_never_fabricates_passes(self):
        matrix = module('experiment_matrix').blank_matrix()
        self.assertEqual(len(matrix['rows']), 24)
        self.assertTrue(all(row['status'] == 'unverified' for row in matrix['rows']))
        self.assertTrue(all(all(value is None for value in row['observations'].values()) for row in matrix['rows']))
    def test_selective_client_requires_both_explicit_identifiers(self):
        prepare = module('prepare_injection_experiment').prepare
        with tempfile.TemporaryDirectory() as output:
            with self.assertRaises(ValueError): prepare('minimal', output, '*', 'ExampleAudio')
            with self.assertRaises(ValueError): prepare('minimal', output, 'com.example.audio', None)
            prepare('minimal', output, 'com.example.audio', 'ExampleAudio')
            preferences = plistlib.loads((Path(output) / 'ExtraResourceClients.plist').read_bytes())
            self.assertEqual(preferences, {'ExtraResourceClientProcesses': ['ExampleAudio']})
