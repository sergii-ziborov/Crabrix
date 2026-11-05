import catalog from './screenshot-catalog.json';

type ScreenshotAsset = { src: string; width: number; height: number; capturedAt: string; surface: string };
const captures: Record<string, ScreenshotAsset> = catalog;

/** One versioned asset for the guide, product galleries and agent setup page. */
export function screenshotAsset(name: string, width = 1320, height = 2868) {
  return captures[name] ?? { src: `/screenshots/${name}.png`, width, height };
}
