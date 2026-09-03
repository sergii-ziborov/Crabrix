// Serves the static site and sends www to the apex so there is one canonical
// URL. That is the whole job.
//
// Crabrix runs no service of its own: no accounts, no board, no API. Ranking
// stays on the device, and if it ever goes online it will go through Game
// Center, which Apple operates. There is deliberately nothing here to secure,
// moderate, or keep about anyone.

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.hostname.startsWith("www.")) {
      url.hostname = url.hostname.slice(4);
      return Response.redirect(url.toString(), 301);
    }

    return env.ASSETS.fetch(request);
  },
};
