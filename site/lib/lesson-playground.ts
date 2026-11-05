import { validatePlaygroundDocument, type PlaygroundDocument } from './playground-document.ts';

// The validator deliberately uses a null-prototype path map. RSC requires a
// plain object at the server/client boundary; retain validation before copying.
export function lessonPlayground(input: unknown): PlaygroundDocument {
  const document = validatePlaygroundDocument(input);
  return { ...document, files: { ...document.files } };
}
