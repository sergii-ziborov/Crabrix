import type { AtlasValue } from "./algorithm-trace-types.ts";
import { valueText } from "./algorithm-trace-types.ts";

export function edgeTarget(item: AtlasValue): number {
  const target = item.kind === "list" ? item.items[0] : item;
  return target?.kind === "scalar" ? Number(target.text) : NaN;
}

// A list of lists is only a graph when every entry names a vertex of that list.
export function isAdjacencyList(value: Extract<AtlasValue, { kind: "list" }>): boolean {
  return value.items.every(row => row.kind === "list" && row.items.every(item => {
    const to = edgeTarget(item);
    return Number.isInteger(to) && to >= 0 && to < value.items.length;
  }));
}

export type TreeNode = { label: string; children: { edge: string; node: TreeNode }[] };
const MAX_LINK_DEPTH = 64;

// Depth counts nodes. An Option's `Some` wrapper is not a level of the structure.
export function linkedTree(value: AtlasValue | undefined, depth = 0): TreeNode | undefined {
  if (!value || depth >= MAX_LINK_DEPTH) return;
  if (value.kind === "named" && value.name === "Some" && value.value.kind === "list") return linkedTree(value.value.items[0], depth);
  if (value.kind !== "named" || value.value.kind !== "map") return;
  const fields = Object.fromEntries(value.value.entries.map(([k, v]) => [valueText(k), v]));
  if (!("left" in fields || "right" in fields || "next" in fields)) return;
  const result: TreeNode = { label: valueText(fields.key ?? fields.value ?? fields.val ?? { kind: "scalar", text: value.name }), children: [] };
  for (const edge of ["left", "right", "next"]) {
    const child = linkedTree(fields[edge], depth + 1);
    if (child) result.children.push({ edge, node: child });
  }
  return result;
}
