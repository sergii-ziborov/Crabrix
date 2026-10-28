"use strict";
(() => {
  const pending = new Map();
  let counter = 0, worker, blobURL, stopped = false;
  const send = message => new Promise((resolve, reject) => {
    if (stopped || pending.size >= 2) { reject(new Error("Analysis is stopped or busy.")); return; }
    const id = ++counter;
    pending.set(id, { resolve, reject });
    worker.postMessage({ ...message, id }, message.kind === "initialize" ? [message.wasm, message.library] : []);
  });
  const initialized = (async () => {
    const responses = await Promise.all(["worker.js", "engine.wasm", "stdlib.json"].map(path => fetch(path)));
    if (responses.some(response => !response.ok)) throw new Error("Bundled analysis files are unavailable.");
    const [script, wasm, library] = await Promise.all([responses[0].text(), responses[1].arrayBuffer(), responses[2].arrayBuffer()]);
    blobURL = URL.createObjectURL(new Blob([script], { type: "text/javascript" }));
    worker = new Worker(blobURL);
    worker.onmessage = event => {
      const message = event.data, request = pending.get(message.id);
      if (!request) return;
      pending.delete(message.id);
      // Return errors as bounded data; source is never interpolated into HTML.
      request.resolve(JSON.stringify(message));
    };
    worker.onerror = () => {
      stopped = true;
      for (const request of pending.values()) request.reject(new Error("The analysis Worker stopped. Compiler Check is still available."));
      pending.clear(); worker.terminate();
    };
    await send({ kind: "initialize", wasm, library });
  })();
  // The native caller supplies JSON as a WebKit argument, never executable JS.
  window.crabrixSemantic = {
    request: async payload => { await initialized; return send({ ...payload, kind: "analyze" }); },
    dispose: () => {
      stopped = true; worker?.terminate(); if (blobURL) URL.revokeObjectURL(blobURL);
      for (const request of pending.values()) request.reject(new Error("Analysis stopped."));
      pending.clear();
    },
  };
  // A rejected initialization is surfaced when a caller requests analysis.
  initialized.catch(() => {});
})();
