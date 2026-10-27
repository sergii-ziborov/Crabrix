"use client";

import { useEffect, useRef } from "react";
import { Compartment, EditorState } from "@codemirror/state";
import { EditorView, Decoration, GutterMarker, gutter, drawSelection, highlightActiveLine, keymap, lineNumbers } from "@codemirror/view";
import { defaultKeymap, indentWithTab } from "@codemirror/commands";
import { bracketMatching, indentOnInput, syntaxHighlighting, HighlightStyle, StreamLanguage, LanguageDescription } from "@codemirror/language";
import { closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete";
import { markdown } from "@codemirror/lang-markdown";
import { toml } from "@codemirror/legacy-modes/mode/toml";
import { rust } from "@codemirror/lang-rust";
import { tags } from "@lezer/highlight";
import { yCollab, yUndoManagerKeymap, ySyncAnnotation } from "y-codemirror.next";
import * as Y from "yjs";
import type { Awareness } from "y-protocols/awareness";

export type EditorPreferences = { fontSize: number; wrap: boolean; pairs: boolean; tabSize: number };
const colors = HighlightStyle.define([
  { tag: tags.keyword, color: "var(--pg-keyword)" }, { tag: [tags.string, tags.character], color: "var(--pg-string)" },
  { tag: tags.comment, color: "var(--pg-comment)" }, { tag: [tags.typeName, tags.className], color: "var(--pg-type)" },
  { tag: [tags.number, tags.bool], color: "var(--pg-number)" }, { tag: tags.macroName, color: "var(--pg-macro)" },
]);

class BreakpointMarker extends GutterMarker {
  constructor(private line: number, private active: boolean, private toggle: () => void) { super(); }
  eq(other: BreakpointMarker) { return this.line === other.line && this.active === other.active; }
  toDOM() { const marker = document.createElement("button"); marker.className = this.active ? "cm-breakpoint cm-breakpoint-set" : "cm-breakpoint"; marker.title = `${this.active ? "Remove" : "Add"} breakpoint at line ${this.line}`; marker.setAttribute("aria-label", marker.title); marker.onclick = this.toggle; marker.textContent = "●"; return marker; }
}
export function PlaygroundCodeEditor({ text, readOnly, preferences, onLimit, awareness, maximumBytes, filePath, breakpoints = [], currentLine, onBreakpoint }: {
  filePath: string; awareness: Awareness; maximumBytes: number; text: Y.Text; readOnly: boolean; preferences: EditorPreferences; onLimit: () => void;
  breakpoints?: number[]; currentLine?: number; onBreakpoint?: (line: number) => void;
}) {
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
    const undo = new Y.UndoManager(text);
    const state = EditorState.create({ doc: text.toString(), extensions: [
      lineNumbers(), highlightActiveLine(), drawSelection(), indentOnInput(), bracketMatching(), ...(filePath.endsWith(".rs") ? [rust()] : filePath.endsWith(".toml") ? [StreamLanguage.define(toml)] : filePath.endsWith(".md") ? [markdown({ codeLanguages: [LanguageDescription.of({ name: "Rust", alias: ["rs"], support: rust() })] })] : []), syntaxHighlighting(colors),
      keymap.of([...yUndoManagerKeymap, ...closeBracketsKeymap, ...defaultKeymap, indentWithTab]),
      yCollab(text, awareness, { undoManager: undo }),
      configuration.current.of(options(preferences, readOnly)),
      debugConfiguration.current.of(debugOptions(breakpoints, currentLine)),
      EditorState.transactionFilter.of(transaction => {
        if (!transaction.annotation(ySyncAnnotation) && transaction.docChanged && new TextEncoder().encode(transaction.newDoc.toString()).length > maximumRef.current) {
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
    return () => { view.current = null; editor.destroy(); undo.destroy(); };
    // Y.Text identity changes only when switching files; preferences reconfigure below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [text, filePath]);

  useEffect(() => { view.current?.dispatch({ effects: configuration.current.reconfigure(options(preferences, readOnly)) }); }, [preferences, readOnly]);
  useEffect(() => { view.current?.dispatch({ effects: debugConfiguration.current.reconfigure(debugOptions(breakpoints, currentLine)) }); if (currentLine && view.current && currentLine <= view.current.state.doc.lines) view.current.dispatch({ effects: EditorView.scrollIntoView(view.current.state.doc.line(currentLine).from, { y: "nearest" }) }); }, [breakpoints, currentLine, text]);
  return <div className="pg-code-editor" ref={parent} />;
}
