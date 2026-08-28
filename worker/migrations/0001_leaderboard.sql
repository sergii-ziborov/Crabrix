-- One row per player. There are no accounts: the id is a random key the app
-- generates once and keeps in the Keychain, so nobody hands over an email or a
-- password to appear on the board.
CREATE TABLE IF NOT EXISTS players (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  rank_title    TEXT NOT NULL,
  points        INTEGER NOT NULL,
  lessons       INTEGER NOT NULL DEFAULT 0,
  lines_changed INTEGER NOT NULL DEFAULT 0,
  achievements  INTEGER NOT NULL DEFAULT 0,
  best_recall   INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);

-- The board is always read in one order, so index for exactly that.
CREATE INDEX IF NOT EXISTS players_by_points ON players (points DESC, updated_at ASC);
