export type CodeLanguage = "rust" | "toml" | "sql" | "json" | "html" | "typescript" | "shell";
export type CodeToken = { value: string; kind?: string };

const rustKeywords = new Set("as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while".split(" "));
const rustTypes = new Set("Arc BinaryHeap Box Cell Err HashMap HashSet Mutex None Ok Option Pin Rc RefCell Result RwLock Some String Vec VecDeque bool char f32 f64 i8 i16 i32 i64 i128 isize str u8 u16 u32 u64 u128 usize".split(" "));
const sqlKeywords = new Set("BEGIN COMMIT ROLLBACK CREATE TABLE INDEX UNIQUE ON EXPLAIN ANALYZE SELECT FROM WHERE UPDATE SET INSERT INTO VALUES DELETE AND OR NOT NULL IS IN AS ORDER BY GROUP HAVING JOIN LEFT RIGHT INNER OUTER LIMIT ASC DESC IF EXISTS TRANSACTION ISOLATION LEVEL READ COMMITTED REPEATABLE SERIALIZABLE".split(" "));
const sqlTypes = new Set("INT INTEGER BIGINT SMALLINT TEXT VARCHAR TIMESTAMP DATE NUMERIC DECIMAL BOOLEAN INTERVAL".split(" "));

export function codeLanguage(code: string): CodeLanguage {
  if (/^\s*(?:--[^\n]*\n\s*)*(?:CREATE\s+(?:TABLE|INDEX)|BEGIN\s*;|SELECT\b|EXPLAIN\b|UPDATE\b)/i.test(code)) return "sql";
  if (/^\s*\[\[?(?:dependencies|dev-dependencies|build-dependencies|features|workspace|package|profile\.[\w-]+|lib)\]?\]\s*$/m.test(code)) return "toml";
  return "rust";
}

function tokensFor(code: string, language: CodeLanguage): CodeToken[] {
  if (["json", "html", "typescript", "shell"].includes(language)) {
    const expression = language === "shell"
      ? /#[^\n]*|"(?:\\.|[^"\\])*"|'[^']*'|--?[A-Za-z][\w-]*|\b(?:git|cargo|rustfmt|npm)\b/g
      : language === "html"
      ? /<!--[\s\S]*?-->|<\/?[A-Za-z][\w:-]*|[A-Za-z_:][\w:.-]*(?=\s*=)|"(?:\\.|[^"\\])*"|'[^']*'/g
      : /\/\/[^\n]*|\/\*[\s\S]*?\*\/|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\b\d+(?:\.\d+)?\b|\b[A-Za-z_$][\w$]*\b/g;
    const keywords = new Set("import from export default const let var function return if else new async await throw class extends true false null undefined type interface as typeof".split(" "));
    const result: CodeToken[] = []; let cursor = 0;
    for (const match of code.matchAll(expression)) {
      if (match.index > cursor) result.push({ value: code.slice(cursor, match.index) });
      const value = match[0];
      const kind = /^(?:<!--|\/\/|\/\*)/.test(value) || (language === "shell" && value.startsWith("#")) ? "comment"
        : /^["'`]/.test(value) ? "string" : /^\d/.test(value) ? "number"
        : language === "shell" ? (value.startsWith("-") ? "attribute" : "keyword")
        : value.startsWith("<") ? "type" : language === "html" ? "attribute"
        : keywords.has(value) ? "keyword" : undefined;
      result.push({ value, ...(kind ? { kind } : {}) }); cursor = match.index + value.length;
    }
    if (cursor < code.length) result.push({ value: code.slice(cursor) });
    return result;
  }
  const pattern = language === "rust"
    ? /\/\/[^\n]*|\/\*[\s\S]*?\*\/|#\[[^\]\n]*\]|(?:br|cr|r)(#{0,255})"[\s\S]*?"\1|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])'|'[A-Za-z_]\w*|\b[A-Za-z_]\w*!|\b\d[\d_]*(?:\.\d[\d_]*)?\b|\b[A-Za-z_]\w*\b/gu
    : language === "toml"
      ? /#[^\n]*|^\s*\[+[^\]\n]+\]+|\b[A-Za-z_][\w.-]*(?=\s*=)|"(?:\\.|[^"\\])*"|'[^']*'|\b(?:true|false)\b|\b\d+(?:\.\d+)*\b/gm
      : /--[^\n]*|\/\*[\s\S]*?\*\/|'(?:''|[^'])*'|"(?:""|[^"])*"|\b\d+(?:\.\d+)?\b|\b[A-Za-z_]\w*\b/g;
  const result: CodeToken[] = []; let cursor = 0;
  for (const match of code.matchAll(pattern)) {
    const start = match.index, value = match[0]; let kind: string | undefined;
    if (start > cursor) result.push({ value: code.slice(cursor, start) });
    if (language === "rust") {
      if (value.startsWith("//") || value.startsWith("/*")) kind = "comment";
      else if (value.startsWith("#[")) kind = "attribute";
      else if (value.startsWith('"') || /^(?:br|cr|r)#{0,255}"/.test(value) || /^'(?:\\.|[^'\\])'$/u.test(value)) kind = "string";
      else if (value.startsWith("'")) kind = "lifetime";
      else if (value.endsWith("!")) kind = "macro";
      else if (/^\d/.test(value)) kind = "number";
      else if (rustKeywords.has(value)) kind = "keyword";
      else if (rustTypes.has(value)) kind = "type";
    } else if (language === "toml") {
      if (value.startsWith("#")) kind = "comment";
      else if (value.trimStart().startsWith("[")) kind = "type";
      else if (/^["']/.test(value)) kind = "string";
      else if (/^\d/.test(value)) kind = "number";
      else if (value === "true" || value === "false") kind = "keyword";
      else kind = "attribute";
    } else {
      if (value.startsWith("--") || value.startsWith("/*")) kind = "comment";
      else if (/^["']/.test(value)) kind = "string";
      else if (/^\d/.test(value)) kind = "number";
      else if (sqlKeywords.has(value.toUpperCase())) kind = "keyword";
      else if (sqlTypes.has(value.toUpperCase())) kind = "type";
    }
    result.push({ value, ...(kind ? { kind } : {}) }); cursor = start + value.length;
  }
  if (cursor < code.length) result.push({ value: code.slice(cursor) });
  return result;
}

export function codeTokens(code: string, selectedLanguage?: CodeLanguage): CodeToken[] {
  const language = selectedLanguage ?? codeLanguage(code);
  // Older lessons can combine a Cargo manifest and a labeled Rust source file.
  if (language === "toml" && /^\/\/[^\n]*\.rs\s*$/m.test(code)) {
    const pieces = code.split(/(?=^\/\/[^\n]*\.rs\s*$)/m);
    return pieces.flatMap((piece, index) => tokensFor(piece, index === 0 ? "toml" : "rust"));
  }
  return tokensFor(code, language);
}
