import { test } from 'node:test';
import assert from 'node:assert/strict';
import { workflowLanguage, workflowLanguageSupport } from '../lib/workflow-syntax.ts';
import { codeTokens } from '../lib/code-highlighting.ts';

test('route file types select their actual grammars, including extensionless config', () => {
  for (const [path, language] of [['Dockerfile','dockerfile'],['Dockerfile.release','dockerfile'],['.env.production','shell'],['migrations/001.sql','sql'],['scripts/release.sh','shell'],['requests.http','http'],['change.patch','diff'],['.github/workflows/ci.yml','yaml']]) {
    assert.equal(workflowLanguage(path), language);
    assert.equal(workflowLanguageSupport(path).length, 1);
  }
  assert.equal(workflowLanguage('src/main.rs'), undefined);
});
test('terminal command examples retain quoted SQL and HTTP arguments', () => {
  const source = `sqlite3 tasks.db 'SELECT id FROM tasks'\ncurl -H 'X-Request-ID: req_1' http://127.0.0.1:8080/tasks`;
  const tokens = codeTokens(source,'shell');
  assert.equal(tokens.map(t=>t.value).join(''), source);
  for (const command of ['sqlite3','curl']) assert.ok(tokens.some(t=>t.value===command && t.kind==='keyword'));
  assert.ok(tokens.some(t=>t.value==="'SELECT id FROM tasks'" && t.kind==='string'));
});
