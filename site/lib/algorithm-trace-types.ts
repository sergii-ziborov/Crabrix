export type AtlasValue =
  | { kind: "scalar"; text: string }
  | { kind: "list"; items: AtlasValue[]; tuple?: boolean }
  | { kind: "set"; items: AtlasValue[] }
  | { kind: "map"; entries: [AtlasValue, AtlasValue][] }
  | { kind: "named"; name: string; value: AtlasValue };

export type AlgorithmTrace = {
  version: 1;
  key: string;
  sourceHash: string;
  pattern: string;
  category: string;
  title: string;
  idea: string;
  complexity: string;
  source: string;
  input: string;
  stdout: string;
  sites: { line: number; function: string; statement: string; edge?: { collection: string; from: string; to: string } }[];
  values: { type: string; data: AtlasValue }[];
  frames: { site: number; stack: [string, number][]; locals: [string, number][] }[];
  verification: { stdoutMatchesOriginal: boolean; independentOracle: boolean; omittedCaptures: number };
};

export function valueText(value: AtlasValue): string {
  switch (value.kind) {
    case "scalar": return value.text;
    case "list": return `${value.tuple ? "(" : "["}${value.items.map(valueText).join(", ")}${value.tuple ? ")" : "]"}`;
    case "set": return `{${value.items.map(valueText).join(", ")}}`;
    case "map": return `{${value.entries.map(([k, v]) => `${valueText(k)}: ${valueText(v)}`).join(", ")}}`;
    case "named": return `${value.name}${valueText(value.value)}`;
  }
}
