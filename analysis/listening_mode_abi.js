// Read native method instructions and symbol names; no control commands.
const open = new NativeFunction(Module.getGlobalExportByName('dlopen'), 'pointer', ['pointer', 'int']);
open(Memory.allocUtf8String('/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager'), 1);
const results = {};
for (const selector of ['- listeningMode', '- setListeningMode:']) {
  const method = ObjC.classes.BluetoothDevice[selector];
  if (!method) continue;
  let pc = method.implementation.strip();
  const lines = [];
  for (let i = 0; i < 100; i++) {
    const instruction = Instruction.parse(pc);
    let line = instruction.toString();
    if (instruction.mnemonic === 'bl' || instruction.mnemonic === 'b') {
      try { line += ' -> ' + DebugSymbol.fromAddress(ptr(instruction.operands[0].value)).name; } catch (_) {}
    }
    lines.push(line); pc = instruction.next;
    if (instruction.mnemonic === 'ret' || instruction.mnemonic === 'retab') break;
  }
  results[selector] = {types: method.types, instructions: lines};
}
send(results);
