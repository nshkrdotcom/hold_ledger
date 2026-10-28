const {test, expect, devices} = require('@playwright/test');
const path = require('node:path');
const fs = require('node:fs');
const {execFileSync} = require('node:child_process');

async function connected(page) {
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
}
async function create(page, mode = 'ledger') {
  await page.goto('/');
  await connected(page);
  await page.locator('#start_mode').selectOption(mode);
  await page.locator('#create-trace').click();
  await expect(page).toHaveURL(/\/explore\/trace-/);
  await connected(page);
  return page.url();
}
async function event(page, type, key = '11', amount = '100') {
  const revision = await page.locator('#trace-revision').innerText();
  await page.locator('#event_type').selectOption(type);
  await page.locator('#event_key').fill(key);
  if (type === 'request') await page.locator('#event_amount').fill(amount);
  await page.locator('#apply-event').click();
  await expect(page.locator('#trace-revision')).not.toHaveText(revision);
  await expect(page.locator('#timeline button[aria-current="step"]')).toContainText(type === 'remote_void' ? 'Remote void' : type.replaceAll('_', ' '));
}

test('one clean entry, four panels, real timeout and reopen', async ({page}) => {
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  const url = await create(page);
  for (const id of ['guarantee-panel','source-panel','result-panel','evidence-panel','timeline']) {
    await expect(page.locator('#' + id)).toBeVisible();
  }
  await expect(page.locator('#review-primer, #glossary, #ai-consent')).toHaveCount(0);
  await event(page, 'request');
  await expect(page.locator('#actual-result')).toHaveText('admitted');
  await event(page, 'dispatch');
  await event(page, 'timeout');
  await expect(page.locator('#entries')).toContainText('unknown');
  await expect(page.locator('#amount-counter')).toHaveText('100¢ / 100¢');
  await event(page, 'request', '12');
  await expect(page.locator('#actual-result')).toHaveText('insufficient_amount');
  await page.reload(); await connected(page);
  await expect(page).toHaveURL(url);
  await expect(page.locator('#actual-result')).toHaveText('insufficient_amount');
  expect(errors).toEqual([]);
});

test('scrubber, previous/next and branches preserve the other path', async ({page}) => {
  await create(page);
  await event(page, 'request');
  await event(page, 'dispatch');
  await page.locator('#previous-step').click();
  await expect(page.locator('#actual-result')).toHaveText('admitted');
  await page.locator('#next-step').click();
  await expect(page.locator('#actual-result')).toHaveText('dispatched');
  await page.locator('#previous-step').click();
  await event(page, 'void');
  await expect(page.locator('#actual-result')).toHaveText('voided');
  await expect(page.locator('#timeline button')).toHaveCount(4);
  await page.locator('#position').focus();
  await page.keyboard.press('Home');
  await expect(page.locator('#entries')).toContainText('No entries');
  await page.keyboard.press('End');
  await expect(page.locator('#actual-result')).toBeVisible();
});

test('candidate JSON, inconsistent totals, explicit recalculation and invalid submit', async ({page}) => {
  await create(page); await event(page, 'request');
  await page.locator('#edit-candidate').click();
  const textarea = page.locator('#candidate_json');
  const value = JSON.parse(await textarea.inputValue());
  value.after.used_amount = 0;
  await textarea.fill(JSON.stringify(value));
  await page.locator('#candidate-form button').click();
  await expect(page.locator('#candidate-checks')).toContainText('false');
  await expect(page.locator('#branch-candidate')).toBeDisabled();
  expect(JSON.parse(await textarea.inputValue()).after.used_amount).toBe(0);
  await page.locator('#recalculate').click();
  await expect.poll(async () => JSON.parse(await textarea.inputValue()).after.used_amount).toBe(100);
  await textarea.fill('{broken');
  await page.locator('#candidate-form button').click();
  await expect(page.locator('[role=alert]')).toContainText('Candidate must');
  await expect(page.locator('#timeline button')).toHaveCount(2);
});

test('a hypothetical branch and its continuation stay labeled', async ({page}) => {
  await create(page); await event(page, 'request');
  await page.locator('#edit-candidate').click();
  const value = JSON.parse(await page.locator('#candidate_json').inputValue());
  value.after.entries = []; value.after.used_amount = 0; value.after.used_holds = 0;
  value.result = 'insufficient_amount';
  await page.locator('#candidate_json').fill(JSON.stringify(value));
  await page.locator('#candidate-form button').click();
  await page.locator('#branch-candidate').click();
  await expect(page.locator('#hypothetical-label')).toBeVisible();
  await event(page, 'request', '12');
  await expect(page.locator('#hypothetical-label')).toBeVisible();
});

test('structured starting entries create a new trace only after totals are consistent', async ({page}) => {
  const original = await create(page);
  await page.locator('#edit-start').click();
  await page.locator('#add-entry').click();
  await page.locator('input[name="state[entries][0][amount]"]').fill('50');
  await page.locator('select[name="state[entries][0][status]"]').selectOption('unknown');
  await page.locator('#save-starting').click();
  await expect(page.locator('[role=alert]')).toContainText('Starting counters');
  await page.locator('#recalculate-initial').click();
  await expect(page.locator('#state_used_amount')).toHaveValue('50');
  await page.locator('#save-starting').click();
  await expect(page).not.toHaveURL(original);
  await expect(page.locator('#amount-counter')).toHaveText('50¢ / 100¢');
});

test('remote delivery and local observation remain distinct through terminal fencing', async ({page}) => {
  await create(page, 'exposure');
  for (const type of ['request','dispatch','authorize','timeout']) await event(page, type);
  await expect(page.locator('#entries')).toContainText('unknown');
  await expect(page.locator('#remote-state')).toContainText('approved');
  await event(page, 'observe');
  await expect(page.locator('#entries')).toContainText('authorized');
  await event(page, 'void'); await event(page, 'remote_void');
  await expect(page.locator('#amount-counter')).toHaveText('100¢ / 100¢');
  await event(page, 'confirm'); await event(page, 'authorize');
  await expect(page.locator('#amount-counter')).toHaveText('0¢ / 100¢');
  await expect(page.locator('#remote-state')).toContainText('voided');
  await expect(page.locator('#evidence-panel')).toContainText('unestablished');
});

test('two tabs refuse a stale note and reconnect preserves the saved revision', async ({page, context}) => {
  const url = await create(page);
  const second = await context.newPage();
  await second.goto(url); await connected(second);
  await page.locator('#note_text').fill('Need evidence about the actual processor.');
  await page.locator('#note-form button').click();
  await expect(page.locator('#review-notes article')).toHaveCount(1);
  await second.locator('#note_text').fill('Stale answer');
  await second.locator('#note-form button').click();
  await expect(second.locator('[role=alert]')).toContainText('Another tab');
  await page.evaluate(() => window.liveSocket.disconnect());
  await page.evaluate(() => window.liveSocket.connect());
  await connected(page);
  await expect(page.locator('#review-notes article')).toHaveCount(1);
  await expect(page.locator('#review-notes article')).not.toContainText('Stale answer');
});

test('source bytes, missing proof evidence, favicon and no provider controls', async ({page, request}) => {
  await create(page);
  await page.getByRole('button', {name:/Read governing policy/}).click();
  await expect(page.locator('#source-detail pre')).toContainText('An exact amount fit is admitted');
  await page.locator('#inspect-proof').click();
  await expect(page.locator('#proof-detail')).toContainText('No report supplied');
  await expect(page.locator('#proof-detail')).toContainText('po_a2');
  const icon = await request.get('/images/lambda.svg');
  expect(icon.status()).toBe(200);
  expect(await icon.text()).toContain('<svg');
  await page.reload(); await connected(page);
  await expect(page.locator('input[type=checkbox], [phx-click=request_ai]')).toHaveCount(0);
});

test('mobile layout, keyboard focus and readable controls', async ({browser}) => {
  const context = await browser.newContext({...devices['iPhone 13']});
  const page = await context.newPage();
  try {
    await create(page); await event(page, 'request');
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
    await page.locator('#previous-step').focus(); await page.keyboard.press('Enter');
    await expect(page.locator('#entries')).toContainText('No entries');
  } finally { await context.close(); }
});

test('local command and browser use the same executor and source identity', async ({page, request}) => {
  await create(page); await event(page, 'request');
  const root = path.resolve(__dirname, '../../../..');
  const input = path.join(root, 'tmp/explorer_completion/command-request.json');
  fs.mkdirSync(path.dirname(input), {recursive:true});
  fs.writeFileSync(input, JSON.stringify({operation:'step', mode:'ledger', before:{amount_limit:100,hold_limit:2,used_amount:0,used_holds:0,entries:[]}, event:{type:'request',key:11,amount:100}}));
  const stdout = execFileSync('uv', ['run','--locked','python','scripts/local_run.py','--cwd','apps/review_web','mix','run','--no-start','scripts/explore.exs','--', input], {cwd:root, encoding:'utf8', timeout:30000});
  const output = JSON.parse(stdout.trim().split('\n').at(-1));
  const exported = await request.get(new URL(page.url()).pathname + '/export');
  const body = await exported.json();
  const step = body.trace.steps[0];
  const receipt = {...step}; delete receipt.id; delete receipt.parent; delete receipt.origin;
  expect(output.receipt).toEqual(receipt);
  expect(output.identity).toEqual(body.trace.identity);
  fs.writeFileSync(path.join(root,'tmp/explorer_completion/command-parity.json'), JSON.stringify(output,null,2));
});
