// Serves the static site, sends www to the apex so there is one canonical URL,
// and backs the public rating board.
//
// There are no accounts here. A player is a random key the app generates once
// and keeps in its Keychain, so appearing on the board costs no email, no
// password, and no personal data. That also means a submission is not proof of
// anything: the endpoint is written defensively rather than trustingly.

/// How many rows the public board ever returns.
const MAX_BOARD = 100;
/// A name is a display label, not an identity. Kept short and printable.
const MAX_NAME = 24;
/// Above this a submission is rejected outright as implausible rather than
/// silently clamped, so a bug in the app is visible instead of stored.
const MAX_POINTS = 5000000;

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.hostname.startsWith("www.")) {
      url.hostname = url.hostname.slice(4);
      return Response.redirect(url.toString(), 301);
    }

    if (url.pathname === "/api/leaderboard") {
      return handleLeaderboard(request, env);
    }
    if (url.pathname === "/api/score") {
      return handleScore(request, env);
    }
    if (url.pathname === "/api/forget") {
      return handleForget(request, env);
    }

    return env.ASSETS.fetch(request);
  },
};

async function handleLeaderboard(request, env) {
  if (request.method !== "GET") {
    return json({ error: "method_not_allowed" }, 405);
  }
  if (!env.DB) {
    return json({ error: "leaderboard_unavailable" }, 503);
  }

  const url = new URL(request.url);
  const limit = clampInt(url.searchParams.get("limit"), 25, 1, MAX_BOARD);

  try {
    const { results } = await env.DB.prepare(
      `SELECT name, rank_title, points, lessons, lines_changed, achievements,
              best_recall, updated_at
         FROM players
        ORDER BY points DESC, updated_at ASC
        LIMIT ?1`,
    )
      .bind(limit)
      .all();

    const entries = (results ?? []).map((row, index) => ({
      rank: index + 1,
      name: row.name,
      title: row.rank_title,
      points: row.points,
      lessons: row.lessons,
      linesChanged: row.lines_changed,
      achievements: row.achievements,
      bestRecall: row.best_recall,
      updatedAt: row.updated_at,
    }));

    return new Response(JSON.stringify({ entries }), {
      headers: {
        "content-type": "application/json; charset=utf-8",
        // Short enough to feel live, long enough that the board is not a
        // database query per page view.
        "cache-control": "public, max-age=60",
      },
    });
  } catch {
    return json({ error: "query_failed" }, 500);
  }
}

async function handleScore(request, env) {
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  if (!env.DB) {
    return json({ error: "leaderboard_unavailable" }, 503);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const id = normaliseKey(body.key);
  if (!id) return json({ error: "invalid_key" }, 400);

  const name = normaliseName(body.name);
  if (!name) return json({ error: "invalid_name" }, 400);

  const points = asCount(body.points, MAX_POINTS);
  if (points === null) return json({ error: "invalid_points" }, 400);

  const lessons = asCount(body.lessons, 100000) ?? 0;
  const linesChanged = asCount(body.linesChanged, 100000000) ?? 0;
  const achievements = asCount(body.achievements, 1000) ?? 0;
  const bestRecall = asCount(body.bestRecall, 1000) ?? 0;
  const rankTitle = normaliseRankTitle(body.rankTitle);
  const now = Math.floor(Date.now() / 1000);

  try {
    // Points only ever go up. A reinstall that starts from zero must not wipe
    // out what the same key already published.
    await env.DB.prepare(
      `INSERT INTO players (
         id, name, rank_title, points, lessons, lines_changed,
         achievements, best_recall, created_at, updated_at
       )
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9)
       ON CONFLICT(id) DO UPDATE SET
         name          = excluded.name,
         rank_title    = CASE WHEN excluded.points >= players.points
                              THEN excluded.rank_title ELSE players.rank_title END,
         points        = MAX(players.points, excluded.points),
         lessons       = MAX(players.lessons, excluded.lessons),
         lines_changed = MAX(players.lines_changed, excluded.lines_changed),
         achievements  = MAX(players.achievements, excluded.achievements),
         best_recall   = MAX(players.best_recall, excluded.best_recall),
         updated_at    = excluded.updated_at`,
    )
      .bind(id, name, rankTitle, points, lessons, linesChanged, achievements, bestRecall, now)
      .run();

    const rankRow = await env.DB.prepare(
      `SELECT COUNT(*) + 1 AS rank
         FROM players
        WHERE points > (SELECT points FROM players WHERE id = ?1)`,
    )
      .bind(id)
      .first();

    const totalRow = await env.DB.prepare("SELECT COUNT(*) AS total FROM players").first();

    return json({ rank: rankRow?.rank ?? null, total: totalRow?.total ?? null });
  } catch {
    return json({ error: "write_failed" }, 500);
  }
}

/// Removes a player's row entirely.
///
/// Required by App Store guideline 5.1.1(v): anything the app can create on a
/// server, the reader has to be able to delete from inside the app. There is no
/// account to close, so the key alone is the whole request.
async function handleForget(request, env) {
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  if (!env.DB) {
    return json({ error: "leaderboard_unavailable" }, 503);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const id = normaliseKey(body.key);
  if (!id) return json({ error: "invalid_key" }, 400);

  try {
    const result = await env.DB.prepare("DELETE FROM players WHERE id = ?1").bind(id).run();
    // Deleting a row that is not there is a success: the caller's stated
    // intent ("I should not be on the board") is satisfied either way.
    return json({ deleted: result.meta?.changes ?? 0 });
  } catch {
    return json({ error: "delete_failed" }, 500);
  }
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

/// A key is opaque to us; we only insist it is long enough not to collide and
/// short enough not to be a payload.
function normaliseKey(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return /^[A-Za-z0-9_-]{16,64}$/.test(trimmed) ? trimmed : null;
}

/// Substrings a public display name may not contain.
///
/// Two jobs: keep slurs and sexual content off a page aimed at learners, and
/// stop anyone claiming to speak for Crabrix or Apple. It is a first pass, not a
/// complete filter — the reporting address on /support is the rest of the
/// mechanism, and a reported name can be removed from the board by hand.
const BLOCKED_NAME_PARTS = [
  // Sexual content and common slurs.
  "fuck", "shit", "cunt", "whore", "slut", "rape", "porn", "dick", "cock",
  "pussy", "bitch", "nigg", "fagg", "faggot", "retard", "kike", "spic",
  "chink", "tranny", "molest", "pedo", "nazi", "hitler",
  // Impersonation of the app, its author, or the platform.
  "crabrix team", "crabrix staff", "crabrix support", "crabrix admin",
  "official crabrix", "moderator", "admin", "administrator", "app store",
  "apple support", "apple inc",
];

/// Characters a display name may contain.
///
/// An allowlist rather than a blocklist: letters in any script, marks, digits,
/// spaces, and a few joiners. Everything else — emoji, box drawing, private-use
/// glyphs — is dropped, which keeps the table readable and rules out anything
/// drawn to look like interface chrome.
const NAME_ALLOWED = /[\p{L}\p{M}\p{N} ._'-]/gu;

/// Names are shown on a public page, so control characters, bidi overrides,
/// unsupported glyphs, runaway lengths, and abusive text are all removed here
/// rather than in the template.
function normaliseName(value) {
  if (typeof value !== "string") return null;

  const kept = (value.normalize("NFKC").match(NAME_ALLOWED) ?? []).join("");
  const cleaned = kept.replace(/\s+/g, " ").trim().slice(0, MAX_NAME);
  if (cleaned.length < 2) return null;

  // Compared with separators removed, so "a d m i n" and "f-u-c-k" do not slip
  // past a plain substring check.
  const folded = cleaned.toLowerCase().replace(/[^a-z]/g, "");
  const spaced = cleaned.toLowerCase();
  for (const part of BLOCKED_NAME_PARTS) {
    const target = part.replace(/[^a-z]/g, "");
    if (folded.includes(target) || spaced.includes(part)) return null;
  }

  return cleaned;
}

/// The rank ladder is fixed, so anything unrecognised becomes the first rung
/// rather than being echoed back onto a public page.
const RANK_TITLES = new Set([
  "Newcomer", "Apprentice", "Builder", "Borrow Checker", "Crate Author", "Rustacean",
]);

function normaliseRankTitle(value) {
  return typeof value === "string" && RANK_TITLES.has(value) ? value : "Newcomer";
}

function asCount(value, maximum) {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  const rounded = Math.floor(value);
  if (rounded < 0 || rounded > maximum) return null;
  return rounded;
}

function clampInt(raw, fallback, minimum, maximum) {
  const parsed = Number.parseInt(raw ?? "", 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(maximum, Math.max(minimum, parsed));
}
