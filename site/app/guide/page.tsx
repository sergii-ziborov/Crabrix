import Link from "next/link";
import { pageMetadata, pageUrl, breadcrumbs } from "@/lib/seo";
import { StructuredData } from "@/components/structured-data";
import { SyntaxCode } from "@/components/SyntaxCode";

export const metadata = pageMetadata({
  title: "Crabrix User Guide: Offline Rust, Cargo Packages and Web Previews",
  description: "Step-by-step Crabrix guide with real screenshots: create Rust and web projects, pin Cargo packages for offline use, diagnose errors, save work and understand iPhone, iPad and Duo limits.",
  path: "/guide/", image: "/screenshots/duo-laptop.png",
  imageAlt: "Crabrix Duo editor with project search, code tabs, helper keys and keyboard",
});

const contents = [
  ["quick-start", "A ten-minute walkthrough"],
  ["first-project", "Your first project"], ["files", "Files and imports"],
  ["packages", "Packages and offline preparation"], ["build", "Check, Run and build stages"],
  ["web", "Local HTML, CSS and JavaScript"],
  ["terminal", "The project terminal"], ["learn", "Lessons and examples"],
  ["devices", "iPhone, iPad and Duo"], ["limits", "Compiler and runtime boundaries"],
  ["troubleshooting", "Troubleshooting and sharing"],
] as const;

function Screenshot({ name, alt, caption, width = 1320, height = 2868 }: {
  name: string; alt: string; caption: string; width?: number; height?: number;
}) {
  return <figure className="guide-screenshot">
    <a href={`/screenshots/${name}.png`} aria-label={`Open full screenshot: ${alt}`}>
      {/* Product captures stay intact and link to their original resolution. */}
      <img src={`/screenshots/${name}.png`} width={width} height={height} alt={alt} loading="lazy" />
    </a>
    <figcaption>{caption}</figcaption>
  </figure>;
}

export default function GuidePage() {
  return <div className="site-shell article-page">
    <StructuredData data={{ "@context": "https://schema.org", "@graph": [
      { "@type": "TechArticle", headline: "Crabrix user guide", description: metadata.description,
        mainEntityOfPage: pageUrl("/guide/"), inLanguage: "en", isAccessibleForFree: true,
        dateModified: "2026-10-25",
        author: { "@type": "Person", name: "Serhii Ziborov", url: pageUrl("/about/") },
        image: [pageUrl("/screenshots/duo-laptop.png"), pageUrl("/screenshots/iphone-build.png")],
      }, breadcrumbs([{ name: "Crabrix", path: "/" }, { name: "User guide", path: "/guide/" }]),
    ] }} />
    <div className="page-intro article-content">
      <p className="eyebrow">The app, explained</p>
      <h1>From your first Rust file to an offline project.</h1>
      <p className="lede">Create, edit, check and run Rust on your device. This guide shows where each part of Crabrix lives, how to prepare dependencies before going offline, and how to tell a code error from a platform requirement.</p>
      <p>Compilation and program execution take place on the device. Crabrix does not upload your project to a remote compiler. Downloading a public repository, a new crate or a course update needs a connection; using material already prepared on the device does not require an app account.</p>
      <p><strong>Version note:</strong> the workflows below describe the offline web lab in Crabrix 1.1.2. Compiler experiments are identified separately on the <Link href="/technology/">Technology page</Link>; a benchmark of a candidate compiler does not mean that compiler is already installed in your App Store build. Check your app version in Settings before following a newly added workflow.</p>
      <nav className="article-toc" aria-label="Guide contents"><strong>In this guide</strong><ol>{contents.map(([id, label]) => <li key={id}><a href={`#${id}`}>{label}</a></li>)}</ol></nav>
    </div>
    <article className="article-content guide-content">
      <section id="quick-start"><h2>A ten-minute walkthrough</h2>
        <ol>
          <li><strong>Create:</strong> in Projects, choose New Project and start with a small Rust program. Keep its first version free of external dependencies.</li>
          <li><strong>Edit:</strong> open Files, select the entry source and change the printed message. Use in-file search when available to find a name in a longer file.</li>
          <li><strong>Check:</strong> analyze the code. Read Problems if a diagnostic appears; a successful Check does not execute the program.</li>
          <li><strong>Run:</strong> compile and execute locally. Read the printed message in Output. Expand Build stages to see which preparation, compilation or execution step ran.</li>
          <li><strong>Prepare:</strong> if you add crates, finish their downloads and retain the exact graph for offline use. Keep the lockfile and successfully run that project before disconnecting.</li>
          <li><strong>Verify offline:</strong> turn off connectivity, reopen your saved project and Run again. Your source, required archives and local compiler should be sufficient for the supported graph.</li>
          <li><strong>Keep a copy:</strong> use project settings to save an editable project package or a source ZIP. A backup should contain supporting files and the manifest, not only the currently open tab.</li>
        </ol>
        <p>For a web exercise, create Web Page instead, edit the local HTML, stylesheet and script, then Run. The Output preview renders those assets on the device. It does not require a hosted website or a remote Rust service.</p>
      </section>
      <section id="first-project"><h2>1. Create a small project first</h2>
        <p>Open <strong>Projects</strong>, choose <strong>New Project</strong> and create a Rust project. Give it a name that describes the experiment. <strong>My Projects</strong> opens your saved project library; folders and tags organize that library without relocating the durable project files.</p>
        <p>Start with a program that has no external packages. Replace the starter source with the example below, use <strong>Check</strong>, then <strong>Run</strong>. A successful run prints one line in <strong>Output</strong>. This establishes that the bundled compiler works before you add a dependency graph.</p>
        <SyntaxCode code={'fn main() {\n    let language = "Rust";\n    println!("Hello, {language} — running locally!");\n}'} />
        <Screenshot name="iphone-projects" alt="Crabrix Projects home on iPhone" caption="Projects is the entry point for creating, importing and opening your work. My Projects opens your saved project library." />
      </section>
      <section id="files"><h2>2. Understand the project files</h2>
        <p>Use <strong>Files</strong> to open the project tree. A small program can live in <code>main.rs</code>; a Cargo package usually has <code>Cargo.toml</code> and <code>src/main.rs</code>. A declaration such as <code>mod greeter;</code> loads another source module from the corresponding file. Keep the module and directory names consistent with the source.</p>
        <p>The selected file is what you edit; the project entry file is what the compiler builds. Opening a supporting module should not turn it into a different program. A library-only repository needs an executable example or a suitable entry point before it can be run; checking a library and running a binary are different operations.</p>
        <p>Under <strong>New Project</strong>, import from Files or GitHub. Public GitHub import downloads a source archive, not the repository's prebuilt native executable. An imported project still has to fit the supported manifest, dependency and target requirements. Large workspaces, Git/path dependencies and host-specific build tools may need preparation before the selected package can be compiled.</p>
        <p>Keep a copy of your original project when investigating a complex import. Read its <code>README</code>, license and <code>Cargo.toml</code> first. A GitHub URL is a source location; it is not a guarantee that the project targets the offline WebAssembly environment.</p>
      </section>
      <section id="packages"><h2>3. Prepare packages before going offline</h2>
        <p>A Cargo project declares crates in <code>Cargo.toml</code>. Open the package controls to add or resolve a dependency. Crabrix resolves the graph, downloads exact source archives, checks their registry checksums and builds the required libraries locally. The dependency graph supports up to <strong>2,048 unique packages</strong>. This counts resolved package versions, not aliases or files; each crate still needs to support the local WASI target. Larger graphs can take longer to prepare and compile. The original package source remains available to view; <strong>Vendor &amp; Edit</strong> creates an editable project-local overlay.</p>
        <p>The package window shows what is waiting, being acquired or unpacked, what is already available, and the exact package that failed. Expand a package to inspect its dependencies. Closing this window leaves the operation running. You can return to its details from the build-stage log in Output.</p>
        <p>Keep <code>Cargo.lock</code> with the project. It records the resolved versions and checksums. New package preparations retain verified archives outside iOS's purgeable cache, so extracted sources can be restored after cache eviction. Removing offline archives intentionally removes that protection. Changing dependencies while offline can require packages that have never been downloaded.</p>
        <p>In Packages, look for <strong>offline pinned</strong>. When an older project is only <strong>offline while cached</strong>, use <strong>Pin exact graph for offline</strong> while connected. A source archive and a compiled library serve different purposes: the archive lets Crabrix restore source; a compiled artifact lets an unchanged build skip work. Changing source, features or compiler identity can correctly require a rebuild even though the project is ready offline.</p>
        <div className="guide-table"><table><caption>Reading the package preparation window</caption><thead><tr><th scope="col">Status</th><th scope="col">Meaning and next action</th></tr></thead><tbody>
          <tr><th scope="row">Waiting</th><td>This package has not reached its acquisition step. Inspect Depends on to understand its place in the graph.</td></tr>
          <tr><th scope="row">Acquiring source archive</th><td>The app is fetching missing source. A connection is needed for material not already retained locally.</td></tr>
          <tr><th scope="row">Checksum verified · unpacking source</th><td>The registry checksum matched; the verified archive is being extracted for local compilation.</td></tr>
          <tr><th scope="row">Source ready / Already available locally</th><td>The source is available. This does not mean the library has finished compiling.</td></tr>
          <tr><th scope="row">An error message</th><td>Read the exact package and reason. A failure to acquire one dependency should be investigated before treating later packages as compiler failures.</td></tr>
        </tbody></table></div>
        <p>Before a trip, open the project, let package preparation finish, perform a successful Run, then disable connectivity and repeat the run after reopening the app. This checks your actual project rather than assuming that a cached result proves every required source archive is retained.</p>
        <p>A package's status distinguishes an expectation from evidence. <strong>Check verified</strong> means metadata compilation succeeded. <strong>Link verified</strong> requires an actual library build. Neither label proves every optional feature, target or version of that crate works. Read the feature-specific results and limits below.</p>
      </section>
      <section id="build"><h2>4. Check code, run it, and read the right panel</h2>
        <p><strong>Check</strong> asks the compiler to analyze the current project and produce diagnostics. It does not execute your program. <strong>Run</strong> builds an executable WebAssembly module and runs it in the local sandbox. The first dependency build can take much longer than an unchanged build that reuses verified artifacts.</p>
        <p><strong>Problems</strong> contains compiler and setup errors, including failures with no source location. Open a diagnostic to inspect its relevant file and location when available. A package build failure is not evidence that the root file is error-free; the compiler may not have reached it yet.</p>
        <p><strong>Output</strong> contains the program's printed text or validated visual output. The expandable <strong>Build stages</strong> log records dependency preparation, compilation, cached work and execution separately. A count of completed packages is not a prediction of time remaining: one large package can take longer than many small ones combined.</p>
        <p>Use <strong>Stop</strong> to cancel a long operation. Cancellation has its own stopping reason; it should not be confused with a Rust syntax error. After cancellation, wait for the worker to finish stopping before starting another operation. Your editable source remains the project you were working on.</p>
        <p>For a concrete exercise, leave out the closing quote of a string and Check. Follow the reported source location, restore the quote, Check again, then Run. If instead a dependency fails during preparation, inspect that package's diagnostic first: there may be no useful line number in your own file. Keep the build-stage context with the error when asking for help.</p>
        <Screenshot name="iphone-build" alt="iPhone Rust editor showing a borrow-checking exercise and Code Problems Output Terminal tabs" caption="The editor shows source; Problems explains errors; Output shows what a completed program printed. This capture is a deliberate borrowing exercise, not a successful-build claim." />
      </section>
      <section id="web"><h2>5. Build a local web page</h2>
        <p>Choose <strong>Web Page</strong> for an HTML entry with <code>styles.css</code> and <code>app.js</code>, or <strong>Rust Web Generator</strong> to write those assets from a Rust program into <code>/sandbox</code>. Run opens the successful output as an offline WebKit preview. Check prepares direct web assets; it does not claim to compile JavaScript or validate browser behavior.</p>
        <p>Keep script and stylesheet references relative and include all required assets locally. External HTTP requests, CDN scripts and remote fonts are blocked. The preview uses a nonpersistent browser data store and exposes no native project-editing or shell bridge. Browser errors appear in its console and in Problems; Rust errors remain compiler diagnostics.</p>
        <ol>
          <li>Start with the Web Page template. Keep <code>index.html</code>, <code>styles.css</code> and <code>app.js</code> in the project; preserve their relative references.</li>
          <li>Change a heading in HTML, a color in CSS and the counter behavior in JavaScript. Run, then interact with the rendered page to verify all three assets were loaded.</li>
          <li>If the page looks unstyled, compare the stylesheet path and file name, including capitalization. If a button does nothing, inspect the web console and Problems for its script error.</li>
          <li>After editing source, Run again to create a new preview snapshot. Reload restarts the current snapshot; it does not read arbitrary unsaved project files into the browser process.</li>
          <li>For generated sites, start with Rust Web Generator. Write the complete local asset set under <code>/sandbox</code>, let the program finish successfully, then inspect the resulting preview.</li>
        </ol>
        <p>A small generator can begin with the following pattern. The full template adds a separate stylesheet and script. Escape user-controlled values before inserting them into generated HTML; Rust string formatting does not perform HTML escaping for you.</p>
        <SyntaxCode code={'fn main() -> std::io::Result<()> {\n    let html = r#"<!doctype html>\n<html lang="en">\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n<title>My offline page</title>\n<h1>Hello from Rust</h1>\n<p>This page was generated on the device.</p>\n</html>"#;\n    std::fs::write("/sandbox/index.html", html)?;\n    Ok(())\n}'} />
        <p>Close releases the preview; Reload starts a new page session. The current snapshot allows 256 supported assets, 2 MiB per asset and 8 MiB in total. WebKit runs separately from WASI: a JavaScript loop is not governed by the Rust guest's instruction or time budgets. TypeScript is highlighted but not transpiled. This feature renders local pages and does not run a TCP server.</p>
        <p>Keep the project source as the durable copy of a web exercise. Browser storage in this nonpersistent preview is temporary; it is unsuitable for the only copy of user data. Node.js package managers, development servers and a remote API are separate requirements. A local interactive page can work here while a framework's ordinary server-based development command cannot.</p>
        <Screenshot name="offline-web-preview" width={1170} height={1614} alt="Actual offline WebKit preview of the Crabrix web template after its JavaScript counter was clicked" caption="A real Simulator WebKit capture after clicking the local counter. This shows the rendered page, not the native editor controls." />
        <p>For a complete generator with escaping, local CSS and an interactive counter, see <Link href="/blog/crabrix-offline-rust-web-preview/">the Rust web lab article</Link>.</p>
      </section>
      <section id="terminal"><h2>6. Use the project terminal as a project tool</h2>
        <p>Choose <strong>Terminal</strong> and enter a supported command, or use a command chip. Start with <code>help</code> to see the commands available in your installed version. Commands such as <code>tree</code>, <code>cargo metadata</code>, <code>cargo check</code> and <code>cargo run</code> inspect or operate on the current project.</p>
        <p>This terminal is a project command interface. It does not expose a general iOS shell, install arbitrary host executables or make external command-line tools available to build scripts. A repository instruction that invokes Bash, a native C compiler or a platform SDK therefore needs a separate compatibility assessment.</p>
        <p>When you switch to Terminal, focus belongs in its command input. On Duo, the keyboard-dismiss control beside the code tabs lets you reclaim space when needed. The editor helper keys and keyboard layout are adapted to the device; the terminal's commands still operate on the same saved project.</p>
      </section>
      <section id="learn"><h2>7. Move from a lesson to your own project</h2>
        <p>In <strong>Learn</strong>, download a course and open its lessons offline. A signed course update can replace lesson explanations, starters and media while retaining your learning progress. Refresh installed courses to look for updates; use the course's Update action or Update all when an update is offered.</p>
        <p><strong>Open in Code</strong> creates or opens an editable project for an example or lesson. That project is a durable copy. Updating the course does not silently rewrite your edited project. If you want the newer starter too, open it separately and compare the source before replacing your own work.</p>
        <p>Some challenges validate a particular behavior through a private harness; a program compiling successfully is not always the same as passing the challenge. Read the lesson's expected outcome and feedback. Code Examples also include descriptions and illustrations that explain what the program is meant to demonstrate.</p>
        <p>The website's <Link href="/learn/">Academy</Link> provides public lesson previews and complete lessons in a free website account. The native app's local compiler and downloaded learning material do not require that website login. Optional online account or Game Center features are separate from local compilation.</p>
        <div className="guide-screenshots"><Screenshot name="iphone-learn" alt="Downloaded Rust courses in Crabrix Learn" caption="Download a course while connected, then keep reading it offline." /><Screenshot name="iphone-examples" alt="Crabrix Code Examples learning path" caption="Examples connect the explanation and illustration to an editable Rust project." /></div>
        <Screenshot name="iphone-example-detail" alt="Ferris Pixel Art example with its explanation, infographic and Open in Code button" caption="An example guide explains what to notice. Open in Code creates your own editable project; future course updates keep that project intact." />
      </section>
      <section id="devices"><h2>8. Work on iPhone, iPad and Duo</h2>
        <p>On iPhone, Files opens the project navigator while the editor stays focused on the selected source. On iPad, the wider workspace can show the file sidebar alongside the editor and in-file search. Search finds text within the open file; it does not change which project is compiled.</p>
        <p>Duo adapts the workspace to the fold and posture. The compact header includes the project name and search. Code, Problems, Output and Terminal share the established tab region, with editor helper keys directly above the keyboard. Use the keyboard-dismiss control in the tab strip when it is available for that posture.</p>
        <div className="guide-screenshots"><Screenshot name="duo-laptop" alt="Duo Rust workspace with search, code tabs, helper keys and keyboard" caption="Duo: project name and search at the top; code tabs, helpers and keyboard in the fold-aware workspace." width={2007} height={2853} /><Screenshot name="ipad-build" alt="iPad Crabrix workspace with file navigation and in-file search" caption="iPad: a wider workspace with navigation and search above the code." width={2064} height={2752} /></div>
      </section>
      <section id="limits"><h2>9. Know what the compiler can actually run</h2>
        <p>The bundled compiler targets <code>wasm32-wasip1</code>, executed by an interpreter. The app does not turn downloaded source into an unsigned native iOS executable. A dependency being pure Rust is helpful, but does not by itself prove compatibility: it may still require operating-system facilities, compiler features or host tools absent from this target.</p>
        <div className="guide-table"><table><caption>Requirements and their meaning in the offline environment</caption><thead><tr><th scope="col">Requirement</th><th scope="col">What to expect</th></tr></thead><tbody>
          <tr><th scope="row">Standard-library learning programs</th><td>Use the local compiler and supported WASI operations. Check and Run remain separate checks.</td></tr>
          <tr><th scope="row">Cargo features and versions</th><td>Compatibility belongs to the exact resolved graph. An optional feature may introduce native code or an unavailable runtime service.</td></tr>
          <tr><th scope="row">Code-generating build.rs</th><td>The offline host supports standard-library scripts with isolated generated files and selected Cargo instructions. Separate build-dependency graphs, subprocesses and native linker directives remain distinct requirements.</td></tr>
          <tr><th scope="row">Procedural macros</th><td>Host procedural-macro execution is not bundled. An explicit macro-free profile may work; Crabrix does not silently rewrite a project's requested features.</td></tr>
          <tr><th scope="row">C, C++ and native libraries</th><td>The toolchain includes its WASI sysroot, not a general on-device Clang installation or arbitrary native iOS/Linux libraries. A crate that invokes cc or links a system library needs additional compiler/runtime work or a documented portable implementation.</td></tr>
          <tr><th scope="row">Tokio and Axum</th><td>Single-threaded scheduling, timers and channels are different from TCP sockets, process spawning and a server runtime. Consult exact tested profiles; a router handling an in-process request is not a listening TCP server.</td></tr>
          <tr><th scope="row">Networking and external services</th><td>The program sandbox has no network imports. Downloading a package through the app does not give that package's program access to the internet.</td></tr>
          <tr><th scope="row">CUDA / NVIDIA</th><td>An iPhone has no NVIDIA CUDA device or CUDA driver. Such a requirement cannot be supplied by enabling a Rust feature flag. GPU APIs are not exposed to this guest environment.</td></tr>
        </tbody></table></div>
        <p>User-program policy currently caps linear memory at 64 MiB, output at 1 MiB, writable sandbox data at 8 MiB across 256 files, and execution at a 30-second deadline plus an instruction budget. Compiler execution has a separate, larger budget. These are upper bounds, not reserved physical memory; iOS can impose its own resource constraints.</p>
        <p>Compilation speed depends on the exact dependency graph, cold versus reused artifacts, the device and its thermal state. The program's 30-second execution limit is not a promise that any project compiles within 30 seconds. Begin with a small supported feature set, keep a reproducible lockfile and consult measured profiles before importing a much larger application.</p>
        <p>A failure in Crabrix's code generator is a compiler defect to investigate, not a claim that the Rust project is invalid. When reporting one, include the exact package versions, features, source and diagnostic. <Link href="/technology/">Technology</Link> describes the runtime and toolchain; the project README records the tested compatibility matrix and remaining gaps.</p>
      </section>
      <section id="troubleshooting"><h2>10. Diagnose, save and share a reproducible project</h2>
        <div className="guide-table"><table><caption>Start with the stage that failed</caption><thead><tr><th scope="col">Symptom</th><th scope="col">Next step</th></tr></thead><tbody>
          <tr><th scope="row">A download fails</th><td>Read the named package and error in the package window. Check connectivity while acquiring new material. Keep already verified packages; retry the missing step when connected.</td></tr>
          <tr><th scope="row">Problems reports a Rust error</th><td>Open the diagnostic, inspect the file and location, fix the code, then Check again.</td></tr>
          <tr><th scope="row">No program output</th><td>Check whether you used Check rather than Run, whether compilation stopped earlier, or whether the successful program prints anything.</td></tr>
          <tr><th scope="row">A crate or target is unsupported</th><td>Read its exact requirement. Separate a backend defect from host macros, native toolchains, networking or GPU hardware requirements. Preserve the original manifest while investigating.</td></tr>
          <tr><th scope="row">An offline reopen fails</th><td>Check Cargo.lock and retained package archives. A changed manifest may request a new dependency that was never acquired.</td></tr>
          <tr><th scope="row">A web preview is blank or a button does nothing</th><td>Inspect the web console, entry HTML and relative script paths. Keep required assets local. Rebuild the snapshot after editing source.</td></tr>
          <tr><th scope="row">A second build is unexpectedly slow</th><td>Check whether source, enabled features, the lockfile or toolchain changed. These can invalidate compiled artifacts without losing offline source archives. Let a hot device cool before comparing timings.</td></tr>
        </tbody></table></div>
        <p>Use project settings to save an editable project package or export a source ZIP. Keep the manifest, lockfile and supporting modules with the entry source. Remove private data before sharing a reproduction. Package licenses still apply to imported and redistributed source; the app's <Link href="/licenses/">license library</Link> and <Link href="/terms/">terms</Link> describe Crabrix's own components and content.</p>
        <p>For help, send the smallest project that demonstrates the problem, the app/build version, device format, exact action and the text from Problems. Mention whether it occurs after an offline reopen or only after changing dependencies. That evidence makes it possible to fix the missing capability and rerun the same test.</p>
        <p><Link href="/support/">Get support</Link> · <Link href="/learn/">Explore the Academy</Link> · <Link href="/blog/">Read practical Rust articles</Link></p>
      </section>
    </article>
  </div>;
}
