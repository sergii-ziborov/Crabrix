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

export function lessonPreview(lesson: Lesson, isBasics = false) {
  const summary = lesson.writing?.summary || lesson.concept;
  const rule = lesson.writing?.rule || "";
  const budget = Math.max(0, Math.floor(lessonWordCount(lesson, isBasics) * .30) - words(lesson.title) - words(summary) - words(rule));
  const explanation = lesson.writing?.explanation || lesson.algorithm?.idea || "";
  const tokens = [...explanation.matchAll(/\S+/g)];
  let prefix = tokens.length <= budget ? explanation : explanation.slice(0, tokens[budget]?.index || 0);
  // Finish at a sentence where possible and keep inline-code delimiters balanced.
  const sentenceEnd = [...prefix.matchAll(/[.!?](?:`)?(?=\s|$)/g)].at(-1);
  if (sentenceEnd && sentenceEnd.index > prefix.length * .65) prefix = prefix.slice(0, sentenceEnd.index + sentenceEnd[0].length);
  if ((prefix.match(/`/g) || []).length % 2) prefix = prefix.slice(0, prefix.lastIndexOf("`"));
  return { summary, rule, paragraphs: prefix.trim().split(/\n\s*\n/).filter(Boolean) };
}
