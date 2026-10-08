export type Post = {
  slug: string;
  title: string;
  date: string;
  readingMinutes: number;
  summary: string;
  sections: { heading: string; paragraphs: string[]; code?: string }[];
};

export const posts: Post[] = [
  {
    slug: "real-rust-on-iphone",
    title: "What it means to run a real Rust compiler on an iPhone",
    date: "2026-10-08",
    readingMinutes: 5,
    summary: "Crabrix bundles rustc and runs it locally. Here is what happens when you press Check or Run, and where the limits are.",
    sections: [
      {
        heading: "The compiler is inside the app",
        paragraphs: [
          "Crabrix is built around a pinned Rust compiler targeting wasm32-wasip1. The compiler and its sysroot ship in the iOS app bundle. When you check a project, the app runs that compiler on the device and presents its diagnostics. Your source does not have to travel to a remote compilation service.",
          "The compiler is WebAssembly executed by CrabrixRuntime, a Swift interpreter derived from WasmKit. This makes it possible to run the toolchain in an iOS app without a JIT, a helper daemon, or downloaded executable code. The exact toolchain identity is visible in the app and recorded in the public build documentation.",
        ],
      },
      {
        heading: "A real build has a real cost",
        paragraphs: [
          "The first build performs real parsing, type checking, borrow checking and, when requested, code generation. That work can take longer on a phone than on a laptop. Identical repeat runs can use a local artifact cache, but a changed source file or a new dependency still needs a genuine build.",
          "Crabrix applies limits to guest memory, writable files, output and runtime. A project terminal operates on the project workspace; it is not a host shell and cannot spawn arbitrary iOS processes. Programs have no socket import. Those boundaries are deliberate and visible, rather than being presented as an unrestricted desktop environment.",
        ],
      },
      {
        heading: "Cargo support is practical, with edges",
        paragraphs: [
          "The app resolves a supported subset of crates.io packages, verifies downloaded archives, writes Cargo.lock and builds dependencies for its target. Cached packages can be reused offline, and Pin for Offline keeps verified archives durable after cache eviction.",
          "Procedural macros, executable build scripts and native C linking remain outside that subset. Crabrix reports incompatibility and build outcomes per dependency. The Technology page keeps the current supported and unsupported cases together, so you can judge a project before committing time to a long build.",
        ],
      },
      {
        heading: "Why this matters for learning",
        paragraphs: [
          "Rust concepts become clearer when feedback comes from the compiler you actually use. A borrow error is a real diagnostic, not a scripted quiz. A lesson can become a durable project; the project can then be edited, checked, run and exported independently of the course.",
          "The same course texts are now free to read in the web Learn section. The iOS app adds local compilation, offline course downloads, practice, progress and a native project workspace.",
        ],
      },
    ],
  },
  {
    slug: "from-lesson-to-project",
    title: "From a Rust lesson to a project you own",
    date: "2026-10-08",
    readingMinutes: 4,
    summary: "How Crabrix connects its 142 Rust lessons, Algorithm Atlas and editable code workspace.",
    sections: [
      {
        heading: "Read, predict, then change the code",
        paragraphs: [
          "Crabrix Academy has six Rust language courses with 142 guided lessons, plus Algorithm Atlas: 200 patterns taught through 600 steps. A lesson introduces one idea, gives a Rust example, asks you to predict or explain an outcome, and offers a task to try. The course content is the same in the app and on this website.",
          "A useful way to study is to pause before revealing an answer. Read the example, write down the output or compiler error you expect, then compare with the explanation. The web lessons keep every answer available without an account or payment.",
        ],
      },
      {
        heading: "Make the example yours",
        paragraphs: [
          "In the iOS app, opening lesson source in Code creates an editable project copy. It is stored separately from the downloaded course. Editing or removing a course does not change the project you made from it. My Projects is where that copy remains available for later work and export.",
          "Try a small change first: rename a value, handle an empty input, or change a borrow into a move. Check the result, inspect Problems, and run the program when it is ready. This short loop is the bridge from reading Rust to writing it.",
        ],
        code: "fn main() {\n    let names = vec![\"Ferris\", \"Crabrix\"];\n    for name in &names {\n        println!(\"Hello, {name}!\");\n    }\n}",
      },
      {
        heading: "Go beyond a single file",
        paragraphs: [
          "Code Examples is an optional separate download in the app with 46 editable Rust projects. Each stop has its own guide and source preview, and Open in Code creates another durable project. The project workspace supports multiple files, a manifest, a supported set of crates.io dependencies, compiler diagnostics, output and a project terminal.",
          "On the website, start with the free Learn catalog and follow the unit order that fits your experience. When you want to experiment with the real compiler on the go, the app carries the lessons and the workspace together.",
        ],
      },
    ],
  },
];

export function postBySlug(slug: string): Post | undefined {
  return posts.find((post) => post.slug === slug);
}
