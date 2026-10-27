// Restrict generated user-program memory before browser compilation. The trusted
// Rust compiler has a separate budget and is never passed through this function.
function unsigned(value: number): number[] {
  const result: number[] = [];
  do { let byte = value & 127; value = Math.floor(value / 128); if (value) byte |= 128; result.push(byte); } while (value);
  return result;
}

export function limitProgramMemory(bytes: Uint8Array, maximumPages = 1024): Uint8Array<ArrayBuffer> {
  let cursor = 8;
  const read = () => {
    let result = 0, shift = 0;
    for (let i = 0; i < 5; i++) {
      if (cursor >= bytes.length) throw new Error("Truncated generated Wasm.");
      const byte = bytes[cursor++]; result += (byte & 127) * 2 ** shift;
      if (!(byte & 128)) return result;
      shift += 7;
    }
    throw new Error("Invalid Wasm length.");
  };
  if (bytes.length < 8 || bytes[0] !== 0 || bytes[1] !== 97 || bytes[2] !== 115 || bytes[3] !== 109) throw new Error("Compiler did not produce Wasm.");
  while (cursor < bytes.length) {
    const start = cursor, type = bytes[cursor++], length = read(), end = cursor + length;
    if (end > bytes.length) throw new Error("Invalid Wasm section.");
    if (type === 5) {
      if (read() !== 1) throw new Error("The Playground requires one non-shared program memory.");
      const flags = read();
      if (flags > 1) throw new Error("Shared and 64-bit program memories are not enabled.");
      const initial = read(), declaredMaximum = flags === 1 ? read() : maximumPages;
      if (initial > maximumPages) throw new Error("Program requests more than 64 MiB of memory.");
      if (cursor !== end) throw new Error("Unsupported program memory declaration.");
      const payload = Uint8Array.from([1, 1, ...unsigned(initial), ...unsigned(Math.min(declaredMaximum, maximumPages))]);
      const header = Uint8Array.from([5, ...unsigned(payload.length)]);
      const result = new Uint8Array(start + header.length + payload.length + bytes.length - end);
      result.set(bytes.subarray(0, start)); result.set(header, start); result.set(payload, start + header.length);
      result.set(bytes.subarray(end), start + header.length + payload.length);
      return result;
    }
    cursor = end;
  }
  throw new Error("Generated program has no memory.");
}
