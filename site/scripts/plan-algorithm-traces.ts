/** Author-time only. Instrument the checked-in Academy fixtures, never visitor code. */
import { parser } from "@lezer/rust";
import type { SyntaxNode } from "@lezer/common";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const helper = "__crabrix_atlas";
function children(n: SyntaxNode) { const out: SyntaxNode[] = []; for (let c = n.firstChild; c; c = c.nextSibling) out.push(c); return out; }
function walk(n: SyntaxNode, visit: (n: SyntaxNode) => boolean | void) { if (visit(n) === false) return; for (const c of children(n)) walk(c, visit); }

function plan(source: string) {
  const tree = parser.parse(source), edits = new Map<number, { text: string; priority: number }[]>();
  const sites: { line: number; function: string; statement: string; edge?: { collection: string; from: string; to: string } }[] = [];
  const captures: Record<string, string> = {};
  let captureID = 0, deriveID = 0;
  const text = (n: SyntaxNode) => source.slice(n.from, n.to);
  const add = (at: number, value: string, priority = 10) => edits.set(at, [...(edits.get(at) ?? []), { text: value, priority }]);
  const bindings = (n: SyntaxNode) => { const out: string[] = []; walk(n, c => { if (c.name === "BoundIdentifier") out.push(text(c)); if (["Block", "ClosureExpression", "FunctionItem"].includes(c.name)) return false; }); return out; };
  walk(tree.topNode, n => {
    if (n.type.isError) throw new Error(`Rust parse error near ${text(n)}`);
    if (!["StructItem", "EnumItem"].includes(n.name)) return;
    let attrs = "";
    for (let p = n.parent; p?.name === "AttributeItem"; p = p.parent) attrs += text(p);
    if (!/\bDebug\b/.test(attrs)) add(n.from, `\n#[derive(Debug)] /*__ATLAS_DERIVE_${deriveID++}__*/\n`, 0);
  });
  walk(tree.topNode, fn => {
    if (!["FunctionItem", "ClosureExpression"].includes(fn.name)) return;
    // Closures matter for fold/map/filter algorithms too: show their actual
    // arguments and accumulator rather than turning them into a single jump.
    for (let parent = fn.parent; parent; parent = parent.parent) if (parent.name === "FunctionItem" && ["csv", "semicolon"].includes(text(parent.getChild("BoundIdentifier")!))) return;
    const closure = fn.name === "ClosureExpression";
    const body = closure ? children(fn).at(-1) : fn.getChild("Block"), nameNode = fn.getChild("BoundIdentifier");
    if (!body || (!closure && !nameNode)) return;
    const name = closure ? `closure · line ${source.slice(0, fn.from).split("\n").length}` : text(nameNode!);
    if (["csv", "semicolon"].includes(name) || children(fn).some(n => ["const", "async"].includes(n.name))) return;
    const fnID = sites.length;
    const checkpoint = (at: number, scope: Set<string>, statement: string, edge?: { collection: string; from: string; to: string }) => {
      const site = sites.length;
      sites.push({ line: source.slice(0, at).split("\n").length, function: name, statement: statement.trim(), ...(edge ? { edge } : {}) });
      let probe = `\n{ let mut __atlas_values = Vec::<(&str,String,&str)>::new();\n`;
      for (const variable of scope) {
        const id = String(captureID++); captures[id] = variable;
        probe += `__atlas_values.push((${JSON.stringify(variable)}, format!("{:?}", &${variable}), std::any::type_name_of_val(&${variable}))); /*__ATLAS_CAPTURE_${id}__*/\n`;
      }
      probe += `${helper}::point(${site}, &__atlas_values); }\n`;
      add(at, probe);
    };
    const descend = (node: SyntaxNode, inherited: Set<string>) => {
      if (["FunctionItem", "ClosureExpression", "MacroInvocation", "ConstBlock"].includes(node.name)) return;
      if (node.name === "Block") { block(node, inherited); return; }
      const nested = new Set(inherited);
      // Bindings from for/while-let/match patterns exist only in that branch.
      for (const child of children(node)) if (child.name !== "Block") for (const b of bindings(child)) nested.add(b);
      for (const child of children(node)) descend(child, nested);
    };
    const block = (node: SyntaxNode, inherited: Set<string>) => {
      const scope = new Set(inherited);
      let edge: { collection: string; from: string; to: string } | undefined;
      for (let parent = node.parent; parent && parent !== fn; parent = parent.parent) {
        if (parent.name !== "ForExpression") continue;
        const header = text(parent).split("{")[0].replace(/\s+/g, " ");
        const match = header.match(/^for (.+?) in &?\s*(\w+)\[(\w+)\]/);
        const to = match?.[1].match(/\b(?!mut\b|ref\b)[a-zA-Z_]\w*/)?.[0];
        if (match && to) { edge = { collection: match[2], from: match[3], to }; break; }
      }
      const statements = children(node).filter(c => !["{", "}", "LineComment", "BlockComment", "InnerAttribute"].includes(c.name));
      for (const statement of statements) {
        if (/Item$|Declaration$/.test(statement.name) && statement.name !== "LetDeclaration") continue;
        checkpoint(statement.from, scope, text(statement).split("\n")[0], edge);
        for (const child of children(statement)) descend(child, scope);
        if (statement.name === "LetDeclaration") {
          const eq = children(statement).find(c => c.name === "=");
          if (eq) for (const child of children(statement).filter(c => c.to <= eq.from)) for (const b of bindings(child)) scope.add(b);
        }
      }
      const last = statements.at(-1);
      if (!last || (text(last).trimEnd().endsWith(";") && !/^(?:return|break|continue)\b/.test(text(last).trimStart()))) checkpoint(node.to - 1, scope, "}", edge);
    };
    const scope = new Set<string>();
    for (const p of fn.getChild("ParamList")?.getChildren("Parameter") ?? []) for (const b of bindings(p)) scope.add(b);
    if (closure) {
      // Include captured collections as well as closure arguments: e.g. the
      // seen set in Iterator::any or the DP table inside Iterator::map.
      for (let parent = fn.parent; parent; parent = parent.parent) {
        if (["FunctionItem", "ClosureExpression"].includes(parent.name)) {
          for (const p of parent.getChild("ParamList")?.getChildren("Parameter") ?? []) for (const b of bindings(p)) scope.add(b);
        }
        if (parent.name === "Block") for (const statement of children(parent)) {
          if (statement.name !== "LetDeclaration" || statement.to > fn.from) continue;
          const eq = children(statement).find(c => c.name === "=");
          if (eq) for (const part of children(statement).filter(c => c.to <= eq.from)) for (const b of bindings(part)) scope.add(b);
        }
        if (["ForExpression", "WhileExpression", "IfExpression", "MatchArm"].includes(parent.name)) {
          for (const part of children(parent).filter(c => c.name !== "Block" && c.to <= fn.from)) for (const b of bindings(part)) scope.add(b);
        }
      }
    }
    const guard = `\nlet __atlas_frame_${fnID} = ${helper}::Frame::enter(${JSON.stringify(name)});\n`;
    if (body.name === "Block") {
      add(body.from + 1, guard, 0);
      block(body, scope);
    } else {
      add(body.from, "{" + guard, 0);
      checkpoint(body.from, scope, text(body).split("\n")[0]);
      add(body.to, "}", 20);
    }
  });
  let transformed = "", cursor = 0;
  for (const [at, values] of [...edits].sort((a, b) => a[0] - b[0])) {
    transformed += source.slice(cursor, at) + values.sort((a, b) => a.priority - b.priority).map(v => v.text).join(""); cursor = at;
  }
  transformed += source.slice(cursor) + rustHelper;
  return { source, transformed, sites, captures };
}

const rustHelper = `
mod __crabrix_atlas {
    use std::cell::RefCell;
    thread_local! { static STACK: RefCell<Vec<(&'static str,usize)>> = const {RefCell::new(Vec::new())}; static SERIAL: RefCell<usize> = const {RefCell::new(0)}; static COUNT: RefCell<usize> = const {RefCell::new(0)}; }
    pub struct Frame;
    impl Frame { pub fn enter(name:&'static str)->Self { let serial=SERIAL.with(|s|{let mut s=s.borrow_mut();*s+=1;*s}); STACK.with(|s|s.borrow_mut().push((name,serial))); Self } }
    impl Drop for Frame { fn drop(&mut self) { STACK.with(|s|{s.borrow_mut().pop();}); } }
    fn quote(s:&str)->String { let mut out=String::from("\\\""); for c in s.chars() { match c { '"'=>out.push_str("\\\\\\\""), '\\\\'=>out.push_str("\\\\\\\\"), '\\n'=>out.push_str("\\\\n"), '\\r'=>out.push_str("\\\\r"), '\\t'=>out.push_str("\\\\t"), c if (c as u32)<32=>out.push_str(&format!("\\\\u{:04x}",c as u32)), c=>out.push(c) } } out.push('"');out }
    pub fn point(site:usize, values:&[(&str,String,&str)]) {
        COUNT.with(|s|{let mut s=s.borrow_mut();*s+=1;assert!(*s<=50000,"Atlas trace exceeds 50000 steps");});
        let locals=values.iter().map(|(n,v,t)|format!("[{}, {}, {}]",quote(n),quote(v),quote(t))).collect::<Vec<_>>().join(",");
        let stack=STACK.with(|s|s.borrow().iter().map(|(n,i)|format!("[{},{}]",quote(n),i)).collect::<Vec<_>>().join(","));
        eprintln!("__CRABRIX_ATLAS__{{\\\"site\\\":{},\\\"locals\\\":[{}],\\\"stack\\\":[{}]}}",site,locals,stack);
    }
}
`;

const destination = resolve(process.argv[2] ?? "../build/algorithm-atlas/plans");
mkdirSync(destination, { recursive: true });
const snapshot = JSON.parse(readFileSync("content/courses.json", "utf8"));
const course = snapshot.courses.find((c: { id: string }) => c.id === "algorithms");
const entries = new Map<string, Record<string, unknown>>();
const lessons: Record<string, string> = {};
for (const unit of course.units) for (const lesson of unit.lessons) {
  const source = lesson.writing.exampleCode;
  const hash = createHash("sha256").update(source).digest("hex");
  const key = `${lesson.algorithm.patternID}-${hash.slice(0, 16)}`;
  lessons[lesson.id] = key;
  if (!entries.has(key)) entries.set(key, { key, sourceHash: hash, pattern: lesson.algorithm.patternID, category: lesson.algorithm.categoryID, title: lesson.title.replace(/ — .*/, ""), idea: lesson.algorithm.idea, complexity: lesson.algorithm.complexity, ...plan(source) });
}
// Independent public example. Full lesson fixtures keep their existing access gate.
const demo = 'fn first_negative(values: &[i32]) -> i32 {\n    for (i, &value) in values.iter().enumerate() {\n        if value < 0 {\n            return i as i32;\n        }\n    }\n    -1\n}\n\nfn main() {\n    let values = [6, 2, 8, -1, 4];\n    let result = first_negative(&values);\n    println!("{result}");\n}\n';
entries.set("demo-linear-scan", { key: "demo-linear-scan", sourceHash: createHash("sha256").update(demo).digest("hex"), pattern: "linear-scan", category: "scans", title: "Find the first negative number", idea: "Inspect each element in order. Stop as soon as a value is negative; return its index, or −1 if there is no match.", complexity: "O(n) time · O(1) extra space", ...plan(demo) });
for (const [key, entry] of entries) writeFileSync(resolve(destination, `${key}.json`), JSON.stringify(entry));
writeFileSync(resolve(destination, "manifest.json"), JSON.stringify({ version: 1, lessons, keys: [...entries.keys()] }, null, 2) + "\n");
console.log(`Planned ${entries.size} examples for ${Object.keys(lessons).length} lessons.`);
