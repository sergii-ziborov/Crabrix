import { parser } from "@lezer/rust";
import type { SyntaxNode } from "@lezer/common";

// Shared by the browser compiler Worker and the app's fixed JavaScriptCore
// parser. This is a separate Rust build, never an evaluator of Rust in JS.
export const debugImport = "__crabrix_debug_checkpoint_v1";
export type DebugSite = { id: number; file: string; line: number; column: number; function: string; functionID: number; kind: "entry" | "statement" };
export type DebugPlan = { version: 1; files: Record<string, string>; sites: DebugSite[]; notes: string[] };
const helperName = "__crabrix_debug_v1";
const primitives = /^(?:[iu](?:8|16|32|64|128|size)|f(?:32|64)|bool|char)$/;
const scalarNodes = new Set(["Integer", "Float", "Boolean", "Char", "Character"]);
const formattingMacros = new Set(["print", "println", "eprint", "eprintln", "format", "format_args", "dbg", "assert", "assert_eq", "assert_ne", "debug_assert", "debug_assert_eq", "debug_assert_ne"]);
function children(node: SyntaxNode): SyntaxNode[] { const result: SyntaxNode[] = []; for (let child = node.firstChild; child; child = child.nextSibling) result.push(child); return result; }
function walk(node: SyntaxNode, visit: (node: SyntaxNode) => boolean | void) { if (visit(node) === false) return; for (let child = node.firstChild; child; child = child.nextSibling) walk(child, visit); }

export function instrumentRust(files: Record<string, string>, entryFile: string): DebugPlan {
  const paths = Object.keys(files).filter(path => path.endsWith(".rs")).sort();
  if (!paths.includes(entryFile) || paths.length > 256 || paths.reduce((n, p) => n + files[p].length, 0) > 4 * 1024 * 1024) throw new Error("Debug supports an editable Rust entry and up to 256 source files / 4 MiB.");
  const sites: DebugSite[] = [], output = { ...files };
  const notes = ["Source-instrumented Rust: breakpoints and stepping use the actual compiled program.", "Locals show safe primitive values. Aggregates, borrowed/captured locals, async bodies and macro expansions are not decoded or stepped internally."];
  for (const file of paths) {
    const source = files[file];
    if (/\b__crabrix_debug_(?:v1|guard_)/.test(source)) throw new Error("The __crabrix_debug_ prefix is reserved by the Debug build.");
    const tree = parser.parse(source);
    const edits = new Map<number, { priority: number; text: string }[]>();
    const add = (position: number, text: string, priority = 10) => { const list = edits.get(position) ?? []; list.push({ priority, text }); edits.set(position, list); };
    const text = (node: SyntaxNode) => source.slice(node.from, node.to);
    const lineStarts = [0]; for (let i = 0; i < source.length; i++) if (source[i] === "\n") lineStarts.push(i + 1);
    const location = (offset: number) => { let lo = 0, hi = lineStarts.length; while (lo + 1 < hi) { const mid = (lo + hi) >> 1; if (lineStarts[mid] <= offset) lo = mid; else hi = mid; } return { line: lo + 1, column: offset - lineStarts[lo] + 1 }; };
    const site = (offset: number, name: string, functionID: number, kind: DebugSite["kind"]) => { if (sites.length >= 8192) throw new Error("Debug source exceeds 8,192 executable locations."); const id = sites.length + 1; sites.push({ id, file, ...location(offset), function: name, functionID: functionID || id, kind }); return id; };
    walk(tree.topNode, node => {
      if (node.type.isError) throw new Error(`Debug cannot safely instrument this syntax at ${file}:${location(node.from).line}. Use normal Run for this source.`);
      if (node.name === "InnerAttribute" && /\bno_std\b/.test(text(node))) throw new Error("Source Debug currently requires the Rust standard library.");
      if (node.name === "Identifier" && node.nextSibling?.name === "!" && ["column", "include", "include_str", "include_bytes"].includes(text(node))) throw new Error(`Debug leaves compile-time source introspection to normal Run (${file}:${location(node.from).line}).`);
      if (node.name === "MacroInvocation" && ["column", "include", "include_str", "include_bytes"].includes(text(node.getChild("Identifier") ?? node))) throw new Error(`Debug leaves compile-time source introspection to normal Run (${file}:${location(node.from).line}).`);
    });
    const functions: SyntaxNode[] = [];
    walk(tree.topNode, node => { if (node.name === "FunctionItem") functions.push(node); });
    for (const fn of functions) {
      const parts = children(fn), body = fn.getChild("Block"); if (!body) continue;
      // Const functions must remain usable in constant evaluation. Async guards
      // span suspended futures and would misrepresent the running call stack.
      if (parts.some(n => n.name === "const" || n.name === "async")) continue;
      const name = text(fn.getChild("BoundIdentifier") ?? fn), functionID = site(fn.from, name, 0, "entry");
      const guard = `__crabrix_debug_guard_${functionID}`;
      const unavailable = new Set<string>();
      const disableIdentifiers = (node: SyntaxNode) => walk(node, n => { if (n.name === "Identifier") unavailable.add(text(n)); });
      walk(body, node => {
        if (node.name === "FunctionItem") return false;
        if (node.name === "ReferenceExpression" || node.name === "ClosureExpression") { disableIdentifiers(node); return false; }
        if (node.name === "MacroInvocation" && !formattingMacros.has(text(node.getChild("Identifier") ?? node))) { disableIdentifiers(node); return false; }
        if (/Attribute/.test(node.name) && node.name !== "InnerAttribute") throw new Error(`Debug does not rewrite statement attributes (${file}:${location(node.from).line}). Normal Run remains available.`);
      });
      type Environment = Map<string, boolean>;
      const env: Environment = new Map();
      for (const parameter of fn.getChild("ParamList")?.getChildren("Parameter") ?? []) {
        const binding = parameter.getChild("BoundIdentifier"), type = parameter.getChild("TypeIdentifier");
        if (binding) env.set(text(binding), !!type && primitives.test(text(type)) && !unavailable.has(text(binding)));
      }
      const safe = (node: SyntaxNode | undefined, scope: Environment): boolean => {
        if (!node) return false;
        if (scalarNodes.has(node.name)) return true;
        if (node.name === "Identifier") return scope.get(text(node)) === true;
        if (["BinaryExpression", "UnaryExpression", "ParenthesizedExpression", "CastExpression"].includes(node.name)) {
          const values = children(node).filter(n => /Expression$/.test(n.name) || n.name === "Identifier" || scalarNodes.has(n.name));
          return values.length > 0 && values.every(n => safe(n, scope));
        }
        return false;
      };
      const checkpoint = (offset: number, scope: Environment) => {
        const id = site(offset, name, functionID, "statement");
        const variables = [...scope].filter(([variable, enabled]) => enabled && !unavailable.has(variable)).slice(-32).map(([variable]) => `(${JSON.stringify(variable)}, &${variable} as &dyn ::std::fmt::Debug, ::std::any::type_name_of_val(&${variable}))`).join(",");
        add(offset, `crate::${helperName}::point(${id}, &[${variables}]);`);
      };
      const descend = (node: SyntaxNode, scope: Environment) => {
        if (node.name === "FunctionItem" || node.name === "ClosureExpression" || node.name === "MacroInvocation" || node.name === "ConstBlock") return;
        if (node.name === "Block") { block(node, scope); return; }
        const nested = new Map(scope);
        // Pattern bindings in for/if-let/match arms shadow outer names, even
        // when their type cannot be inspected safely.
        for (const child of children(node)) if (child.name !== "Block") walk(child, n => { if (n.name === "Block" || n.name === "FunctionItem" || n.name === "ClosureExpression") return false; if (n.name === "BoundIdentifier") nested.set(text(n), false); });
        if (node.name === "ForExpression") {
          const binding = node.getChild("BoundIdentifier"), range = node.getChild("RangeExpression");
          if (binding && range) {
            const values = children(range).filter(n => n.name === "Integer" || n.name === "Identifier");
            if (values.length === 2 && values.every(n => safe(n, scope))) nested.set(text(binding), !unavailable.has(text(binding)));
          }
        }
        for (const child of children(node)) descend(child, nested);
      };
      const block = (node: SyntaxNode, inherited: Environment) => {
        const scope = new Map(inherited), statements = children(node).filter(n => !["{", "}", "LineComment", "BlockComment", "InnerAttribute"].includes(n.name));
        for (const statement of statements) {
          if (/Item$|Declaration$/.test(statement.name) && statement.name !== "LetDeclaration") continue;
          checkpoint(statement.from, scope);
          descendStatement(statement, scope);
          if (statement.name === "LetDeclaration") {
            const bindings: string[] = []; walk(statement, n => { if (n.name === "BoundIdentifier") bindings.push(text(n)); if (n.name === "Block" || n.name === "ClosureExpression") return false; });
            const pieces = children(statement), equal = pieces.findIndex(n => n.name === "=");
            const binding = statement.getChild("BoundIdentifier"), type = statement.getChild("TypeIdentifier");
            const enabled = equal >= 0 && !!binding && bindings.length === 1 && !unavailable.has(text(binding)) && (type ? primitives.test(text(type)) : safe(pieces[equal + 1], scope));
            for (const variable of bindings) scope.set(variable, enabled && variable === (binding ? text(binding) : ""));
          }
        }
        const last = statements.at(-1);
        if (!last || last.name === "LetDeclaration" || /Item$/.test(last.name) || text(last).trimEnd().endsWith(";")) checkpoint(node.to - 1, scope);
      };
      const descendStatement = (node: SyntaxNode, scope: Environment) => { for (const child of children(node)) descend(child, scope); };
      const first = children(body).find(n => !["{", "}", "LineComment", "BlockComment", "InnerAttribute"].includes(n.name));
      add(first?.from ?? body.to - 1, `let ${guard} = crate::${helperName}::Frame::enter(${functionID});`, 0);
      block(body, env);
    }
    const chunks: string[] = []; let cursor = 0;
    for (const [position, insertions] of [...edits].sort((a, b) => a[0] - b[0])) {
      chunks.push(source.slice(cursor, position), insertions.sort((a, b) => a.priority - b.priority).map(v => v.text).join("")); cursor = position;
    }
    chunks.push(source.slice(cursor)); let transformed = chunks.join("");
    // Each Cargo crate root gets its own helper; module files resolve crate::
    // through that root. Other dependency crates are left untouched.
    if (file === entryFile || /(?:^|\/)(?:main|lib)\.rs$/.test(file)) transformed += "\n" + rustHelper;
    if (transformed.length > 8 * 1024 * 1024) throw new Error("Debug instrumentation exceeds its generated-source limit.");
    output[file] = transformed;
  }
  if (!sites.some(site => site.kind === "statement")) throw new Error("No synchronous Rust function body is available to debug. Const/async bodies are not instrumented.");
  return { version: 1, files: output, sites, notes };
}

const rustHelper = `
#[doc(hidden)] #[allow(dead_code)] mod ${helperName} {
    unsafe extern "C" { fn ${debugImport}(kind:u32, site:u32, ptr:*const u8, len:u32); }
    pub struct Frame { site:u32 }
    impl Frame { pub fn enter(site:u32)->Self { unsafe { ${debugImport}(1,site,::std::ptr::null(),0); } Self{site} } }
    impl Drop for Frame { fn drop(&mut self) { unsafe { ${debugImport}(3,self.site,::std::ptr::null(),0); } } }
    fn quote(out:&mut ::std::string::String, value:&str) {
        out.push('"');
        for c in value.chars().take(256) { match c {
            '"' => out.push_str("\\\\\\\""), '\\\\' => out.push_str("\\\\\\\\"),
            c if (c as u32)<32 => { use ::std::fmt::Write; let _=write!(out,"\\\\u{:04x}",c as u32); },
            c => out.push(c)
        } } out.push('"');
    }
    pub fn point(site:u32, values:&[(&str,&dyn ::std::fmt::Debug,&str)]) {
        let mut out=::std::string::String::from("[");
        for (i,(name,value,ty)) in values.iter().enumerate().take(32) {
            if i>0 {out.push(',');} out.push('['); quote(&mut out,name); out.push(','); quote(&mut out,ty); out.push(',');
            quote(&mut out,&::std::format!("{:?}",value)); out.push(']');
        } out.push(']');
        unsafe { ${debugImport}(2,site,out.as_ptr(),out.len() as u32); }
    }
}
`;
