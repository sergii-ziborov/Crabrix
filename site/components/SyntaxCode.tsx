import type { ReactNode } from "react";

const keywords = new Set([
  "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum",
  "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod",
  "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super",
  "trait", "true", "type", "unsafe", "use", "where", "while",
]);

const types = new Set([
  "Arc", "BinaryHeap", "Box", "Cell", "Err", "HashMap", "HashSet", "Mutex", "None",
  "Ok", "Option", "Pin", "Rc", "RefCell", "Result", "RwLock", "Some", "String",
  "Vec", "VecDeque", "bool", "char", "f32", "f64", "i8", "i16", "i32", "i64",
  "i128", "isize", "str", "u8", "u16", "u32", "u64", "u128", "usize",
]);

const tokens = /\/\/[^\n]*|\/\*[\s\S]*?\*\/|#\[[^\]\n]*\]|r#{0,3}"[\s\S]*?"#{0,3}|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])'|'[A-Za-z_]\w*|\b[A-Za-z_]\w*!|\b\d[\d_]*(?:\.\d[\d_]*)?\b|\b[A-Za-z_]\w*\b/g;

function kind(token: string): string | undefined {
  if (token.startsWith("//") || token.startsWith("/*")) return "comment";
  if (token.startsWith("#[")) return "attribute";
  if (token.startsWith('"') || token.startsWith('r"') || /^r#+"/.test(token) || /^'(?:\\.|[^'\\])'$/.test(token)) return "string";
  if (token.startsWith("'")) return "lifetime";
  if (token.endsWith("!")) return "macro";
  if (/^\d/.test(token)) return "number";
  if (keywords.has(token)) return "keyword";
  if (types.has(token)) return "type";
  return undefined;
}

export function highlightedCode(code: string): ReactNode[] {
  const result: ReactNode[] = [];
  let position = 0;
  for (const match of code.matchAll(tokens)) {
    const start = match.index;
    if (start > position) result.push(code.slice(position, start));
    const token = match[0];
    const tokenKind = kind(token);
    result.push(tokenKind
      ? <span className={`syntax-${tokenKind}`} key={start}>{token}</span>
      : token);
    position = start + token.length;
  }
  if (position < code.length) result.push(code.slice(position));
  return result;
}

export function SyntaxCode({ code }: { code: string }) {
  return <pre className="syntax-code"><code>{highlightedCode(code)}</code></pre>;
}
