use base_db::{
    CrateName, CrateOrigin, CrateWorkspaceData, DependencyBuilder, Env, LangCrateOrigin,
};
use cfg::CfgOptions;
use hir::{ChangeWithProcMacros, Symbol};
use ide::{
    AnalysisHost, CrateGraphBuilder, FileId, FilePosition, FileRange, SourceRoot, TextRange,
    TextSize,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    cell::RefCell,
    collections::{BTreeMap, BTreeSet},
};
use triomphe::Arc;
use vfs::{VfsPath, file_set::FileSet};

#[derive(Clone, Deserialize, Serialize, PartialEq, Eq)]
struct CrateInput {
    root: String,
    #[serde(default)]
    dependencies: BTreeMap<String, String>,
    #[serde(default = "default_edition")]
    edition: String,
    #[serde(default)]
    kind: String,
    #[serde(default)]
    name: String,
    #[serde(default)]
    features: Vec<String>,
}
fn default_edition() -> String {
    "2024".into()
}
impl Default for CrateInput {
    fn default() -> Self {
        Self {
            root: String::new(),
            dependencies: BTreeMap::new(),
            edition: default_edition(),
            kind: String::new(),
            name: String::new(),
            features: vec![],
        }
    }
}
#[derive(Clone, Deserialize)]
struct FileInput {
    path: String,
    text: String,
}
#[derive(Deserialize)]
struct Configuration {
    files: Vec<FileInput>,
    crates: Vec<CrateInput>,
}
struct Engine {
    host: AnalysisHost,
    files: BTreeMap<String, (FileId, String)>,
    crates: Vec<CrateInput>,
    next_id: u32,
}
impl Default for Engine {
    fn default() -> Self {
        Self {
            host: AnalysisHost::new(Some(32)),
            files: BTreeMap::new(),
            crates: vec![],
            next_id: 0,
        }
    }
}
fn path_ok(path: &str) -> bool {
    path.len() <= 240
        && path.ends_with(".rs")
        && !path.starts_with('/')
        && !path.contains(['\\', ':', '\0'])
        && !path.chars().any(char::is_control)
        && path
            .split('/')
            .all(|p| !p.is_empty() && p != "." && p != "..")
}
fn range(range: TextRange) -> Value {
    json!({"start":u32::from(range.start()),"end":u32::from(range.end()),"unit":"utf8"})
}
impl Engine {
    fn configure(&mut self, configuration: Configuration) -> Result<Value, String> {
        if configuration.files.is_empty()
            || configuration.files.len() > 4096
            || configuration.crates.is_empty()
            || configuration.crates.len() > 256
        {
            return Err("Analysis configuration exceeds profile limits".into());
        }
        let mut total = 0usize;
        let mut seen = BTreeSet::new();
        for f in &configuration.files {
            total += f.text.len();
            if !path_ok(&f.path) || f.text.len() > 1024 * 1024 || !seen.insert(f.path.clone()) {
                return Err("Invalid or duplicate Rust source path".into());
            }
        }
        if total > 24 * 1024 * 1024 {
            return Err("Analysis sources exceed 24 MiB".into());
        }
        if configuration.crates.iter().any(|c| {
            !seen.contains(&c.root)
                || c.dependencies.len() > 256
                || c.features.len() > 256
                || c.features.iter().any(|f| f.len() > 128)
                || c.dependencies
                    .values()
                    .any(|p| !configuration.crates.iter().any(|d| &d.root == p))
        }) {
            return Err("Missing crate root or dependency".into());
        }
        let structural =
            seen != self.files.keys().cloned().collect() || configuration.crates != self.crates;
        let mut changes = ChangeWithProcMacros::default();
        let mut changed = 0;
        let mut files = BTreeMap::new();
        let mut next_id = self.next_id;
        for f in configuration.files {
            let id = if let Some((id, old)) = self.files.get(&f.path) {
                if old != &f.text {
                    changes.change_file(*id, Some(f.text.clone()));
                    changed += 1
                }
                *id
            } else {
                let id = FileId::from_raw(next_id);
                next_id += 1;
                changes.change_file(id, Some(f.text.clone()));
                changed += 1;
                id
            };
            files.insert(f.path, (id, f.text));
        }
        for (p, (id, _)) in &self.files {
            if !seen.contains(p) {
                changes.change_file(*id, None);
                changed += 1
            }
        }
        if structural {
            let mut local = FileSet::default();
            let mut libraries = FileSet::default();
            for (path, (id, _)) in &files {
                let virtual_path = VfsPath::new_virtual_path(format!("/workspace/{path}"));
                if path.starts_with("__lib/") || path.starts_with("__dep/") {
                    libraries.insert(*id, virtual_path)
                } else {
                    local.insert(*id, virtual_path)
                }
            }
            changes.set_roots(vec![
                SourceRoot::new_local(local),
                SourceRoot::new_library(libraries),
            ]);
            let mut graph = CrateGraphBuilder::default();
            let mut roots = BTreeMap::new();
            for c in &configuration.crates {
                let mut cfg = CfgOptions::default();
                for (key, value) in [
                    ("target_arch", "wasm32"),
                    ("target_os", "wasi"),
                    ("target_env", "p1"),
                    ("target_vendor", "unknown"),
                    ("target_family", "wasm"),
                    ("target_endian", "little"),
                    ("target_pointer_width", "32"),
                    ("panic", "abort"),
                ] {
                    cfg.insert_key_value(Symbol::intern(key), Symbol::intern(value));
                }
                for width in ["8", "16", "32", "64", "ptr"] {
                    cfg.insert_key_value(
                        Symbol::intern("target_has_atomic"),
                        Symbol::intern(width),
                    );
                }
                for feature in &c.features {
                    cfg.insert_key_value(Symbol::intern("feature"), Symbol::intern(feature));
                }
                let origin = if ["core", "alloc", "std"].contains(&c.kind.as_str()) {
                    CrateOrigin::Lang(LangCrateOrigin::from(c.kind.as_str()))
                } else if c.kind == "library" {
                    CrateOrigin::Library {
                        repo: None,
                        name: Symbol::intern(&c.name),
                    }
                } else {
                    CrateOrigin::Local {
                        repo: None,
                        name: Some(Symbol::intern(&c.name)),
                    }
                };
                let edition = c.edition.parse().map_err(|_| "Unsupported Rust edition")?;
                let target = base_db::target::TargetData {
                    arch: base_db::target::Arch::Wasm32,
                    data_layout:
                        "e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-i128:128-n32:64-S128-ni:1:10:20"
                            .into(),
                };
                let name = if c.name.is_empty() {
                    None
                } else {
                    Some(base_db::CrateDisplayName::from_canonical_name(&c.name))
                };
                let id = graph.add_crate_root(
                    files[&c.root].0,
                    edition,
                    name,
                    None,
                    cfg,
                    None,
                    Env::default(),
                    origin,
                    vec![],
                    false,
                    Arc::new(
                        "/workspace"
                            .try_into()
                            .map_err(|_| "Target path semantics reject the virtual workspace")?,
                    ),
                    Arc::new(CrateWorkspaceData {
                        target: Ok(target),
                        toolchain: Some("1.96.0".parse().unwrap()),
                    }),
                );
                if roots.insert(c.root.clone(), id).is_some() {
                    return Err("Duplicate crate root".into());
                }
            }
            for c in &configuration.crates {
                for (name, root) in &c.dependencies {
                    let name = CrateName::new(name).map_err(str::to_owned)?;
                    graph
                        .add_dep(roots[&c.root], DependencyBuilder::new(name, roots[root]))
                        .map_err(|_| "Cyclic crate graph")?
                }
            }
            changes.set_crate_graph(graph);
        }
        if structural || changed > 0 {
            self.host.apply_change(changes)
        }
        // Commit only after every path, edition and graph edge has validated.
        self.files = files;
        self.next_id = next_id;
        self.crates = configuration.crates;
        Ok(
            json!({"changedFiles":changed,"structural":structural,"files":self.files.len(),"profile":"supplied source graph, wasm32-wasip1, Rust 1.96; no external proc macros or automatic Cargo loading"}),
        )
    }
    fn update(&mut self, input: Vec<FileInput>) -> Result<Value, String> {
        if input.len() > 1024 {
            return Err("Too many changed files".into());
        }
        let mut seen = BTreeSet::new();
        let mut total = self.files.values().map(|(_, s)| s.len()).sum::<usize>();
        for f in &input {
            let (_, old) = self
                .files
                .get(&f.path)
                .ok_or("New files require a fresh graph")?;
            if f.path.starts_with("__lib/")
                || f.path.starts_with("__dep/")
                || f.text.len() > 1024 * 1024
                || !seen.insert(&f.path)
            {
                return Err("Immutable library or invalid changed file".into());
            }
            total = total - old.len() + f.text.len();
        }
        if total > 24 * 1024 * 1024 {
            return Err("Analysis source budget exceeded".into());
        }
        let mut changes = ChangeWithProcMacros::default();
        let mut count = 0;
        for f in input {
            let (id, old) = self.files.get_mut(&f.path).unwrap();
            if old != &f.text {
                changes.change_file(*id, Some(f.text.clone()));
                *old = f.text;
                count += 1
            }
        }
        if count > 0 {
            self.host.apply_change(changes)
        }
        Ok(json!({"changedFiles":count,"structural":false}))
    }
    fn position(&self, input: &Value) -> Result<FilePosition, String> {
        let path = input["file"].as_str().ok_or("Missing file")?;
        let (id, text) = self.files.get(path).ok_or("Unknown file")?;
        let n = usize::try_from(input["offset"].as_u64().ok_or("Missing UTF-8 offset")?)
            .map_err(|_| "UTF-8 offset exceeds this target")?;
        if n > text.len() || !text.is_char_boundary(n) {
            return Err("Invalid UTF-8 offset".into());
        }
        Ok(FilePosition {
            file_id: *id,
            offset: TextSize::from(n as u32),
        })
    }
    fn path(&self, id: FileId) -> String {
        self.files
            .iter()
            .find_map(|(p, (f, _))| (*f == id).then(|| p.clone()))
            .unwrap_or_default()
    }
    fn query(&self, input: Value) -> Result<Value, String> {
        let position = self.position(&input)?;
        let analysis = self.host.analysis();
        match input["op"].as_str().unwrap_or("") {
            "source" => Ok(
                json!({"text":self.files[&self.path(position.file_id)].1,"readOnly":self.path(position.file_id).starts_with("__lib/")||self.path(position.file_id).starts_with("__dep/")}),
            ),
            "definition" => {
                let result = analysis
                    .goto_definition(
                        position,
                        &ide::GotoDefinitionConfig {
                            minicore: Default::default(),
                        },
                    )
                    .map_err(|_| "Cancelled")?;
                Ok(
                    json!({"targets":result.map(|r|r.info.into_iter().map(|n|json!({"file":self.path(n.file_id),"range":range(n.focus_range.unwrap_or(n.full_range)),"name":n.name.to_string(),"description":n.description})).collect::<Vec<_>>()).unwrap_or_default()}),
                )
            }
            "references" => {
                let refs = analysis
                    .find_all_refs(
                        position,
                        &ide::FindAllRefsConfig {
                            search_scope: Some(ide_db::search::SearchScope::files(
                                &self
                                    .files
                                    .iter()
                                    .filter(|(p, _)| {
                                        !p.starts_with("__lib/") && !p.starts_with("__dep/")
                                    })
                                    .flat_map(|(_, (id, _))| {
                                        ide::Edition::iter().map(|edition| {
                                            ide_db::EditionedFileId::new(
                                                self.host.raw_database(),
                                                *id,
                                                edition,
                                            )
                                        })
                                    })
                                    .collect::<Vec<_>>(),
                            )),
                            minicore: Default::default(),
                        },
                    )
                    .map_err(|_| "Cancelled")?
                    .unwrap_or_default();
                let mut result = vec![];
                for group in refs {
                    if let Some(d) = group.declaration {
                        result.push(json!({"file":self.path(d.nav.file_id),"range":range(d.nav.focus_range.unwrap_or(d.nav.full_range)),"declaration":true}))
                    }
                    for (file, items) in group.references {
                        for (r, _) in items {
                            result.push(json!({"file":self.path(file),"range":range(r)}));
                            if result.len() > 10000 {
                                return Err("Reference limit exceeded".into());
                            }
                        }
                    }
                }
                Ok(json!({"references":result}))
            }
            "hover" => {
                let config = ide::HoverConfig {
                    links_in_hover: false,
                    memory_layout: None,
                    documentation: true,
                    keywords: false,
                    format: ide::HoverDocFormat::PlainText,
                    max_trait_assoc_items_count: Some(12),
                    max_fields_count: Some(12),
                    max_enum_variants_count: Some(12),
                    max_subst_ty_len: ide::SubstTyLen::LimitTo(64),
                    show_drop_glue: false,
                    minicore: Default::default(),
                };
                let result = analysis
                    .hover(
                        &config,
                        FileRange {
                            file_id: position.file_id,
                            range: TextRange::empty(position.offset),
                        },
                    )
                    .map_err(|_| "Cancelled")?;
                Ok(
                    json!({"hover":result.map(|v|json!({"range":range(v.range),"text":v.info.markup.as_str()}))}),
                )
            }
            "signature" => {
                let result = analysis.signature_help(position).map_err(|_| "Cancelled")?;
                Ok(
                    json!({"signature":result.map(|v|json!({"text":v.signature,"activeParameter":v.active_parameter,"parameters":v.parameter_labels().collect::<Vec<_>>()}))}),
                )
            }
            "complete" => {
                let config = completion_config();
                let mut items = analysis
                    .completions(&config, position, None)
                    .map_err(|_| "Cancelled")?
                    .unwrap_or_default();
                items.sort_by(|a, b| {
                    b.relevance
                        .score()
                        .cmp(&a.relevance.score())
                        .then_with(|| a.label.primary.cmp(&b.label.primary))
                });
                let text = &self.files[&self.path(position.file_id)].1;
                let items=items.into_iter().filter(|i|!i.is_snippet&&{
     let begin=u32::from(i.source_range.start()) as usize;let end=u32::from(position.offset) as usize;
     begin<=end&&text.get(begin..end).is_some_and(|prefix|i.lookup.starts_with(prefix))
    }).take(256).map(|i|json!({"label":i.label.primary.as_str(),"detail":i.detail,"kind":format!("{:?}",i.kind),"range":range(i.source_range),"edits":i.text_edit.iter().map(|e|json!({"range":range(e.delete),"insert":e.insert})).collect::<Vec<_>>(),"imports":i.import_to_add.into_iter().collect::<Vec<_>>()})).collect::<Vec<_>>();
                Ok(json!({"items":items}))
            }
            "completionImports" => {
                let imports = input["imports"].as_array().ok_or("Missing import paths")?;
                if imports.len() > 8 {
                    return Err("Too many imports".into());
                }
                let imports = imports
                    .iter()
                    .map(|v| {
                        v.as_str()
                            .filter(|s| s.len() <= 1024)
                            .map(str::to_owned)
                            .ok_or("Invalid import path")
                    })
                    .collect::<Result<Vec<_>, _>>()?;
                let edits = analysis
                    .resolve_completion_edits(&completion_config(), position, imports)
                    .map_err(|_| "Cancelled")?;
                Ok(
                    json!({"edits":edits.into_iter().flat_map(|e|e.iter().map(|i|json!({"range":range(i.delete),"insert":i.insert})).collect::<Vec<_>>()).collect::<Vec<_>>()}),
                )
            }
            "rename" => {
                if self.path(position.file_id).starts_with("__lib/")
                    || self.path(position.file_id).starts_with("__dep/")
                {
                    return Err("Library declarations are read-only".into());
                }
                if analysis
                    .goto_definition(
                        position,
                        &ide::GotoDefinitionConfig {
                            minicore: Default::default(),
                        },
                    )
                    .map_err(|_| "Cancelled")?
                    .is_some_and(|r| {
                        r.info.iter().any(|n| {
                            let p = self.path(n.file_id);
                            p.starts_with("__lib/") || p.starts_with("__dep/")
                        })
                    })
                {
                    return Err("Library declarations are read-only; rename a project-local symbol or alias".into());
                }
                let name = input["name"]
                    .as_str()
                    .filter(|s| s.len() <= 128)
                    .ok_or("Missing rename identifier")?;
                let result = analysis
                    .rename(
                        position,
                        name,
                        &ide::RenameConfig {
                            prefer_no_std: false,
                            prefer_prelude: true,
                            prefer_absolute: false,
                            show_conflicts: true,
                        },
                    )
                    .map_err(|_| "Cancelled")?
                    .map_err(|e| e.to_string())?;
                if result.source_file_edits.keys().any(|id| {
                    let p = self.path(*id);
                    p.starts_with("__lib/") || p.starts_with("__dep/")
                }) {
                    return Err("Rename touches an immutable library".into());
                }
                if !result.file_system_edits.is_empty() || result.is_snippet {
                    return Err(
                        "Module-file or snippet rename is outside the analysis profile".into(),
                    );
                }
                let annotations=result.annotations.values().map(|a|json!({"label":a.label,"description":a.description,"needsConfirmation":a.needs_confirmation})).collect::<Vec<_>>();
                let files=result.source_file_edits.into_iter().map(|(id,(edit,_))|json!({"file":self.path(id),"edits":edit.iter().map(|e|json!({"range":range(e.delete),"insert":e.insert})).collect::<Vec<_>>()})).collect::<Vec<_>>();
                Ok(json!({"files":files,"annotations":annotations}))
            }
            _ => Err("Unknown semantic operation".into()),
        }
    }
}
fn completion_config() -> ide::CompletionConfig<'static> {
    ide::CompletionConfig {
        enable_postfix_completions: false,
        enable_imports_on_the_fly: true,
        enable_self_on_the_fly: true,
        enable_auto_iter: false,
        enable_auto_await: false,
        enable_private_editable: false,
        enable_term_search: false,
        term_search_fuel: 0,
        full_function_signatures: true,
        callable: Some(ide::CallableSnippets::AddParentheses),
        add_semicolon_to_unit: false,
        snippet_cap: None,
        insert_use: ide_db::imports::insert_use::InsertUseConfig {
            granularity: ide_db::imports::insert_use::ImportGranularity::Crate,
            prefix_kind: hir::PrefixKind::Plain,
            enforce_granularity: true,
            group: true,
            skip_glob_imports: true,
        },
        prefer_no_std: false,
        prefer_prelude: true,
        prefer_absolute: false,
        snippets: vec![],
        limit: None,
        fields_to_resolve: ide::CompletionFieldsToResolve::empty(),
        exclude_flyimport: vec![],
        exclude_traits: &[],
        minicore: Default::default(),
    }
}
thread_local! {static ENGINE: RefCell<Engine> = RefCell::new(Engine::default());static OUTPUT:RefCell<Vec<u8>>=const{RefCell::new(Vec::new())};}
fn request(bytes: &[u8]) -> Vec<u8> {
    let result = (|| {
        if bytes.len() > 28 * 1024 * 1024 {
            return Err("Request size".to_owned());
        }
        let value: Value = serde_json::from_slice(bytes).map_err(|_| "Invalid JSON".to_owned())?;
        ENGINE.with_borrow_mut(|engine| {
            if value["op"] == "configure" {
                engine.configure(
                    serde_json::from_value(value["configuration"].clone())
                        .map_err(|_| "Invalid configuration".to_owned())?,
                )
            } else if value["op"] == "update" {
                engine.update(
                    serde_json::from_value(value["files"].clone())
                        .map_err(|_| "Invalid update".to_owned())?,
                )
            } else {
                engine.query(value)
            }
        })
    })();
    let output = serde_json::to_vec(&match result {
        Ok(v) => json!({"ok":true,"result":v}),
        Err(e) => json!({"ok":false,"error":e}),
    })
    .unwrap();
    if output.len() > 2 * 1024 * 1024 {
        br#"{"ok":false,"error":"Semantic response exceeds 2 MiB"}"#.to_vec()
    } else {
        output
    }
}
thread_local! {static INPUTS:RefCell<BTreeMap<usize,Vec<u8>>>=const{RefCell::new(BTreeMap::new())};}
#[unsafe(no_mangle)]
pub extern "C" fn crabrix_semantic_alloc(len: usize) -> usize {
    if len == 0 || len > 28 * 1024 * 1024 {
        return 0;
    }
    INPUTS.with_borrow_mut(|inputs| {
        if inputs.len() >= 2 {
            return 0;
        }
        let mut v = vec![0; len];
        let ptr = v.as_mut_ptr() as usize;
        inputs.insert(ptr, v);
        ptr
    })
}
#[unsafe(no_mangle)]
pub extern "C" fn crabrix_semantic_free(ptr: usize, len: usize) {
    INPUTS.with_borrow_mut(|inputs| {
        if inputs.get(&ptr).is_some_and(|v| v.len() == len) {
            inputs.remove(&ptr);
        }
    });
}
#[unsafe(no_mangle)]
pub extern "C" fn crabrix_semantic_request(ptr: usize, len: usize) -> usize {
    OUTPUT.with_borrow_mut(|out| {
        *out = INPUTS.with_borrow(|inputs| match inputs.get(&ptr) {
            Some(v) if v.len() == len => request(v),
            _ => br#"{"ok":false,"error":"Invalid request allocation"}"#.to_vec(),
        });
        out.as_ptr() as usize
    })
}
#[unsafe(no_mangle)]
pub extern "C" fn crabrix_semantic_output_len() -> usize {
    OUTPUT.with_borrow(|out| out.len())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn scopes_modules_dependencies_and_semantic_rename() {
        let main = "mod other; fn main(){ let value=1; { let value=2; let x=value; } let y=value; other::greet(); math::sum(1,2); }";
        let mut engine = Engine::default();
        engine
            .configure(Configuration {
                files: vec![
                    FileInput {
                        path: "src/main.rs".into(),
                        text: main.into(),
                    },
                    FileInput {
                        path: "src/other.rs".into(),
                        text: "pub fn greet() {}".into(),
                    },
                    FileInput {
                        path: "deps/math/lib.rs".into(),
                        text: "pub fn sum(a:i32,b:i32)->i32{a+b}".into(),
                    },
                ],
                crates: vec![
                    CrateInput {
                        root: "src/main.rs".into(),
                        dependencies: BTreeMap::from([("math".into(), "deps/math/lib.rs".into())]),
                        ..Default::default()
                    },
                    CrateInput {
                        root: "deps/math/lib.rs".into(),
                        dependencies: BTreeMap::new(),
                        ..Default::default()
                    },
                ],
            })
            .unwrap();
        for (needle, declaration) in [("x=value", "value=2"), ("y=value", "value=1")] {
            let at = main.find(needle).unwrap() + 2;
            let r = engine
                .query(json!({"op":"definition","file":"src/main.rs","offset":at}))
                .unwrap();
            assert_eq!(
                r["targets"][0]["range"]["start"],
                main.find(declaration).unwrap()
            );
        }
        for (needle, file) in [("greet()", "src/other.rs"), ("sum(1", "deps/math/lib.rs")] {
            let r=engine.query(json!({"op":"definition","file":"src/main.rs","offset":main.find(needle).unwrap()})).unwrap();
            assert_eq!(r["targets"][0]["file"], file);
        }
        let renamed=engine.query(json!({"op":"rename","file":"src/main.rs","offset":main.find("y=value").unwrap()+2,"name":"outer"})).unwrap();
        assert_eq!(renamed["files"][0]["edits"].as_array().unwrap().len(), 2);
        let hover = engine
            .query(
                json!({"op":"hover","file":"src/main.rs","offset":main.find("y=value").unwrap()+2}),
            )
            .unwrap();
        assert!(hover["hover"]["text"].as_str().unwrap().contains("i32"));
    }
}
