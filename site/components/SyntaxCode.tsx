import type { ReactNode } from "react";
import { codeTokens, type CodeLanguage } from "@/lib/code-highlighting";

export function highlightedCode(code: string, language?: CodeLanguage): ReactNode[] {
  return codeTokens(code, language).map((token, index) => token.kind
    ? <span className={`syntax-${token.kind}`} key={index}>{token.value}</span>
    : token.value);
}

export function SyntaxCode({ code, language }: { code: string; language?: CodeLanguage }) {
  return <pre className="syntax-code"><code>{highlightedCode(code, language)}</code></pre>;
}
