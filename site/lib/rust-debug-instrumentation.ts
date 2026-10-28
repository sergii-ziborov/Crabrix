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
function resourceLiteral(value: string): string | undefined {
  const raw = value.match(/^r(#+)?"([\s\S]*)"\1$/); if (raw) return raw[2];
  if (!value.startsWith('"') || !value.endsWith('"')) return;
  let result = "";
  for (let i = 1; i < value.length - 1; i++) {
    if (value[i] !== "\\") { result += value[i]; continue; }
    const escape = value[++i], simple: Record<string, string> = { n: "\n", r: "\r", t: "\t", "0": "\0", "\\": "\\", '"': '"', "'": "'" };
    if (Object.hasOwn(simple, escape)) result += simple[escape];
    else if (escape === "x" && /^[0-9a-f]{2}$/i.test(value.slice(i + 1, i + 3))) { result += String.fromCharCode(parseInt(value.slice(i + 1, i + 3), 16)); i += 2; }
    else if (escape === "u" && value[i + 1] === "{") {
      const end = value.indexOf("}", i + 2), hex = value.slice(i + 2, end).replaceAll("_", "");
      if (end < 0 || !/^[0-9a-f]{1,6}$/i.test(hex)) return;
      const point = parseInt(hex, 16); if (point > 0x10ffff || point >= 0xd800 && point <= 0xdfff) return;
      result += String.fromCodePoint(point); i = end;
    } else if (escape === "\n" || escape === "\r" && value[i + 1] === "\n") { while (/\s/.test(value[i + 1] ?? "") && i + 1 < value.length - 1) i++; }
    else return;
  }
  return result;
}

export function instrumentRust(files: Record<string, string>, entryFile: string, excludedRustFiles: string[] = []): DebugPlan {
  const paths = Object.keys(files).filter(path => path.endsWith(".rs") && !excludedRustFiles.includes(path)).sort();
  if (!paths.includes(entryFile) || paths.length > 256 || paths.reduce((n, p) => n + files[p].length, 0) > 4 * 1024 * 1024) throw new Error("Debug supports an editable Rust entry and up to 256 source files / 4 MiB.");
  const sites: DebugSite[] = [], output = { ...files };
  let resourceCopyUnits = 0;
  const notes = ["Source-instrumented Rust: breakpoints and stepping use the actual compiled program.", "Locals include bounded String, Vec and local struct previews without calling user Debug implementations. Borrowed, moved and captured values may be omitted. Async stacks show active polls; const bodies and macro expansions are not stepped internally."];
  for (const file of paths) {
    const source = files[file];
    if (/\b__crabrix_debug_(?:v1|guard_)/.test(source)) throw new Error("The __crabrix_debug_ prefix is reserved by the Debug build.");
    const tree = parser.parse(source);
    const resourceMacros = new Set<number>();
    const edits = new Map<number, { priority: number; text: string }[]>();
    const replacements: { from: number; to: number; text: string }[] = [];
    const resourceAliases = new Map<string, string>();
    const add = (position: number, text: string, priority = 10) => { const list = edits.get(position) ?? []; list.push({ priority, text }); edits.set(position, list); };
    const text = (node: SyntaxNode) => source.slice(node.from, node.to);
    const lineStarts = [0]; for (let i = 0; i < source.length; i++) if (source[i] === "\n") lineStarts.push(i + 1);
    const location = (offset: number) => { let lo = 0, hi = lineStarts.length; while (lo + 1 < hi) { const mid = (lo + hi) >> 1; if (lineStarts[mid] <= offset) lo = mid; else hi = mid; } return { line: lo + 1, column: offset - lineStarts[lo] + 1 }; };
    const site = (offset: number, name: string, functionID: number, kind: DebugSite["kind"]) => { if (sites.length >= 8192) throw new Error("Debug source exceeds 8,192 executable locations."); const id = sites.length + 1; sites.push({ id, file, ...location(offset), function: name, functionID: functionID || id, kind }); return id; };
    walk(tree.topNode, node => {
      if (node.type.isError) throw new Error(`Debug cannot safely instrument this syntax at ${file}:${location(node.from).line}. Use normal Run for this source.`);
      if (node.name === "InnerAttribute" && /\bno_std\b/.test(text(node))) throw new Error("Source Debug currently requires the Rust standard library.");
      const macroName = node.name === "Identifier" ? text(node) : "";
      const invocation = node.nextSibling?.name === "!" ? node : node.parent?.name === "ScopedIdentifier" && node.parent.nextSibling?.name === "!" && node.parent.lastChild?.from === node.from ? node.parent : undefined;
      if (invocation && ["column", "include"].includes(macroName)) throw new Error(`Debug leaves compile-time source introspection to normal Run (${file}:${location(node.from).line}).`);
      if (node.name === "MacroInvocation" && ["column", "include"].includes(text(node.getChild("Identifier") ?? node))) throw new Error(`Debug leaves compile-time source introspection to normal Run (${file}:${location(node.from).line}).`);
      // These macros load resources, not executable Rust. Leave HTML/CSS/JS
      // untouched. If Rust source is included as data (even this very file),
      // redirect the literal to an original sidecar so it cannot observe the
      // instrumented snapshot. Token nodes cover includes inside println! too.
      if (!invocation || !["include_str", "include_bytes"].includes(macroName) || resourceMacros.has(node.from)) return;
      resourceMacros.add(node.from);
      const group = invocation.nextSibling?.nextSibling;
      if (!group || !/Tokens$/.test(group.name)) return;
      const argument = text(group).slice(1, -1).trim().replace(/,\s*$/, "").trim();
      const resourcePath = resourceLiteral(argument);
      if (typeof resourcePath !== "string") throw new Error(`Debug needs a literal resource path for ${text(node)}! (${file}:${location(node.from).line}).`);
      if (resourcePath.startsWith("/") && !resourcePath.startsWith("/work/")) return;
      const absolute = resourcePath.startsWith("/work/");
      const parts = absolute ? [] : file.split("/").slice(0, -1);
      let outside = false;
      for (const part of (absolute ? resourcePath.slice(6) : resourcePath).split("/")) { if (!part || part === ".") continue; if (part === "..") { if (!parts.length) outside = true; parts.pop(); } else parts.push(part); }
      if (outside) return;
      const target = parts.join("/");
      if (!paths.includes(target)) return;
      const directory = file.split("/").slice(0, -1).join("/");
      let alias = resourceAliases.get(target);
      if (!alias) {
        alias = `__crabrix_debug_original_${resourceMacros.size}.txt`;
        while (Object.hasOwn(output, directory ? `${directory}/${alias}` : alias)) alias = "_" + alias;
        resourceCopyUnits += files[target].length;
        if (resourceCopyUnits > 8 * 1024 * 1024) throw new Error("Debug original-resource snapshots exceed their preparation limit.");
        output[directory ? `${directory}/${alias}` : alias] = files[target];
        resourceAliases.set(target, alias);
      }
      const literal = JSON.stringify(alias);
      const start = group.from + 1 + text(group).slice(1, -1).indexOf(argument);
      replacements.push({ from: start, to: start + argument.length, text: literal + "\n".repeat((argument.match(/\n/g) ?? []).length) });
    });
    // Implement inspection beside each concrete struct so private fields remain
    // accessible. Never take references to packed or conditionally absent fields.
    walk(tree.topNode, node => {
      if (node.name !== "StructItem" || node.getChild("TypeParamList")) return;
      let attrs = "";
      for (let n = node.parent; n?.name === "AttributeItem"; n = n.parent) attrs += n.getChildren("Attribute").map(text).join("");
      if (/packed|cfg_attr/.test(attrs)) return;
      const list = node.getChild("FieldDeclarationList") ?? node.getChild("OrderedFieldDeclarationList");
      if (list && /#/.test(text(list))) return;
      const fields = list?.name === "FieldDeclarationList" ? list.getChildren("FieldDeclaration").map(n => text(n.getChild("FieldIdentifier")!))
        : list ? children(list).filter(n => !["(", ")", ",", "Vis"].includes(n.name)).map((_, i) => String(i)) : [];
      const name = text(node.getChild("TypeIdentifier")!);
      const cfg = attrs.match(/#\[cfg\([^\n]*?\)\]/g)?.join("") ?? "";
      add(node.to, `${cfg} impl crate::${helperName}::Value for ${name} {fn view(&self,s:&mut crate::${helperName}::Sink,d:usize){ use crate::${helperName}::Inspect as _; if d>=4 {s.push("…");return;} s.push(${JSON.stringify(name + " { ")}); ${fields.slice(0,16).map((f,i)=>`s.push(${JSON.stringify((i ? ", " : "") + f + ": ")}); (&crate::${helperName}::Probe(&self.${f})).inspect(s,d+1);`).join("")} ${fields.length>16 ? 's.push(", …");' : ''} s.push(" }");}}`, 30);
    });
    const functions: SyntaxNode[] = [];
    walk(tree.topNode, node => { if (node.name === "FunctionItem" || node.name === "AsyncBlock") functions.push(node); });
    for (const fn of functions) {
      const parts = children(fn), body = fn.getChild("Block"); if (!body) continue;
      // Enter/leave async frames per poll, never for a suspended future's lifetime.
      let constant = parts.some(n => n.name === "const");
      for (let n = fn.parent; n; n = n.parent) if (n.name === "ConstBlock" || n.name === "ConstItem" || n.name === "FunctionItem" && children(n).some(n => n.name === "const")) constant = true;
      if (constant) continue;
      const asynchronous = fn.name === "AsyncBlock" || parts.some(n => n.name === "async");
      const name = fn.name === "AsyncBlock" ? "async block" : text(fn.getChild("BoundIdentifier") ?? fn), functionID = site(fn.from, name, 0, "entry");
      const guard = `__crabrix_debug_guard_${functionID}`;
      const unavailable = new Set<string>();
      const disableIdentifiers = (node: SyntaxNode) => walk(node, n => { if (n.name === "Identifier") unavailable.add(text(n)); });
      walk(body, node => {
        if (node.name === "FunctionItem") return false;
        if (node.name === "ReferenceExpression" || node.name === "ClosureExpression" || node.name === "AsyncBlock") { disableIdentifiers(node); return false; }
        if (node.name === "MacroInvocation" && !formattingMacros.has(text(node.getChild("Identifier") ?? node))) { disableIdentifiers(node); return false; }
        if (/Attribute/.test(node.name) && node.name !== "InnerAttribute") throw new Error(`Debug does not rewrite statement attributes (${file}:${location(node.from).line}). Normal Run remains available.`);
      });
      type Environment = Map<string, boolean | "owned">;
      const env: Environment = new Map();
      const containers = new Set<string>(), ownershipUses = new Set<string>();
      const containerType = (value: string) => /^(?:(?:std|alloc)::(?:string|vec)::)?(?:String|Vec)(?:$|<|::)/.test(value.replace(/\s/g,""));
      walk(fn, n => {
        if (n !== fn && (n.name === "FunctionItem" || n.name === "ClosureExpression" || n.name === "AsyncBlock")) return false;
        if (n.name === "LetDeclaration" || n.name === "Parameter") {
          const binding = n.getChild("BoundIdentifier");
          if (binding && children(n).some(part => containerType(text(part)))) containers.add(text(binding));
          if (binding && /(?:=\s*vec!|=\s*(?:String|Vec)::)/.test(text(n))) containers.add(text(binding));
        }
      });
      walk(body, n => {
        if (n.name === "FunctionItem") return false;
        if (n.name === "MacroInvocation") return false; // handled conservatively above
        if (n.name !== "Identifier") return;
        const parent = n.parent;
        // Only known standard containers get the non-consuming method whitelist.
        const method = parent?.name === "FieldExpression" && parent.firstChild?.from === n.from && parent.parent?.name === "CallExpression" ? parent.getChild("FieldIdentifier") : null;
        if (containers.has(text(n)) && method && /^(?:len|capacity|is_empty|push|push_str|pop|clear|reserve|reserve_exact|shrink_to_fit|truncate|insert|remove|swap_remove|retain|sort|sort_unstable|reverse|dedup)$/.test(text(method))) return;
        ownershipUses.add(text(n));
      });
      for (const parameter of fn.getChild("ParamList")?.getChildren("Parameter") ?? []) {
        const binding = parameter.getChild("BoundIdentifier"), type = parameter.getChild("TypeIdentifier");
        if (binding) env.set(text(binding), !!type && primitives.test(text(type)) ? true : "owned");
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
        const variables = [...scope].filter(([variable, enabled]) => enabled && !unavailable.has(variable) && (enabled !== "owned" || !ownershipUses.has(variable))).slice(-32).map(([variable]) => `(${JSON.stringify(variable)}, crate::${helperName}::preview(&${variable}, |s| {use crate::${helperName}::Inspect as _; (&crate::${helperName}::Probe(&${variable})).inspect(s,0);}), ::std::any::type_name_of_val(&${variable}))`).join(",");
        add(offset, `crate::${helperName}::point(${id}, &[${variables}]);`);
      };
      const descend = (node: SyntaxNode, scope: Environment) => {
        if (node.name === "FunctionItem" || node.name === "ClosureExpression" || node.name === "AsyncBlock" || node.name === "MacroInvocation" || node.name === "ConstBlock") return;
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
            const enabled = equal >= 0 && !!binding && bindings.length === 1 && !unavailable.has(text(binding)) ? (type ? primitives.test(text(type)) : safe(pieces[equal + 1], scope)) ? true : "owned" : false;
            for (const variable of bindings) scope.set(variable, variable === (binding ? text(binding) : "") ? enabled : false);
          }
        }
        const last = statements.at(-1);
        if (!last || last.name === "LetDeclaration" || /Item$/.test(last.name) || text(last).trimEnd().endsWith(";")) checkpoint(node.to - 1, scope);
      };
      const descendStatement = (node: SyntaxNode, scope: Environment) => { for (const child of children(node)) descend(child, scope); };
      const first = children(body).find(n => !["{", "}", "LineComment", "BlockComment", "InnerAttribute"].includes(n.name));
      if (asynchronous) {
        if (fn.name === "AsyncBlock") {
          add(fn.from, `crate::${helperName}::poll_frame(${functionID},`, 20);
          add(fn.to, ")", 0);
        } else {
          add(first?.from ?? body.to - 1, `crate::${helperName}::poll_frame(${functionID}, async move {`, 0);
          add(body.to - 1, "}).await", 20);
        }
      } else add(first?.from ?? body.to - 1, `let ${guard} = crate::${helperName}::Frame::enter(${functionID});`, 0);
      block(body, env);
    }
    for (const replacement of replacements) { add(replacement.from, replacement.text, 0); add(replacement.to, "", -1); }
    const chunks: string[] = []; let cursor = 0;
    for (const [position, insertions] of [...edits].sort((a, b) => a[0] - b[0])) {
      if (position < cursor) continue;
      chunks.push(source.slice(cursor, position), insertions.sort((a, b) => a.priority - b.priority).map(v => v.text).join(""));
      cursor = replacements.find(r => r.from === position)?.to ?? position;
    }
    chunks.push(source.slice(cursor)); let transformed = chunks.join("");
    // Each Cargo crate root gets its own helper; module files resolve crate::
    // through that root. Other dependency crates are left untouched.
    if (file === entryFile || /(?:^|\/)(?:main|lib)\.rs$/.test(file)) transformed += "\n" + rustHelper;
    if (transformed.length > 8 * 1024 * 1024) throw new Error("Debug instrumentation exceeds its generated-source limit.");
    output[file] = transformed;
  }
  if (!sites.some(site => site.kind === "statement")) throw new Error("No Rust function body is available to debug. Const bodies are not instrumented.");
  return { version: 1, files: output, sites, notes };
}


const rustHelper = String.raw`
#[doc(hidden)] #[allow(dead_code)] mod ${helperName} {
    unsafe extern "C" { fn ${debugImport}(kind:u32, site:u32, ptr:*const u8, len:u32); }
    pub struct Frame { site:u32 }
    impl Frame { pub fn enter(site:u32)->Self { unsafe { ${debugImport}(1,site,::std::ptr::null(),0); } Self{site} } }
    impl Drop for Frame { fn drop(&mut self) { unsafe { ${debugImport}(3,self.site,::std::ptr::null(),0); } } }
    pub struct PollFrame<F> { inner:F, site:u32 }
    pub fn poll_frame<F: ::std::future::Future>(site:u32,inner:F)->PollFrame<F>{PollFrame{inner,site}}
    impl<F: ::std::future::Future> ::std::future::Future for PollFrame<F> {
        type Output=F::Output;
        fn poll(self: ::std::pin::Pin<&mut Self>,cx:&mut ::std::task::Context<'_>)->::std::task::Poll<Self::Output>{
            // SAFETY: inner is structurally pinned. It is never moved by this
            // wrapper, which has no Drop implementation or unpin projection.
            let this=unsafe{self.get_unchecked_mut()};
            let _frame=Frame::enter(this.site);
            unsafe{::std::pin::Pin::new_unchecked(&mut this.inner)}.poll(cx)
        }
    }
    pub struct Sink { text: ::std::string::String, clipped:bool }
    impl Sink {
        pub fn push(&mut self,text:&str){ use ::std::fmt::Write; let _=self.write_str(text); }
    }
    impl ::std::fmt::Write for Sink {
        fn write_str(&mut self,text:&str)->::std::fmt::Result {
            let remaining=256usize.saturating_sub(self.text.len());
            if text.len()<=remaining {self.text.push_str(text);return Ok(());}
            let mut end=remaining.min(text.len());while !text.is_char_boundary(end){end-=1;}
            self.text.push_str(&text[..end]);self.clipped=true;Err(::std::fmt::Error)
        }
    }
    pub trait Value {fn view(&self,s:&mut Sink,d:usize);}
    pub struct Probe<'a,T:?Sized>(pub &'a T);
    pub trait Inspect {fn inspect(self,s:&mut Sink,d:usize);}
    impl<T:Value+?Sized> Inspect for &Probe<'_,T>{fn inspect(self,s:&mut Sink,d:usize){self.0.view(s,d);}}
    impl<T:?Sized> Inspect for &&Probe<'_,T>{fn inspect(self,s:&mut Sink,_:usize){s.push("<not inspected>");}}
    pub fn preview<T:?Sized>(_:&T,render:impl FnOnce(&mut Sink))->::std::string::String {
        let mut s=Sink{text: ::std::string::String::new(),clipped:false};render(&mut s);
        if s.clipped{s.text.push('…');} s.text
    }
    macro_rules! scalar {($($ty:ty),*)=>{$(impl Value for $ty{fn view(&self,s:&mut Sink,_:usize){use ::std::fmt::Write;let _=write!(s,"{:?}",self);}})*};}
    scalar!(u8,u16,u32,u64,u128,usize,i8,i16,i32,i64,i128,isize,f32,f64,bool,char);
    impl Value for str{fn view(&self,s:&mut Sink,_:usize){
        s.push("\"");for c in self.chars().take(128){for e in c.escape_debug(){use ::std::fmt::Write;let _=s.write_char(e);}if s.clipped{break;}}
        s.push("\"");if self.chars().take(129).count()>128{s.push("…");}
        use ::std::fmt::Write;let _=write!(s," ({} bytes)",self.len());
    }}
    impl Value for ::std::string::String{fn view(&self,s:&mut Sink,d:usize){self.as_str().view(s,d);}}
    impl<T:Value+?Sized> Value for &T{fn view(&self,s:&mut Sink,d:usize){(**self).view(s,d);}}
    impl<T:Value> Value for [T]{fn view(&self,s:&mut Sink,d:usize){
        if d>=4{s.push("…");return;} use ::std::fmt::Write;let _=write!(s,"[len={}] [",self.len());
        for (i,v) in self.iter().take(16).enumerate(){if i>0{s.push(", ");}v.view(s,d+1);if s.clipped{break;}}
        if self.len()>16{s.push(", …");}s.push("]");
    }}
    impl<T:Value> Value for ::std::vec::Vec<T>{fn view(&self,s:&mut Sink,d:usize){self.as_slice().view(s,d);}}
    impl<T:Value,const N:usize> Value for [T;N]{fn view(&self,s:&mut Sink,d:usize){self.as_slice().view(s,d);}}
    impl<T:Value> Value for Option<T>{fn view(&self,s:&mut Sink,d:usize){if d>=4{s.push("…");return;}match self{Some(v)=>{s.push("Some(");v.view(s,d+1);s.push(")");},None=>s.push("None")}}}
    fn quote(out:&mut ::std::string::String,value:&str){
        out.push('"');for c in value.chars().take(512){match c{
            '"'=>out.push_str("\\\""),'\\'=>out.push_str("\\\\"),
            c if (c as u32)<32=>{use ::std::fmt::Write;let _=write!(out,"\\u{:04x}",c as u32);},c=>out.push(c)
        }}out.push('"');
    }
    pub fn point(site:u32,values:&[(&str,::std::string::String,&str)]){
        let mut out=::std::string::String::from("[");
        for (i,(name,value,ty)) in values.iter().enumerate().take(32){
            if out.len()>52000{break;}if i>0{out.push(',');}out.push('[');quote(&mut out,name);out.push(',');quote(&mut out,ty);out.push(',');quote(&mut out,value);out.push(']');
        }out.push(']');unsafe{${debugImport}(2,site,out.as_ptr(),out.len() as u32);}
    }
}
`;
