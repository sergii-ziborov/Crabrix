import type { ReactNode } from "react";
import { codeTokens } from "@/lib/code-highlighting";

export function highlightedCode(code: string): ReactNode[] {
  return codeTokens(code).map((token, index) => token.kind
    ? <span className={`syntax-${token.kind}`} key={index}>{token.value}</span>
    : token.value);
}

export function SyntaxCode({ code }: { code: string }) {
  return <pre className="syntax-code"><code>{highlightedCode(code)}</code></pre>;
}
