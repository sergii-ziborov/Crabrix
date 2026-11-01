import type { Lesson } from "./courses";

const words = (text?: string) => text?.trim().split(/\s+/).filter(Boolean).length || 0;
// Count the text readers receive, without serializing an entire lesson to a client.
export function lessonWordCount(lesson: Lesson, isBasics = false) {
  const w = lesson.writing, d = lesson.depth, a = lesson.algorithm;
  const texts = [lesson.title, w?.summary || lesson.concept, w?.rule, w?.explanation,
    w?.exampleCode, w?.exampleCaption, w?.practiceCode !== w?.exampleCode ? w?.practiceCode : "",
    w?.task || a?.task, w?.success, w?.question, ...(w?.answers || []), w?.feedback,
    ...(lesson.illustration ? [lesson.illustration.caption] : []),
    d?.transferChallenge,
    ...(!isBasics && d ? [d.misconception, d.correction,
      ...(d.traceSteps || []).flatMap((step) => [step.title, step.detail]), ...(d.connections || []).flatMap((connection) => [connection.title, connection.concept])] : []),
    a?.idea, a?.useCases, a?.complexity, a?.visibleInput, a?.rustSketch, a?.expectedAnswer];
  return texts.reduce((sum, text) => sum + words(text), 0);
}

// A `.`, `!` or `?` inside inline code, as in `dbg!`, never ends a sentence.
function lastSentenceEnd(text: string) {
  let inCode = false, end = -1;
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "`") inCode = !inCode;
    else if (!inCode && ".!?".includes(text[i]) && (i + 1 === text.length || /\s/.test(text[i + 1]))) end = i + 1;
  }
  return end;
}

// The 30% budget counts code the preview never shows, so it can exceed the prose.
const MAX_EXPLANATION_SHARE = .6;

export function lessonPreview(lesson: Lesson, isBasics = false) {
  const summary = lesson.writing?.summary || lesson.concept;
  const rule = lesson.writing?.rule || "";
  const explanation = lesson.writing?.explanation || lesson.algorithm?.idea || "";
  const tokens = [...explanation.matchAll(/\S+/g)];
  const budget = Math.min(Math.floor(tokens.length * MAX_EXPLANATION_SHARE),
    Math.max(0, Math.floor(lessonWordCount(lesson, isBasics) * .30) - words(lesson.title) - words(summary) - words(rule)));
  let prefix = explanation.slice(0, tokens[budget]?.index ?? 0);
  // Finish at a sentence where possible and keep inline-code delimiters balanced.
  const sentenceEnd = lastSentenceEnd(prefix);
  if (sentenceEnd > prefix.length * .65) prefix = prefix.slice(0, sentenceEnd);
  if ((prefix.match(/`/g) || []).length % 2) prefix = prefix.slice(0, prefix.lastIndexOf("`"));
  return { summary, rule, paragraphs: prefix.trim().split(/\n\s*\n/).filter(Boolean) };
}
