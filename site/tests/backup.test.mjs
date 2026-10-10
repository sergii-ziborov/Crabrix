import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
test('consistent backups preserve accounts, restore reapplies deletion and revokes sessions', () => {
  const folder = mkdtempSync(join(tmpdir(), 'crabrix-restore-'));
  const env = { ...process.env, AUTH_DB_PATH: join(folder, 'accounts.sqlite') };
  const authURL = new URL('../lib/auth-store.ts', import.meta.url).href;
  const script = fileURLToPath(new URL('../scripts/backup-accounts.mjs', import.meta.url));
  function run(args) {
    const result = spawnSync(process.execPath, args, { env, encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
  }
  run(['--experimental-strip-types', '--input-type=module', '-e', `const a=await import(${JSON.stringify(authURL)});await a.registerAccount('restore_test','a long test password for backup');`]);
  run([script]);
  const filename = readdirSync(join(folder, 'backups'))[0];
  run(['--experimental-strip-types', '--input-type=module', '-e', `const a=await import(${JSON.stringify(authURL)});await a.deleteAccount(1,'a long test password for backup');`]);
  run([script, '--restore', filename]);
  const sql = new DatabaseSync(env.AUTH_DB_PATH);
  assert.equal(sql.prepare('SELECT count(*) AS n FROM users').get().n, 0);
  assert.equal(sql.prepare('SELECT count(*) AS n FROM sessions').get().n, 0);
  sql.close();
});
