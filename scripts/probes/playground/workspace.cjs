// Browser acceptance for the Playground workspace. Runs against a local site:
//   ORIGIN=http://localhost:3393 node scripts/probes/playground/workspace.cjs
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/serhiirihgt/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const assert = require('node:assert/strict');
const origin = process.env.ORIGIN || 'http://localhost:3393';

const results = [];
async function scenario(name, work) {
  try { await work(); results.push(['ok', name]); console.log('ok  ', name); }
  catch (error) { results.push(['FAIL', name]); console.log('FAIL', name, '\n  ', String(error.message).split('\n').slice(0, 6).join('\n   ')); }
}

(async () => {
  const browser = await chromium.launch();
  const fresh = async (viewport = { width: 1280, height: 900 }) => {
    const context = await browser.newContext({ viewport });
    await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin });
    const page = await context.newPage();
    const errors = []; page.on('pageerror', error => errors.push(error.message)); page.errors = errors;
    return { context, page };
  };
  const open = async (page, url = '/playground/') => { await page.goto(origin + url); await page.waitForSelector('.cm-content'); };
  const button = (page, name) => page.getByRole('button', { name, exact: true });
  const fileRow = (page, name) => page.getByRole('treeitem', { name: new RegExp(name.replace('.', '\\.')) });
  const openFile = (page, name) => fileRow(page, name).locator('.pg-tree-open').click();
  const addFile = async (page, path) => {
    await button(page, 'Add source file').click();
    await page.locator('.pg-file-form').getByLabel('Path').fill(path);
    await page.locator('.pg-file-form').getByRole('button', { name: 'New file' }).click();
    await page.waitForSelector('dialog.pg-dialog:not([open])', { state: 'attached' });
  };
  const fileList = page => page.locator('[role=treeitem] .pg-tree-name').allTextContents();
  const editorText = page => page.locator('.cm-content').innerText();
  const uploadFiles = (page, label, files) => page.getByLabel(label, { exact: true }).setInputFiles(files.map(([name, text]) => ({ name, mimeType: 'text/plain', buffer: Buffer.from(text) })));

  await scenario('T01 choosing a file changes nothing until Apply, and Add keeps the project', async () => {
    const { context, page } = await fresh(); await open(page);
    await addFile(page, 'bubble_sort.rs');
    await button(page, 'Import').click();
    await uploadFiles(page, 'Files', [['example.rs', 'pub fn e() {}\n']]);
    await page.getByRole('button', { name: 'Review' }).waitFor();
    assert.deepEqual((await fileList(page)).sort(), ['bubble_sort.rs', 'main.rs']);
    await page.getByRole('button', { name: 'Review' }).click();
    await page.getByRole('button', { name: 'Apply' }).click();
    assert.deepEqual((await fileList(page)).sort(), ['bubble_sort.rs', 'example.rs', 'main.rs']);
    assert.deepEqual(page.errors, []); await context.close();
  });

  await scenario('T02 Replace followed by Cancel applies nothing', async () => {
    const { context, page } = await fresh(); await open(page);
    await button(page, 'Import').click();
    await uploadFiles(page, 'Files', [['other.rs', 'fn main() {}\n']]);
    await page.getByLabel('How to apply').selectOption('replace');
    await page.getByRole('button', { name: 'Review' }).click();
    await page.getByText('1 added · 0 replaced · 1 removed').waitFor();
    await button(page, 'Cancel').click();
    assert.deepEqual(await fileList(page), ['main.rs']);
    await context.close();
  });

  await scenario('T04 a slow GitHub answer after Cancel changes nothing', async () => {
    const { context, page } = await fresh(); await open(page);
    let release; const held = new Promise(resolve => { release = resolve; });
    await context.route('https://api.github.com/**', async route => { await held; await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ default_branch: 'main' }) }); });
    await button(page, 'Import').click();
    await page.getByLabel(/Repository, folder, file/).fill('https://github.com/o/r');
    await button(page, 'List files').click();
    await page.locator('dialog').getByRole('button', { name: 'Cancel' }).click();
    release(); await page.waitForTimeout(300);
    assert.equal(await page.locator('dialog[open]').count(), 0);
    assert.deepEqual(await fileList(page), ['main.rs']);
    await context.close();
  });

  await scenario('T03 another participant typing behind a preview forces a refreshed result', async () => {
    const { context, page } = await fresh(); await open(page);
    await button(page, 'Share Playground').click();
    await page.getByRole('button', { name: /Create share link/ }).click();
    await page.getByRole('button', { name: 'Copy Playground link' }).waitFor();
    await button(page, 'Close').click();
    await page.getByText('Connected').waitFor({ timeout: 15000 });
    const guest = await fresh(); await open(guest.page, page.url().replace(origin, ''));
    await guest.page.getByText('Connected').waitFor({ timeout: 15000 });
    await button(page, 'Import').click();
    await uploadFiles(page, 'Files', [['a.rs', '// a\n']]);
    await page.getByRole('button', { name: 'Review' }).click();
    await page.getByRole('button', { name: 'Apply' }).waitFor();
    await guest.page.locator('.cm-content').click(); await guest.page.keyboard.type('// from-guest\n');
    await page.waitForFunction(() => document.querySelector('.cm-content')?.innerText.includes('from-guest'), null, { timeout: 8000 });
    await page.getByRole('button', { name: 'Apply' }).click();
    await page.getByText('The project changed while this preview was open').waitFor();
    assert.deepEqual(await fileList(page), ['main.rs']);
    await page.getByRole('button', { name: 'Apply' }).click();
    await page.waitForFunction(() => document.querySelectorAll('[role=treeitem]').length === 2);
    await guest.page.waitForFunction(() => document.querySelectorAll('[role=treeitem]').length === 2, null, { timeout: 8000 });
    assert.match(await editorText(guest.page), /from-guest/, 'the guest edit survives the import');
    await guest.context.close(); await context.close();
  });

  await scenario('T09 a conflict needs a choice and can keep both files', async () => {
    const { context, page } = await fresh(); await open(page);
    await button(page, 'Import').click();
    await uploadFiles(page, 'Files', [['main.rs', 'fn main() { println!("new"); }\n']]);
    await page.getByRole('button', { name: 'Review' }).click();
    assert.equal(await page.getByRole('button', { name: 'Apply' }).isDisabled(), true);
    await page.getByRole('combobox', { name: /^main\.rs/ }).selectOption('rename');
    await page.getByRole('button', { name: 'Apply' }).click();
    assert.deepEqual((await fileList(page)).sort(), ['main-imported.rs', 'main.rs']);
    assert.match(await editorText(page), /Hello, Crabrix/);
    await context.close();
  });

  await scenario('T49 a local draft has no room timer and stays editable', async () => {
    const { context, page } = await fresh();
    await page.clock.install();
    await open(page);
    await page.getByText('no time limit').waitFor();
    await page.clock.fastForward(2 * 3600 * 1000);
    await page.waitForTimeout(100);
    await page.getByText('no time limit').waitFor();
    assert.equal(await button(page, 'Import').isDisabled(), false);
    assert.equal(await page.locator('.cm-content').getAttribute('contenteditable'), 'true');
    await context.close();
  });

  await scenario('T50 leaving through a site link asks first, and coming back restores the draft', async () => {
    const { context, page } = await fresh(); await open(page);
    await page.locator('.cm-content').click(); await page.keyboard.type('// keep me\n');
    await page.locator('.site-nav').getByRole('link', { name: 'Guide' }).click();
    await page.getByRole('heading', { name: 'Leave this page?' }).waitFor();
    assert.match(page.url(), /\/playground\/$/);
    await button(page, 'Stay').click();
    assert.match(await editorText(page), /keep me/);
    await context.close();
    const back = await fresh(); await back.page.goto(origin + '/');
    await back.page.locator('.site-nav').getByRole('link', { name: 'Playground' }).click();
    await back.page.waitForSelector('.cm-content');
    await back.page.locator('.cm-content').click(); await back.page.keyboard.type('// keep me too\n');
    await back.page.goBack(); await back.page.waitForURL(origin + '/');
    await back.page.locator('.site-nav').getByRole('link', { name: 'Playground' }).click();
    await back.page.waitForSelector('.cm-content');
    await back.page.locator('.pg-notice').first().getByText('Your unsaved draft from this visit is back').waitFor();
    assert.match(await editorText(back.page), /keep me too/);
    await back.context.close();
  });

  await scenario('T52 Undo survives switching files and does not cross into another file', async () => {
    const { context, page } = await fresh(); await open(page);
    await page.locator('.cm-content').click();
    await page.keyboard.press('Control+End'); await page.keyboard.press('Meta+ArrowDown');
    await page.keyboard.type('// typed-in-main');
    await addFile(page, 'helper.rs');
    await page.locator('.cm-content').click(); await page.keyboard.type('// typed-in-helper');
    await openFile(page, 'main.rs');
    assert.match(await editorText(page), /typed-in-main/);
    await page.locator('.cm-content').click();
    await page.keyboard.press(process.platform === 'darwin' ? 'Meta+z' : 'Control+z');
    await page.waitForTimeout(100);
    assert.doesNotMatch(await editorText(page), /typed-in-main/);
    await openFile(page, 'helper.rs');
    assert.match(await editorText(page), /typed-in-helper/);
    await context.close();
  });

  await scenario('T25 the tree works from the keyboard, with folders first and a menu', async () => {
    const { context, page } = await fresh(); await open(page);
    await addFile(page, 'src/parser/lexer.rs');
    await addFile(page, 'README.md');
    const names = await fileList(page);
    assert.deepEqual(names, ['src', 'parser', 'lexer.rs', 'main.rs', 'README.md']);
    await fileRow(page, 'src').first().focus();
    await page.keyboard.press('ArrowLeft');
    assert.deepEqual(await fileList(page), ['src', 'main.rs', 'README.md']);
    await page.keyboard.press('ArrowDown');
    assert.equal(await page.evaluate(() => document.activeElement.getAttribute('title')), 'main.rs');
    await page.keyboard.press('End');
    assert.equal(await page.evaluate(() => document.activeElement.getAttribute('title')), 'README.md');
    await page.keyboard.press('Enter');
    await page.waitForFunction(() => document.querySelector('.pg-file-bar strong')?.textContent === 'README.md');
    await page.keyboard.press('F2');
    await page.getByRole('heading', { name: 'Rename' }).waitFor();
    await page.locator('.pg-file-form').getByLabel('Path').fill('docs/README.md');
    await page.locator('.pg-file-form').getByRole('button', { name: 'Rename' }).click();
    await page.waitForFunction(() => document.querySelector('.pg-file-bar strong')?.textContent === 'docs/README.md');
    await button(page, 'Find file').click();
    await page.getByPlaceholder('Find file').fill('lexer');
    assert.deepEqual(await fileList(page), ['src', 'parser', 'lexer.rs']);
    await page.getByPlaceholder('Find file').press('Escape');
    assert.ok((await fileList(page)).includes('main.rs'));
    assert.deepEqual(page.errors, []); await context.close();
  });

  await scenario('deleting a folder holding the entry asks for a new entry; a touch phone reaches the menu', async () => {
    const { context, page } = await fresh({ width: 390, height: 844 }); await open(page);
    await button(page, '☷ Files').click();
    await addFile(page, 'src/a.rs');
    await button(page, '☷ Files').click();
    await page.getByRole('button', { name: 'Actions for main.rs' }).click();
    await page.getByRole('menuitem', { name: 'Delete' }).click();
    assert.equal(await page.locator('.pg-file-form').getByRole('button', { name: 'Delete' }).isDisabled(), true);
    await page.getByLabel('New entry file').selectOption('src/a.rs');
    await page.locator('.pg-file-form').getByRole('button', { name: 'Delete' }).click();
    await page.waitForFunction(() => document.querySelector('.pg-file-bar strong')?.textContent === 'src/a.rs');
    assert.deepEqual(page.errors, []); await context.close();
  });

  await scenario('T26 a theme chosen in the Playground holds across the site and a reload', async () => {
    const { context, page } = await fresh(); await open(page);
    await button(page, 'Editor settings').click();
    await button(page, 'Cyberpunk ●').or(button(page, 'Cyberpunk ○')).click();
    assert.equal(await page.evaluate(() => document.documentElement.dataset.theme), 'cyberpunk');
    await button(page, 'Close').click();
    const editor = await page.evaluate(() => getComputedStyle(document.querySelector('.pg-workspace')).getPropertyValue('--pg-bg').trim());
    assert.equal(editor, '#060c14');
    await page.goto(origin + '/guide/');
    assert.equal(await page.evaluate(() => document.documentElement.dataset.theme), 'cyberpunk');
    assert.equal(await page.evaluate(() => getComputedStyle(document.body).backgroundColor), 'rgb(6, 12, 20)');
    await page.waitForFunction(() => document.querySelector('.site-theme select').value === 'cyberpunk');
    await page.reload();
    assert.equal(await page.evaluate(() => document.documentElement.dataset.theme), 'cyberpunk');
    await context.close();
  });

  await scenario('T27 the old preference moves over once, Auto follows the system, other tabs follow', async () => {
    const { context, page } = await fresh();
    await page.addInitScript(() => { if (!sessionStorage.getItem('seeded')) { sessionStorage.setItem('seeded', '1'); localStorage.setItem('crabrix.playground.preferences.v1', JSON.stringify({ theme: 'amber', fontSize: 15 })); } });
    await page.goto(origin + '/');
    assert.equal(await page.evaluate(() => document.documentElement.dataset.theme), 'amber');
    assert.equal(await page.evaluate(() => localStorage.getItem('crabrix.theme.v1')), 'amber');
    const other = await context.newPage(); await other.goto(origin + '/about/');
    await page.locator('.site-theme select').selectOption('system');
    await page.emulateMedia({ colorScheme: 'light' });
    await page.waitForFunction(() => document.documentElement.dataset.theme === 'light');
    await page.emulateMedia({ colorScheme: 'dark' });
    await page.waitForFunction(() => document.documentElement.dataset.theme === 'dark');
    await page.locator('.site-theme select').selectOption('light');
    await page.emulateMedia({ colorScheme: 'dark' });
    await page.waitForTimeout(150);
    assert.equal(await page.evaluate(() => document.documentElement.dataset.theme), 'light');
    await other.waitForFunction(() => document.documentElement.dataset.theme === 'light');
    await context.close();
  });

  await scenario('editor settings reset does not touch the site theme', async () => {
    const { context, page } = await fresh(); await open(page);
    await page.locator('.site-theme select').selectOption('amber');
    await button(page, 'Editor settings').click();
    await button(page, 'Reset editor preferences').click();
    assert.equal(await page.evaluate(() => document.documentElement.dataset.theme), 'amber');
    await context.close();
  });

  let shared;
  await scenario('T19 a shared room closes rename and delete, and T51 Copy to local detaches', async () => {
    const { context, page } = await fresh(); await open(page);
    await addFile(page, 'helper.rs');
    await button(page, 'Share Playground').click();
    await page.getByRole('button', { name: /Create share link/ }).click();
    await page.getByRole('button', { name: 'Copy Playground link' }).waitFor();
    shared = page.url(); assert.match(shared, /\/playground\/room\/.*#key=/);
    await button(page, 'Close').click();
    await page.getByText('Connected').waitFor({ timeout: 15000 });
    await page.getByRole('button', { name: 'Actions for helper.rs' }).click();
    assert.equal(await page.getByRole('menuitem', { name: 'Delete' }).isDisabled(), true);
    assert.equal(await page.getByRole('menuitem', { name: 'Rename' }).isDisabled(), true);
    assert.equal(await page.getByRole('menuitem', { name: 'Duplicate' }).isDisabled(), false);
    await page.keyboard.press('Escape');

    const guest = await fresh(); await open(guest.page, shared.replace(origin, ''));
    await guest.page.getByText('Connected').waitFor({ timeout: 15000 });
    await button(guest.page, 'Copy to local').click();
    await guest.page.getByText('no time limit').waitFor();
    assert.equal(guest.page.url(), origin + '/playground/');
    await guest.page.locator('.cm-content').click(); await guest.page.keyboard.type('// only-in-copy\n');
    assert.deepEqual((await fileList(guest.page)).sort(), ['helper.rs', 'main.rs']);
    await page.waitForTimeout(1200);
    assert.doesNotMatch(await editorText(page), /only-in-copy/, 'the copy must not reach the room');
    guest.page.once('dialog', dialog => dialog.accept());
    await guest.page.reload();
    await guest.page.waitForSelector('.cm-content');
    assert.equal(guest.page.url(), origin + '/playground/');
    await guest.context.close();

    const viewLink = await page.evaluate(() => null);
    assert.equal(viewLink, null);
    await button(page, 'Share Playground').click();
    const view = await page.getByLabel('View-only link').inputValue();
    await button(page, 'Close').click();
    const viewer = await fresh(); await open(viewer.page, view.replace(origin, ''));
    await viewer.page.getByText('view only').waitFor({ timeout: 15000 });
    assert.equal(await button(viewer.page, 'Import').isDisabled(), true);
    await button(viewer.page, 'Copy to local').click();
    await viewer.page.getByText('no time limit').waitFor();
    assert.equal(await button(viewer.page, 'Import').isDisabled(), false, 'a viewer can edit their own copy');
    await viewer.context.close();
    await context.close();
  });

  await scenario('an expired room keeps its text and Copy to local carries on, with a leave warning', async () => {
    const { context, page } = await fresh();
    await page.clock.install();
    await open(page);
    await page.locator('.cm-content').click(); await page.keyboard.type('// written-before-expiry\n');
    await button(page, 'Share Playground').click();
    await page.getByRole('button', { name: /Create share link/ }).click();
    await page.getByRole('button', { name: 'Copy Playground link' }).waitFor();
    await button(page, 'Close').click();
    await page.getByText('Connected').waitFor({ timeout: 15000 });
    await page.clock.fastForward(2 * 3600 * 1000);
    await page.getByText('Room expired').waitFor();
    assert.match(await editorText(page), /written-before-expiry/);
    assert.equal(await button(page, 'Run').count() ? await page.getByRole('button', { name: '▶ Run' }).isDisabled() : true, true);
    await page.locator('.site-nav').getByRole('link', { name: 'Guide' }).click();
    await page.getByRole('heading', { name: 'Leave this page?' }).waitFor();
    await button(page, 'Stay').click();
    await button(page, 'Copy to local').click();
    await page.getByText('no time limit').waitFor();
    assert.equal(page.url(), origin + '/playground/');
    assert.equal(await page.locator('.cm-content').getAttribute('contenteditable'), 'true');
    assert.match(await editorText(page), /written-before-expiry/);
    await context.close();
  });

  await scenario('AI-01 Connect AI gives one setup per agent and an agent link with a task', async () => {
    const { context, page } = await fresh(); await open(page);
    await button(page, 'Connect AI').click();
    await page.getByText('claude mcp add --transport http crabrix-room').waitFor();
    await page.getByText('Add custom connector').waitFor();
    await page.getByText('which decrypts this room').waitFor();
    await page.getByRole('tab', { name: 'Codex' }).click();
    await page.getByText('codex mcp add crabrix-room --url').waitFor();
    await page.getByRole('tab', { name: 'Cursor' }).click();
    await button(page, 'Add to Cursor').waitFor();
    await page.getByRole('tab', { name: 'Grok' }).click();
    await page.getByText('New connector → Custom').waitFor();
    await page.getByLabel('Task (optional)').fill('Split the sort.');
    assert.equal(page.url(), origin + '/playground/', 'no room exists until asked');
    await page.getByRole('button', { name: /Create room and copy message for the agent/ }).click();
    await page.getByRole('heading', { name: 'Your agent works through crabrix.com' }).waitFor();
    assert.equal(page.url(), origin + '/playground/', 'no room or agent link before the warning is accepted');
    await page.locator('dialog.pg-consent').getByRole('button', { name: 'Continue' }).click();
    await page.getByText('Copied. The agent link contains').waitFor();
    const text = await page.evaluate(() => navigator.clipboard.readText());
    assert.match(text, /^Split the sort\./);
    assert.match(text, /"schema": "crabrix-handoff-v1"/);
    assert.match(text, /\/mcp\/[A-Za-z0-9_-]{24}\//);
    assert.doesNotMatch(text, /\/playground\/room\//, 'the agent gets an agent link, not a person link');
    assert.match(text, /crabrix_connect/);
    assert.match(text, /\/ai\//);
    await page.getByRole('tab', { name: 'Codex' }).click();
    assert.match(await page.locator('.pg-code-copy code').first().innerText(), /^codex mcp add crabrix-room --url https?:\/\/[^ ]+\/mcp\/[A-Za-z0-9_-]{24}\//, 'the setup carries the real agent link');
    await context.close();
  });

  await scenario('AI-02 the docs route, redirect, descriptor and schemas are served', async () => {
    const { context, page } = await fresh();
    const docs = await page.goto(origin + '/ai/');
    assert.equal(docs.status(), 200);
    await page.getByRole('heading', { name: 'Install it once for your client' }).waitFor();
    await page.goto(origin + '/playground/mcp/');
    assert.equal(new URL(page.url()).pathname, '/ai/');
    const descriptor = await (await context.request.get(origin + '/ai/bootstrap.json')).json();
    assert.equal(descriptor.schema, 'crabrix-ai-bootstrap-v1');
    assert.equal(descriptor.execution.automatic, false);
    assert.equal((await context.request.get(origin + '/ai/schemas/crabrix-handoff-v1.json')).status(), 200);
    assert.equal((await context.request.get(origin + '/ai/schemas/crabrix-ai-bootstrap-v1.json')).status(), 200);
    const footer = await page.locator('.site-footer').getByRole('link', { name: 'Connect AI' }).count();
    assert.equal(footer, 1);
    await context.close();
  });

  await browser.close();
  const failed = results.filter(([state]) => state === 'FAIL').length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
