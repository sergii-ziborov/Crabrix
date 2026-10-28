"use client";

import { useId, useRef, useState } from "react";

type Capture = { name: string; caption: string };
const groups: { device: string; images: Capture[] }[] = [
  { device: "iPhone", images: [
    { name: "iphone-academy", caption: "Keep courses and progress offline" },
    { name: "iphone-lesson", caption: "Read code, diagrams and explanations" },
    { name: "iphone-build", caption: "Edit and run Rust locally" },
    { name: "iphone-examples", caption: "Explore runnable code examples" },
    { name: "iphone-example-detail", caption: "Read an example, then open it in Code" },
    { name: "iphone-cyberpunk-settings", caption: "Choose a theme and protect your workspace" },
  ] },
  { device: "iPhone Duo", images: [
    { name: "duo-laptop", caption: "Write Rust in the fold-aware workspace" },
    { name: "duo-output", caption: "See the result of a local run" },
  ] },
  { device: "iPad", images: [
    { name: "ipad-build", caption: "Work with files, search and the Rust editor" },
    { name: "ipad-learn", caption: "Browse courses on the larger canvas" },
    { name: "ipad-lesson", caption: "Read illustrated Rust lessons" },
    { name: "ipad-examples", caption: "Explore code examples on iPad" },
  ] },
];

function DeviceGallery({ device, images }: typeof groups[number]) {
  const [index, setIndex] = useState(0);
  const dialog = useRef<HTMLDialogElement>(null);
  const heading = useId();
  const image = images[index];
  const move = (direction: number) => setIndex(current => (current + direction + images.length) % images.length);
  return <div className="device-gallery" aria-label={`${device} screenshots`}>
    <div className="device-gallery-heading"><h3>{device}</h3><span>{index + 1} / {images.length}</span></div>
    <figure>
      <button className="device-capture" aria-label={`Enlarge ${device} screenshot: ${image.caption}`} onClick={() => dialog.current?.showModal()}>
        <img src={`/screenshots/${image.name}.png`} alt={`${device}: ${image.caption}`} loading="lazy" />
        <span className="capture-zoom" aria-hidden="true">↗</span>
      </button>
      <figcaption aria-live="polite">{image.caption}</figcaption>
    </figure>
    <div className="gallery-controls">
      <button aria-label={`Previous ${device} screenshot`} onClick={() => move(-1)}>←</button>
      <span>Browse screenshots</span>
      <button aria-label={`Next ${device} screenshot`} onClick={() => move(1)}>→</button>
    </div>
    <dialog ref={dialog} className="capture-dialog" aria-labelledby={heading} onClick={event => { if (event.target === event.currentTarget) dialog.current?.close(); }} onKeyDown={event => {
      if (event.key === "ArrowLeft" || event.key === "ArrowRight") { event.preventDefault(); move(event.key === "ArrowLeft" ? -1 : 1); }
    }}>
      <div className="capture-dialog-heading"><h2 id={heading}>{device}</h2><button autoFocus aria-label="Close screenshot" onClick={() => dialog.current?.close()}>×</button></div>
      <img src={`/screenshots/${image.name}.png`} alt={`${device}: ${image.caption}`} />
      <div className="capture-dialog-caption"><button aria-label={`Previous enlarged ${device} screenshot`} onClick={() => move(-1)}>←</button><p>{image.caption} <span>· {index + 1} / {images.length}</span></p><button aria-label={`Next enlarged ${device} screenshot`} onClick={() => move(1)}>→</button></div>
      <a href={`/screenshots/${image.name}.png`} target="_blank" rel="noreferrer">Open original image ↗</a>
    </dialog>
  </div>;
}

export function ScreenshotGalleries() {
  return <section id="screens"><div className="site-shell">
    <h2>On the device</h2>
    <p className="section-lede">Choose a course, keep it offline, then turn an idea into a project. Browse each device gallery or open a screenshot at full size.</p>
    <div className="device-galleries">{groups.map(group => <DeviceGallery key={group.device} {...group} />)}</div>
  </div></section>;
}
