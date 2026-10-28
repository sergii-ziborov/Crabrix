import type { AtlasValue } from "@/lib/algorithm-trace-types";
import { valueText } from "@/lib/algorithm-trace-types";
import { useId } from "react";

type StateProps = { value: AtlasValue; previous?: AtlasValue; name: string; pointers?: [string, number][]; category: string; edge?: { collection: string; from: string; to: string } };
const same = (a: AtlasValue | undefined, b: AtlasValue) => !!a && valueText(a) === valueText(b);

function Cells({ value, previous, pointers = [] }: StateProps & { value: Extract<AtlasValue, { kind: "list" }> }) {
  const before = previous?.kind === "list" ? previous.items : [];
  const numeric = value.items.every(v => v.kind === "scalar" && /^-?\d+(?:\.\d+)?$/.test(v.text) && Math.abs(Number(v.text)) < 1e8);
  const max = numeric ? Math.max(1, ...value.items.map(v => Math.abs(Number(valueText(v))))) : 1;
  return <div className="atlas-scroll"><div className={`atlas-cells ${numeric ? "atlas-bars" : ""}`} role="list" aria-label="Indexed values">
    {value.items.map((item, index) => {
      const markers = pointers.filter(([, n]) => n === index).map(([n]) => n);
      const changed = !!previous && !same(before[index], item);
      return <div className={`atlas-cell ${changed ? "is-changed" : ""} ${markers.length ? "is-current" : ""}`} role="listitem" key={index}>
        <span className="atlas-index">{index}</span>
        {numeric && <span className="atlas-bar" style={{ height: `${8 + 54 * Math.abs(Number(valueText(item))) / max}px` }} />}
        <strong title={valueText(item)}>{valueText(item)}</strong>
        <span className="atlas-pointer">{markers.join(" · ") || (changed ? "changed" : "")}</span>
      </div>;
    })}
    {!value.items.length && <span className="atlas-empty">Empty collection</span>}
  </div></div>;
}

function Matrix({ value, previous, pointers = [] }: StateProps & { value: Extract<AtlasValue, { kind: "list" }> }) {
  const rows = value.items.filter((v): v is Extract<AtlasValue, { kind: "list" }> => v.kind === "list");
  const width = Math.max(0, ...rows.map(r => r.items.length));
  const row = pointers.find(([n]) => ["i", "r", "row"].includes(n))?.[1];
  const col = pointers.find(([n]) => ["j", "c", "col"].includes(n))?.[1];
  return <div className="atlas-scroll"><table className="atlas-matrix" aria-label="Matrix with row and column indices">
    <thead><tr><th scope="col">r / c</th>{Array.from({ length: width }, (_, i) => <th scope="col" key={i}>{i}</th>)}</tr></thead>
    <tbody>{rows.map((r, i) => <tr key={i}><th scope="row">{i}</th>{r.items.map((cell, j) => {
      const before = previous?.kind === "list" && previous.items[i]?.kind === "list" ? previous.items[i].items[j] : undefined;
      return <td key={j} className={`${previous && !same(before, cell) ? "is-changed" : ""} ${row === i && col === j ? "is-current" : ""}`} title={valueText(cell)}>{valueText(cell)}</td>;
    })}</tr>)}</tbody>
  </table></div>;
}

function Graph({ value, pointers = [], state, edge, name }: StateProps & { value: Extract<AtlasValue, { kind: "list" }>; state?: Record<string, AtlasValue> }) {
  const arrowID = useId().replace(/:/g, "");
  const n = value.items.length;
  const nodes = Array.from({ length: n }, (_, i) => ({ x: 220 + 155 * Math.cos(-Math.PI / 2 + 2 * Math.PI * i / n), y: 175 + 135 * Math.sin(-Math.PI / 2 + 2 * Math.PI * i / n) }));
  const edges: { from: number; to: number; weight?: string }[] = [];
  value.items.forEach((row, from) => { if (row.kind === "list") row.items.forEach(item => {
    const target = item.kind === "list" ? item.items[0] : item;
    const to = target?.kind === "scalar" ? Number(target.text) : NaN;
    if (Number.isInteger(to) && to >= 0 && to < n) edges.push({ from, to, weight: item.kind === "list" && item.items[1] ? valueText(item.items[1]) : undefined });
  }); });
  const vertex = (key: string | undefined) => key && state?.[key]?.kind === "scalar" ? Number(state[key].text) : undefined;
  const u = edge?.collection === name ? vertex(edge.from) : pointers.find(([name]) => ["u", "node", "vertex", "v"].includes(name))?.[1];
  const v = edge?.collection === name ? vertex(edge.to) : undefined;
  const distance = state?.distance ?? state?.dist;
  return <div className="atlas-graph"><svg viewBox="0 0 440 350" role="img" aria-label={`Adjacency graph: ${n} vertices. Active vertex ${u ?? "none"}. Edge direction and weights are listed below.`}>
    <defs><marker id={arrowID} viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="var(--muted)" /></marker></defs>
    {edges.map((e, i) => <g key={i} className={u === e.from && v === e.to ? "is-active" : undefined}>
      {e.from === e.to ? <path d={`M ${nodes[e.from].x - 14} ${nodes[e.from].y - 18} c -45 -65 75 -65 30 0`} fill="none" stroke="var(--muted)" strokeWidth="2" markerEnd={`url(#${arrowID})`} /> : <line x1={nodes[e.from].x} y1={nodes[e.from].y} x2={nodes[e.to].x - (nodes[e.to].x - nodes[e.from].x) / Math.max(1, Math.hypot(nodes[e.to].x - nodes[e.from].x, nodes[e.to].y - nodes[e.from].y)) * 25} y2={nodes[e.to].y - (nodes[e.to].y - nodes[e.from].y) / Math.max(1, Math.hypot(nodes[e.to].x - nodes[e.from].x, nodes[e.to].y - nodes[e.from].y)) * 25} markerEnd={`url(#${arrowID})`} />}
      {e.weight && <text className="atlas-edge-weight" x={(nodes[e.from].x * 2 + nodes[e.to].x) / 3} y={(nodes[e.from].y * 2 + nodes[e.to].y) / 3 - 9}>{e.weight}</text>}
    </g>)}
    {nodes.map((point, i) => <g key={i} className={u === i ? "is-active" : undefined}>
      <circle cx={point.x} cy={point.y} r="22" /><text x={point.x} y={point.y + 5}>{i}</text>
      {distance?.kind === "list" && distance.items[i] && <text className="atlas-distance" x={point.x} y={point.y + 40}>{valueText(distance.items[i]) === "9223372036854775807" ? "∞" : valueText(distance.items[i])}</text>}
    </g>)}
  </svg><details><summary>Directed edges{edges.some(e => e.weight) ? " and weights" : ""}</summary><ul>{edges.map((e, i) => <li key={i}>{e.from} → {e.to}{e.weight ? ` · weight ${e.weight}` : ""}</li>)}</ul></details></div>;
}

type TreeNode = { label: string; children: { edge: string; node: TreeNode }[] };
function treeNode(value: AtlasValue, depth = 0): TreeNode | undefined {
  if (depth > 12) return;
  if (value.kind === "named" && value.name === "Some" && value.value.kind === "list") return treeNode(value.value.items[0], depth + 1);
  if (value.kind !== "named" || value.value.kind !== "map") return;
  const fields = Object.fromEntries(value.value.entries.map(([k, v]) => [valueText(k), v]));
  if (!("left" in fields || "right" in fields || "next" in fields)) return;
  const result: TreeNode = { label: valueText(fields.key ?? fields.value ?? fields.val ?? { kind: "scalar", text: value.name }), children: [] };
  for (const edge of ["left", "right", "next"]) {
    const child = fields[edge] && treeNode(fields[edge], depth + 1);
    if (child) result.children.push({ edge, node: child });
  }
  return result;
}

function Tree({ root }: { root: TreeNode }) {
  const nodes: { label: string; x: number; y: number }[] = [], edges: { from: number; to: number; label: string }[] = [];
  let leaf = 0, maxDepth = 0;
  function place(node: TreeNode, depth: number): number {
    const id = nodes.length; nodes.push({ label: node.label, x: 0, y: 35 + depth * 90 }); maxDepth = Math.max(maxDepth, depth);
    const kids = node.children.map(({ edge, node: child }) => { const to = place(child, depth + 1); edges.push({ from: id, to, label: edge }); return to; });
    nodes[id].x = kids.length ? kids.reduce((n, k) => n + nodes[k].x, 0) / kids.length : 40 + leaf++ * 100;
    return id;
  }
  place(root, 0);
  const width = Math.max(180, leaf * 100), height = 80 + maxDepth * 90;
  return <div className="atlas-scroll"><svg className="atlas-tree" viewBox={`0 0 ${width} ${height}`} style={{ minWidth: Math.min(width, 900) }} role="img" aria-label={`Linked nodes: ${nodes.map(n => n.label).join(", ")}`}>
    {edges.map((e, i) => <g key={i}><line x1={nodes[e.from].x} y1={nodes[e.from].y + 20} x2={nodes[e.to].x} y2={nodes[e.to].y - 20} /><text x={(nodes[e.from].x + nodes[e.to].x) / 2 + 15} y={(nodes[e.from].y + nodes[e.to].y) / 2}>{e.label}</text></g>)}
    {nodes.map((n, i) => <g key={i}><circle cx={n.x} cy={n.y} r="24" /><text x={n.x} y={n.y + 5}>{n.label}</text></g>)}
  </svg></div>;
}

export function AlgorithmState(props: StateProps & { state?: Record<string, AtlasValue> }) {
  const { value } = props;
  const tree = treeNode(value);
  if (tree) return <Tree root={tree} />;
  if (value.kind === "list") {
    const matrix = value.items.length > 0 && value.items.every(row => row.kind === "list" && !row.tuple);
    if (matrix && /^(graph|g|adj|adjacency)$/.test(props.name) && value.items.length <= 24) return <Graph {...props} value={value} />;
    if (matrix) return <Matrix {...props} value={value} />;
    return <Cells {...props} value={value} />;
  }
  if (value.kind === "map") return <div className="atlas-scroll"><table className="atlas-map"><thead><tr><th>Key</th><th>Value</th></tr></thead><tbody>{value.entries.map(([k, v], i) => <tr key={i}><th scope="row">{valueText(k)}</th><td>{valueText(v)}</td></tr>)}</tbody></table>{!value.entries.length && <p className="atlas-empty">Empty map</p>}</div>;
  if (value.kind === "set") return <div className="atlas-set" role="list" aria-label="Set members, unordered">{value.items.map((item, i) => <span role="listitem" key={i}>{valueText(item)}</span>)}{!value.items.length && <p className="atlas-empty">Empty set</p>}</div>;
  return <pre className="atlas-raw">{valueText(value)}</pre>;
}
