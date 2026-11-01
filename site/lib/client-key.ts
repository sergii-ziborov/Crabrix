// IPv6 customers usually control a whole /64, so per-address limits use that prefix.
export function clientKey(address: string | null | undefined): string {
  const value = (address ?? "").trim().toLowerCase().split("%")[0];
  if (!value) return "direct";
  if (!value.includes(":")) return value;
  const mapped = value.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  if (mapped) return mapped[1];
  const [head, tail] = value.split("::");
  const left = head ? head.split(":") : [];
  const right = tail ? tail.split(":") : [];
  const full = value.includes("::") ? [...left, ...Array(Math.max(0, 8 - left.length - right.length)).fill("0"), ...right] : left;
  return full.slice(0, 4).map(part => part.replace(/^0+(?=.)/, "")).join(":") + "::/64";
}
