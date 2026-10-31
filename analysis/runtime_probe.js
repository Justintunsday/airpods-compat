// Read-only instrumentation. No method replacements, PID writes or percentages.
// Do not confuse instrumentation attachment with installation of the tweak.
const moduleFor = pointer => {
  try { return Process.findModuleByAddress(pointer.strip()).name; } catch (_) { return 'unknown'; }
};
const read = (object, selector) => {
  try {
    if (!object || !object.respondsToSelector_(ObjC.selector(selector))) return null;
    const value = object[selector]();
    if (value === null) return null;
    return typeof value === 'object' ? value.toString() : value;
  } catch (_) { return null; }
};

ObjC.schedule(ObjC.mainQueue, () => {
  const result = {process: Process.name, hooks: {}, routes: [], batteries: [], limitations: []};
  for (const [name, selector] of [
    ['MPAVOutputDeviceRoute', '- productIdentifier'],
    ['MPAVRoutingController', '+ _symbolNameForRoute:'],
    ['MRUOutputDeviceAsset', '- initWithOutputDeviceRoute:'],
    ['BCBatteryDevice', '- batteryWidgetGlyphName:']
  ]) {
    const method = ObjC.classes[name]?.[selector];
    result.hooks[name + selector] = method ? {encoding: method.types, image: moduleFor(method.implementation)} : null;
  }
  const routeClass = ObjC.classes.MPAVOutputDeviceRoute;
  if (routeClass) for (const route of ObjC.chooseSync(routeClass).slice(0, 24)) {
    const before = read(route, 'productIdentifier');
    if (!before) continue;
    const record = {modelBefore: before, routeSubtype: read(route, 'routeSubtype'), isAirpodsRoute: read(route, 'isAirpodsRoute')};
    try {
      const controller = ObjC.classes.MPAVRoutingController;
      if (controller?.['+ _symbolNameForRoute:']) {
        const symbol = controller['+ _symbolNameForRoute:'](route);
        record.symbol = symbol ? symbol.toString() : null;
      }
      const assetClass = ObjC.classes.MRUOutputDeviceAsset;
      if (assetClass?.['- initWithOutputDeviceRoute:']) {
        const asset = assetClass.alloc().initWithOutputDeviceRoute_(route);
        if (asset) {
          record.assetType = read(asset, 'type');
          record.hasImage = !!asset.icon();
          asset.release();
        }
      }
    } catch (error) { record.error = error.message; }
    record.modelAfter = read(route, 'productIdentifier');
    result.routes.push(record);
  }
  const controller = ObjC.classes.BCBatteryDeviceController;
  if (controller?.['+ _sharedPowerSourceController']) {
    try {
      const devices = controller['+ _sharedPowerSourceController']().connectedDevices();
      for (let i = 0; i < Number(devices.count()); i++) {
        const device = devices.objectAtIndex_(i);
        const record = {};
        for (const key of ['productIdentifier', 'vendor', 'transportType', 'parts', 'percentCharge', 'isCharging']) record[key] = read(device, key);
        if (device.respondsToSelector_(ObjC.selector('batteryWidgetGlyphName:'))) {
          const flag = Memory.alloc(1); flag.writeU8(0);
          const glyph = device.batteryWidgetGlyphName_(flag);
          record.glyph = glyph ? glyph.toString() : null;
          record.isImage = !!flag.readU8();
        }
        result.batteries.push(record);
      }
    } catch (error) { result.limitations.push(error.message); }
  }
  if (!result.routes.length) result.limitations.push('No live route objects observed; open the output UI while connected.');
  result.limitations.push('Factory observations are not screen acceptance or proof of playback/listening-mode behavior.');
  send(result);
});
