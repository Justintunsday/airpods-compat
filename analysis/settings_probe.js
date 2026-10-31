// Read current Settings controller and selector ABIs, without forcing a page load.
// Load the frameworks only when the controller has not yet been materialized.
if (!ObjC.classes.BTSDeviceConfigController) {
  const open = new NativeFunction(Module.getGlobalExportByName('dlopen'), 'pointer', ['pointer', 'int']);
  for (const path of ['/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager',
                      '/System/Library/PrivateFrameworks/HeadphoneConfigs.framework/HeadphoneConfigs'])
    open(Memory.allocUtf8String(path), 1);
}
ObjC.schedule(ObjC.mainQueue, () => {
  const result = {controllers: [], methods: {}};
  if (ObjC.classes.PSSpecifier) {
    result.specifierSignatures = {};
    for (const selector of ['+ preferenceSpecifierNamed:target:set:get:detail:cell:edit:', '+ groupSpecifierWithName:', '- setButtonAction:', '- propertyForKey:', '- setProperty:forKey:']) {
      const method = ObjC.classes.PSSpecifier[selector];
      if (method) result.specifierSignatures[selector] = method.types;
    }
  }
  for (const name of ['CBDevice', 'BluetoothDevice', 'BTSDevice', 'BTSDeviceClassic', 'CUBluetoothDevice', 'HPSBatteryStatusView', 'BTSDeviceConfigController']) {
    const cls = ObjC.classes[name];
    if (!cls) continue;
    result.methods[name] = {};
    for (const selector of ['- device', '- classicDevice', '- address', '- setSpecifier:', '- productID', '- productId', '- proximityPairingProductID', '- getModelName:', '- getProductIDString', '- getDeviceCaseIcon:', '- getAssetsDictionary:']) {
      if (cls[selector]) result.methods[name][selector] = cls[selector].types;
    }
  }
  const cls = ObjC.classes.BTSDeviceConfigController;
  if (cls) for (const controller of ObjC.chooseSync(cls)) {
    const record = {};
    try {
      const hasGetter = !!controller['- device'];
      const device = hasGetter ? controller.device() : controller.$ivars._device;
      record.deviceStorage = hasGetter ? 'getter' : 'object ivar _device';
      record.deviceClass = device ? device.$className : null;
      if (device) {
        if (device['- classicDevice']?.types.startsWith('@')) {
          const native = device.classicDevice();
          record.nativeDevice = native ? {deviceClass: native.$className, hardwareProductID: Number(native.productId()), vendorID: Number(native.vendorId())} : null;
        }
        record.deviceMethods = device.$methods.filter(name => /address|classic|product|device$/i.test(name));
        record.deviceIvarClasses = {};
        for (const key of Object.keys(device.$ivars).filter(name => /device/i.test(name))) {
          const value = device.$ivars[key];
          record.deviceIvarClasses[key] = value && value.$className ? value.$className : '<non-object or nil>';
        }
        for (const selector of ['productID', 'productId', 'proximityPairingProductID']) {
          if (device.respondsToSelector_(ObjC.selector(selector))) record[selector] = String(device[selector]());
        }
        if (controller.respondsToSelector_(ObjC.selector('getModelName:'))) {
          const value = controller.getModelName_(device);
          const name = value ? value.toString() : null;
          record.modelName = name && /^(AirPods|ACCESSORY_MODEL_NAME_)/.test(name) ? name : '<other or unavailable>';
        }
      }
      if (controller.respondsToSelector_(ObjC.selector('listeningMode'))) record.listeningMode = String(controller.listeningMode());
    } catch (error) { record.error = error.message; }
    result.controllers.push(record);
  }
  send(result);
});
