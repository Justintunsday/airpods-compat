// Native BluetoothManager inventory; no writes, pairing or identity changes.
const load = new NativeFunction(Module.getGlobalExportByName('dlopen'), 'pointer', ['pointer', 'int']);
load(Memory.allocUtf8String('/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager'), 1);
ObjC.schedule(ObjC.mainQueue, () => {
  const result = {devices: [], signatures: {}};
  const cls = ObjC.classes.BluetoothDevice;
  if (cls) for (const selector of ['- productId', '- listeningMode', '- listeningModeConfigs', '- setListeningMode:'])
    if (cls[selector]) result.signatures[selector] = cls[selector].types;
  try {
    const manager = ObjC.classes.BluetoothManager.sharedInstance();
    const devices = manager.connectedDevices();
    for (let i = 0; i < Number(devices.count()); i++) {
      const device = devices.objectAtIndex_(i);
      const pid = Number(device.productId());
      if (![0x2036, 0x2030, 0x2037, 0x2032].includes(pid)) continue;
      result.devices.push({productID: pid, deviceClass: device.$className,
        listeningMode: Number(device.listeningMode()), listeningModeConfigs: Number(device.listeningModeConfigs())});
    }
  } catch (error) { result.error = error.message; }
  send(result);
});
