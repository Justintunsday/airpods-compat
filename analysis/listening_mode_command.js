// Explicit native control experiment: ANC then restore the original reported
// mode. No raw packets, product-ID spoofing or mode-configuration writes.
const open = new NativeFunction(Module.getGlobalExportByName('dlopen'), 'pointer', ['pointer', 'int']);
open(Memory.allocUtf8String('/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager'), 1);
ObjC.schedule(ObjC.mainQueue, () => {
  const result = {};
  const devices = ObjC.classes.BluetoothManager.sharedInstance().connectedDevices();
  const targets = [];
  for (let i = 0; i < Number(devices.count()); i++) {
    const candidate = devices.objectAtIndex_(i);
    if ([0x2036, 0x2030, 0x2037, 0x2032].includes(Number(candidate.productId()))) targets.push(candidate);
  }
  if (targets.length !== 1) { send({error: 'Need exactly one connected target'}); return; }
  const device = targets[0].retain();
  const original = Number(device.listeningMode());
  const mask = Number(device.listeningModeConfigs());
  result.before = {productID: Number(device.productId()), mode: original, configuredModes: mask};
  if (![1, 2, 3].includes(original) || !(mask & 2)) { device.release(); send({error: 'Reported mode/configuration is not eligible', ...result}); return; }
  result.acceptedANC = device.setListeningMode_(2);
  setTimeout(() => ObjC.schedule(ObjC.mainQueue, () => {
    try { result.afterANC = Number(device.listeningMode()); }
    finally { result.acceptedRestore = device.setListeningMode_(original); }
    setTimeout(() => ObjC.schedule(ObjC.mainQueue, () => {
      result.restoredMode = Number(device.listeningMode());
      result.hardwareProductIDAfter = Number(device.productId());
      device.release(); send(result);
    }), 1200);
  }), 1200);
});
