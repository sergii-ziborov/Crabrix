/** Copy for the "Rust for … developers" bridge courses. Course content itself comes from crabrix-courses. */
export type BridgeAudience = {
  /** The language the reader already knows, as shown in headings. */
  language: string;
  /** Two-letter badge used in place of course artwork. */
  badge: string;
  /** Who the course is for, for structured data and the intro. */
  audience: string;
  /** Title tag for the course page. */
  pageTitle: string;
  /** Meta description for the course page, at most 160 characters. */
  description: string;
  /** Intro paragraph on the course page. */
  intro: string;
  prerequisites: string;
};

export const bridgeAudiences: Record<string, BridgeAudience> = {
  "rust-for-c-developers": {
    language: "C",
    badge: "C",
    audience: "C programmers",
    pageTitle: "Rust for C Developers — malloc, pointers, errno and make, side by side",
    description: "Learn Rust from C: malloc/free vs ownership, pointers vs references, tagged unions vs enums, errno vs Result. Each lesson puts C next to Rust. Free.",
    intro: "You already know how memory, pointers and a compiler work. Each lesson puts a C habit next to its Rust equivalent, names exactly what changes, and asks you to port the C function to Rust. Undefined behaviour in the C examples was confirmed with sanitizers, and every Rust example was compiled and run.",
    prerequisites: "Working knowledge of C: pointers, malloc and free, structs, and building with a compiler command line or make.",
  },
  "rust-for-nodejs-developers": {
    language: "Node.js",
    badge: "JS",
    audience: "JavaScript, TypeScript and Node.js developers",
    pageTitle: "Rust for Node.js Developers — JavaScript and TypeScript side by side",
    description: "Learn Rust from JavaScript and TypeScript: undefined vs Option, try/catch vs Result, array methods vs iterators, npm vs Cargo, Promises vs futures. Free.",
    intro: "You already ship JavaScript or TypeScript. Each lesson puts a Node.js habit next to its Rust equivalent, names exactly what changes, and asks you to port the function to Rust. Every JavaScript example was run on Node.js 22, TypeScript was type-checked in strict mode, and every Rust example was compiled and run.",
    prerequisites: "Working knowledge of JavaScript or TypeScript on Node.js: objects, arrays, closures, Promises and npm.",
  },
};

export function bridgeAudience(courseId: string): BridgeAudience | undefined {
  return bridgeAudiences[courseId];
}

/**
 * True once an App Store build that credits Academy lessons from bridge lessons
 * is live. Until then the site only says which lessons a reader can skip.
 */
export const appSupportsBridgeCredits = false;
