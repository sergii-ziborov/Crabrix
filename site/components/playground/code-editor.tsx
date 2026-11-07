"use client";

import { useEffect, useRef } from "react";
import { Compartment, EditorState } from "@codemirror/state";
import { EditorView, Decoration, GutterMarker, gutter, drawSelection, highlightActiveLine, keymap, lineNumbers } from "@codemirror/view";
import { defaultKeymap, indentWithTab } from "@codemirror/commands";
import { bracketMatching, indentOnInput, syntaxHighlighting, HighlightStyle, StreamLanguage, LanguageDescription } from "@codemirror/language";
import { closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete";
import { markdown } from "@codemirror/lang-markdown";
import { toml } from "@codemirror/legacy-modes/mode/toml";
import { workflowLanguageSupport } from "@/lib/workflow-syntax";
import { rust } from "@codemirror/lang-rust";
import { tags } from "@lezer/highlight";
import { yCollab, yUndoManagerKeymap, ySyncAnnotation } from "y-codemirror.next";
import * as Y from "yjs";
import type { Awareness } from "y-protocols/awareness";

export type EditorPreferences = { fontSize: number; wrap: boolean; pairs: boolean; tabSize: number };
/** Lives as long as the workspace, so switching files keeps Undo, the cursor and the scroll position. */
export type FileEditorState = { text: Y.Text; undo: Y.UndoManager; anchor: number; head: number; top: number; left: number };
export function createFileEditorState(text: Y.Text): FileEditorState { return { text, undo: new Y.UndoManager(text), anchor: 0, head: 0, top: 0, left: 0 }; }
const colors = HighlightStyle.define([
  { tag: tags.keyword, color: "var(--pg-keyword)" }, { tag: [tags.string, tags.character], color: "var(--pg-string)" },
  { tag: tags.comment, color: "var(--pg-comment)" },
  { tag: tags.inserted, color: "var(--pg-string)" }, { tag: tags.deleted, color: "var(--pg-keyword)" }, { tag: [tags.typeName, tags.className], color: "var(--pg-type)" },
  { tag: [tags.number, tags.bool], color: "var(--pg-number)" }, { tag: tags.macroName, color: "var(--pg-macro)" },
]);

class BreakpointMarker extends GutterMarker {
  constructor(private line: number, private active: boolean, private toggle: () => void) { super(); }
  eq(other: BreakpointMarker) { return this.line === other.line && this.active === other.active; }
  toDOM() { const marker = document.createElement("button"); marker.className = this.active ? "cm-breakpoint cm-breakpoint-set" : "cm-breakpoint"; marker.title = `${this.active ? "Remove" : "Add"} breakpoint at line ${this.line}`; marker.setAttribute("aria-label", marker.title); marker.onclick = this.toggle; marker.textContent = "●"; return marker; }
}
export function PlaygroundCodeEditor({ fileState, readOnly, preferences, onLimit, awareness, maximumBytes, filePath, breakpoints = [], currentLine, onBreakpoint }: {
  filePath: string; awareness: Awareness; maximumBytes: number; fileState: FileEditorState; readOnly: boolean; preferences: EditorPreferences; onLimit: () => void;
  breakpoints?: number[]; currentLine?: number; onBreakpoint?: (line: number) => void;
}) {
  const text = fileState.text;
  const parent = useRef<HTMLDivElement>(null), view = useRef<EditorView | null>(null);
  const configuration = useRef(new Compartment());
  const debugConfiguration = useRef(new Compartment());
  const breakpointAction = useRef(onBreakpoint); breakpointAction.current = onBreakpoint;
  const debugOptions = (points: number[], line?: number) => [
    gutter({ class: "cm-debug-gutter", renderEmptyElements: true, lineMarker: (view, block) => { const number = view.state.doc.lineAt(block.from).number; return new BreakpointMarker(number, points.includes(number), () => breakpointAction.current?.(number)); } }),
    EditorView.decorations.of(view => line && line <= view.state.doc.lines ? Decoration.set([Decoration.line({ class: "cm-debug-current-line" }).range(view.state.doc.line(line).from)]) : Decoration.none),
  ];
  const onLimitRef = useRef(onLimit); onLimitRef.current = onLimit;
  const maximumRef = useRef(maximumBytes); maximumRef.current = maximumBytes;
  const options = (prefs: EditorPreferences, locked: boolean) => [
    EditorView.theme({ "&": { fontSize: `${prefs.fontSize}px` }, ".cm-content": { caretColor: "var(--pg-text)" } }),
    EditorState.readOnly.of(locked), EditorView.editable.of(!locked), EditorState.tabSize.of(prefs.tabSize),
    ...(prefs.wrap ? [EditorView.lineWrapping] : []), ...(prefs.pairs ? [closeBrackets()] : []),
  ];

  useEffect(() => {
    if (!parent.current) return;
    const undo = fileState.undo, length = text.length;
    const state = EditorState.create({ doc: text.toString(), selection: { anchor: Math.min(fileState.anchor, length), head: Math.min(fileState.head, length) }, extensions: [
      lineNumbers(), highlightActiveLine(), drawSelection(), indentOnInput(), bracketMatching(), ...(filePath.endsWith(".rs") ? [rust()] : filePath.endsWith(".toml") ? [StreamLanguage.define(toml)] : filePath.endsWith(".md") ? [markdown({ codeLanguages: [LanguageDescription.of({ name: "Rust", alias: ["rs"], support: rust() })] })] : workflowLanguageSupport(filePath)), syntaxHighlighting(colors),
      keymap.of([...yUndoManagerKeymap, ...closeBracketsKeymap, ...defaultKeymap, indentWithTab]),
      yCollab(text, awareness, { undoManager: undo }),
      configuration.current.of(options(preferences, readOnly)),
      debugConfiguration.current.of(debugOptions(breakpoints, currentLine)),
      EditorState.transactionFilter.of(transaction => {
        // An edit that shortens the file is always allowed, so an oversized file can be fixed.
        const size = (doc: typeof transaction.newDoc) => new TextEncoder().encode(doc.toString()).length;
        if (!transaction.annotation(ySyncAnnotation) && transaction.docChanged && size(transaction.newDoc) > maximumRef.current && size(transaction.newDoc) > size(transaction.startState.doc)) {
          queueMicrotask(() => onLimitRef.current()); return [];
        }
        return transaction;
      }),
      EditorView.contentAttributes.of({ "aria-label": "Rust source editor", spellcheck: "false", autocorrect: "off", autocapitalize: "off" }),
    ] });
    const editor = new EditorView({ parent: parent.current, state }); view.current = editor;
    // CodeMirror hides decorative gutters from accessibility by default. Our
    // breakpoint buttons are interactive; keep only line-number text hidden.
    editor.dom.querySelector(".cm-gutters")?.removeAttribute("aria-hidden");
    editor.dom.querySelector(".cm-lineNumbers")?.setAttribute("aria-hidden", "true");
    editor.scrollDOM.scrollTo(fileState.left, fileState.top);
    return () => {
      const selection = editor.state.selection.main;
      fileState.anchor = selection.anchor; fileState.head = selection.head;
      fileState.top = editor.scrollDOM.scrollTop; fileState.left = editor.scrollDOM.scrollLeft;
      view.current = null; editor.destroy();
    };
    // Y.Text identity changes only when switching files; preferences reconfigure below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fileState, filePath]);

  useEffect(() => { view.current?.dispatch({ effects: configuration.current.reconfigure(options(preferences, readOnly)) }); }, [preferences, readOnly]);
  useEffect(() => { view.current?.dispatch({ effects: debugConfiguration.current.reconfigure(debugOptions(breakpoints, currentLine)) }); if (currentLine && view.current && currentLine <= view.current.state.doc.lines) view.current.dispatch({ effects: EditorView.scrollIntoView(view.current.state.doc.line(currentLine).from, { y: "nearest" }) }); }, [breakpoints, currentLine, text]);
  return <div className="pg-code-editor" ref={parent} />;
}
