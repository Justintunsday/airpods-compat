"""Packaging/hook integration contracts, separate from runtime/device validation."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RepositoryTests(unittest.TestCase):
    def test_default_filter_is_explicit(self):
        text = (ROOT / 'tweak/AirPodsCompatResources.plist').read_text()
        strings = set(re.findall(r'"([^"\n]+)"', text))
        self.assertEqual(strings, {'com.apple.springboard', 'com.apple.Music', 'com.apple.podcasts', 'com.apple.PosterBoard', 'MusicUIService'})
        self.assertNotIn('com.apple.UIKit', text)
        self.assertNotIn('com.apple.MediaPlayer', text)

    def test_accessory_filter_stays_small(self):
        text = (ROOT / 'tweak/AirPodsCompat.plist').read_text()
        self.assertEqual(set(re.findall(r'"([^"\n]+)"', text)), {
            'com.apple.springboard', 'com.apple.Preferences', 'bluetoothd',
            'bluetoothuserd', 'bluetoothaudiod', 'uarpd', 'HeadphoneProxService'})

    def test_swift_factory_preserves_native_calling_context(self):
        text = (ROOT / 'tweak/Hooks/HeadphoneFeatureHooks.mm').read_text()
        self.assertIn('SwiftFeatureFactory.h', text)
        self.assertIn('swift_context', text)
        self.assertIn('originalFactory(decision.lookupProductID, device, context)', text)
        self.assertIn('ACNativeAirPods5FeatureContent()', text)
        self.assertIn('B768FeatureContentCMa', text)
        self.assertNotIn('objc_allocateClassPair', text)

    def test_modern_scopes_exclude_identity_lifecycle(self):
        text = (ROOT / 'tweak/Hooks/HeadphoneConfigHooks.mm').read_text()
        hooks = text.split('} hooks[] = {')[1].split('};')[0]
        self.assertEqual(len(re.findall(r'\{"', hooks)), 5)
        for forbidden in ['loadAccessorySettings', 'FindMy', 'Firmware', 'setListeningMode', 'pair']:
            self.assertNotIn(forbidden, hooks)
        self.assertIn('@finally', text)
        self.assertIn('!= scopedDevice', text)
        self.assertIn('MSHookMessageEx(device, @selector(productId)', text)

    def test_registration_and_telemetry_are_not_spoofed(self):
        resource = (ROOT / 'tweak/SystemIntegration/ResourceResolver.mm').read_text()
        for forbidden in ['setPercentCharge:', 'setBatteryLevel:', 'setParts:', 'setProductIdentifier:']:
            self.assertNotIn(forbidden, resource)
        registration = (ROOT / 'tweak/Bluetooth/AccessoryRegistration.mm').read_text()
        self.assertNotIn('ACCompatibilitySelect', registration)
        self.assertIn('ACWithRegistrationGuard', registration)
    def test_identity_guards_do_not_wrap_general_settings_loading(self):
        text = (ROOT / 'tweak/Bluetooth/IdentityBoundaries.mm').read_text()
        self.assertNotIn('@"loadAccessoryInfo"', text)
        self.assertNotIn('@"loadAccessorySettings"', text)
        self.assertIn('@"loadAccessoryFirmwareInfo"', text)
    def test_noise_controls_are_ui_only_and_use_real_device_identity(self):
        filter_text = (ROOT / 'tweak/AirPodsCompatControls.plist').read_text()
        self.assertEqual(set(re.findall(r'"([^"\n]+)"', filter_text)), {'com.apple.Preferences'})
        adapter = (ROOT / 'tweak/SystemIntegration/NoiseControlAdapter.mm').read_text()
        self.assertIn('@selector(productId)', adapter)
        self.assertNotIn('setProductID', adapter)
        self.assertNotIn('setListeningModeConfigs:', adapter)
        module = (ROOT / 'tweak/CCModule/NoiseControlModule.mm').read_text()
        self.assertIn('ACNoiseControlSnapshot', module)
        self.assertNotIn('_selected =', module)


if __name__ == '__main__':
    unittest.main()
