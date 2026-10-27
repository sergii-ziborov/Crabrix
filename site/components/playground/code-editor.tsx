"use client";

import { useEffect, useRef } from "react";
import { Compartment, EditorState } from "@codemirror/state";
import { EditorView, drawSelection, highlightActiveLine, keymap, lineNumbers } from "@codemirror/view";
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

export function PlaygroundCodeEditor({ text, readOnly, preferences, onLimit, awareness, maximumBytes, filePath }: {
  filePath: string; awareness: Awareness; maximumBytes: number; text: Y.Text; readOnly: boolean; preferences: EditorPreferences; onLimit: () => void;
}) {
  const parent = useRef<HTMLDivElement>(null), view = useRef<EditorView | null>(null);
  const configuration = useRef(new Compartment());
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
      EditorState.transactionFilter.of(transaction => {
        if (!transaction.annotation(ySyncAnnotation) && transaction.docChanged && new TextEncoder().encode(transaction.newDoc.toString()).length > maximumRef.current) {
          queueMicrotask(() => onLimitRef.current()); return [];
        }
        return transaction;
      }),
      EditorView.contentAttributes.of({ "aria-label": "Rust source editor", spellcheck: "false", autocorrect: "off", autocapitalize: "off" }),
    ] });
    const editor = new EditorView({ parent: parent.current, state }); view.current = editor;
    return () => { view.current = null; editor.destroy(); undo.destroy(); };
    // Y.Text identity changes only when switching files; preferences reconfigure below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [text, filePath]);

  useEffect(() => { view.current?.dispatch({ effects: configuration.current.reconfigure(options(preferences, readOnly)) }); }, [preferences, readOnly]);
  return <div className="pg-code-editor" ref={parent} />;
}
