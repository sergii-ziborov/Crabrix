import { DatabaseSync } from 'node:sqlite';
import { createHash } from 'node:crypto';
import { chmodSync, copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
const databasePath = process.env.AUTH_DB_PATH || '/data/accounts.sqlite';
const folder = dirname(databasePath), backups = join(folder, 'backups');
const retention = 7 * 24 * 60 * 60 * 1000;
const ledgerFolder = join(folder, 'deletions');
const ledgerFiles = existsSync(ledgerFolder) ? readdirSync(ledgerFolder).filter(file => /^\d{4}-\d{2}-\d{2}\.jsonl$/.test(file)) : [];

if (process.argv[2] === '--restore') {
  // Stop the website first. Restore the consistent snapshot and reapply deletions.
  const filename = process.argv[3] || '';
  if (!/^accounts-\d+\.sqlite$/.test(filename)) throw new Error('Supply a backup filename inside /data/backups.');
  const source = join(backups, basename(filename));
  if (!existsSync(source)) throw new Error('Backup not found.');
  for (const suffix of ['', '-wal', '-shm']) rmSync(databasePath + suffix, { force: true });
  copyFileSync(source, databasePath);
  const sql = new DatabaseSync(databasePath);
  sql.exec('PRAGMA foreign_keys=ON;');
  const deletions = ledgerFiles.flatMap(file => readFileSync(join(ledgerFolder, file), 'utf8').split('\n').filter(Boolean).map(line => JSON.parse(line)));
  const deleted = new Set(deletions.map(item => item.identityHash));
  for (const user of sql.prepare('SELECT id,username,created_at FROM users').all()) {
    const hash = createHash('sha256').update(`${user.username}:${user.created_at}`).digest('hex');
    if (deleted.has(hash)) sql.prepare('DELETE FROM users WHERE id=?').run(user.id);
  }
  sql.exec('DELETE FROM sessions; DELETE FROM rate_limits;');
  sql.close();
  chmodSync(databasePath, 0o600);
  console.log('Account backup restored; deletions reapplied; all sessions revoked.');
} else if (existsSync(databasePath)) {
  mkdirSync(backups, { recursive: true, mode: 0o700 });
  const sql = new DatabaseSync(databasePath);
  sql.exec('PRAGMA busy_timeout=5000;');
  sql.prepare('DELETE FROM sessions WHERE expires_at < ?').run(Date.now());
  sql.prepare('DELETE FROM rate_limits WHERE expires_at < ?').run(Date.now());
  const filename = join(backups, `accounts-${Date.now()}.sqlite`);
  sql.prepare('VACUUM INTO ?').run(filename);
  sql.close();
  chmodSync(filename, 0o600);
  for (const file of readdirSync(backups)) {
    const match = file.match(/^accounts-(\d+)\.sqlite$/);
    if (match && Number(match[1]) < Date.now() - retention) rmSync(join(backups, file));
  }
  // Prune only whole, expired day files; never rewrite the file accepting new deletions.
  for (const file of ledgerFiles) {
    if (Date.parse(file.slice(0, 10)) + 24 * 60 * 60 * 1000 < Date.now() - retention) rmSync(join(ledgerFolder, file));
  }
  console.log('Account backup saved; seven-day retention applied.');
}
