// Read only. Use Apple's accessors for the opaque IOPS snapshot; never publish
// or relabel power sources. No Bluetooth identifiers or user names are exported.
const api = (name, result, args) => {
  const address = Module.findGlobalExportByName(name);
  if (!address) throw new Error(name + ' unavailable');
  return new NativeFunction(address, result, args);
};
ObjC.schedule(ObjC.mainQueue, () => {
  let snapshot = ptr(0), sources = ptr(0), release;
  try {
    const copy = api('IOPSCopyPowerSourcesByType', 'pointer', ['int']);
    const list = api('IOPSCopyPowerSourcesList', 'pointer', ['pointer']);
    const description = api('IOPSGetPowerSourceDescription', 'pointer', ['pointer', 'pointer']);
    const count = api('CFArrayGetCount', 'long', ['pointer']);
    const item = api('CFArrayGetValueAtIndex', 'pointer', ['pointer', 'long']);
    release = api('CFRelease', 'void', ['pointer']);
    snapshot = copy(0); // kIOPSSourceAll, not a guessed CFString or type pointer.
    if (snapshot.isNull()) throw new Error('No IOPS snapshot');
    sources = list(snapshot);
    const records = [];
    if (!sources.isNull()) for (let i = 0; i < Number(count(sources)); i++) {
      const data = description(snapshot, item(sources, i));
      if (data.isNull()) continue;
      const dictionary = new ObjC.Object(data);
      const record = {};
      for (const key of ['Type', 'Part Identifier', 'Product ID', 'Vendor ID', 'Transport Type',
                         'Current Capacity', 'Max Capacity', 'Is Charging', 'Is Present', 'Accessory Category']) {
        const value = dictionary.objectForKey_(key);
        if (value) record[key] = value.toString();
      }
      records.push(record);
    }
    send({process: ObjC.classes.NSProcessInfo.processInfo().processName().toString(), records,
      conclusion: 'Only an explicitly identified, source-verified Case record can establish charging-case telemetry.'});
  } catch (error) { send({error: error.message}); }
  finally {
    if (release && !sources.isNull()) release(sources);
    if (release && !snapshot.isNull()) release(snapshot);
  }
});
