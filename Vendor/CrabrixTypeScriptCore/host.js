"use strict";
(() => {
  let worker, blobURL, counter = 0, stopped = false;
  const pending = new Map();
  const dispose = () => {
    stopped = true; worker?.terminate();
    if (blobURL) URL.revokeObjectURL(blobURL);
    for (const request of pending.values()) request.reject(Error("TypeScript checking stopped."));
    pending.clear();
  };
  const send = (kind, payload, library) => new Promise((resolve, reject) => {
    if (stopped || pending.size >= 2) return reject(Error("TypeScript checker is stopped or busy."));
    const id = ++counter; pending.set(id, { resolve, reject });
    worker.postMessage({ id, kind, payload, library }, library ? [library] : []);
  });
  const ready = (async () => {
    const responses = await Promise.all(["compiler.js", "worker.js", "library.json"].map(path => fetch(path)));
    if (responses.some(response => !response.ok)) throw Error("Bundled TypeScript files are unavailable.");
    const [compiler, bridge, library] = await Promise.all([responses[0].text(), responses[1].text(), responses[2].arrayBuffer()]);
    if (stopped) throw Error("TypeScript checking stopped during initialization.");
    blobURL = URL.createObjectURL(new Blob([compiler, "\n", bridge], { type: "text/javascript" }));
    worker = new Worker(blobURL);
    worker.onmessage = event => {
      const request = pending.get(event.data.id);
      if (!request) return;
      pending.delete(event.data.id); request.resolve(JSON.stringify(event.data));
    };
    worker.onerror = dispose;
    const response = JSON.parse(await send("initialize", null, library));
    if (!response.initialized) throw Error("The pinned TypeScript compiler could not initialize.");
  })();
  ready.catch(dispose);
  window.crabrixTypeScript = { request: async payload => { await ready; return send("check", payload); }, dispose };
})();
