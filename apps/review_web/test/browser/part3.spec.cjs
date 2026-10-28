const { test, expect, devices } = require('@playwright/test');

const ids = {
  baseline: process.env.PART3_TEST_BASELINE_ID,
  proposal: process.env.PART3_TEST_PROPOSAL_ID,
};
const hasSnapshots = /^[0-9a-f]{64}$/.test(ids.baseline || '') &&
  /^[0-9a-f]{64}$/.test(ids.proposal || '') && ids.baseline !== ids.proposal;

async function connected(page) {
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
}

async function create(page) {
  await page.goto('/changes');
  await connected(page);
  await page.locator('#baseline-id').selectOption(ids.baseline);
  await page.locator('#proposal-id').selectOption(ids.proposal);
  await page.locator('#create-change-package button[type=submit]').click();
  await expect(page).toHaveURL(/\/changes\/[A-Za-z0-9_-]{16,80}$/);
  await expect(page.locator('#part3-comparison')).toBeVisible();
  return page.url();
}

test('change review is discoverable; no snapshot means no fake runnable package', async ({page}) => {
  await page.goto('/changes');
  await connected(page);
  await expect(page.locator('h1')).toContainText('Review a proposed change');
  await expect(page.locator('#create-change-package')).toBeVisible();
  await expect(page.locator('#create-change-package')).toContainText('Baseline content identity');
  await expect(page.locator('#create-change-package')).toContainText('Proposal content identity');
  await expect(page.locator('a[href="/workbench"]')).toBeVisible();
});

test('creation, review reopening, explicit pin and source evidence', async ({page}) => {
  test.skip(!hasSnapshots, 'Provide two operator-staged local snapshot IDs for real Part 3 browser QC');
  const url = await create(page);
  await expect(page.locator('#part3-source-delta li').first()).toBeVisible();
  await expect(page.locator('#part3-pin')).toBeEnabled();
  await expect(page.locator('#part3-replay-attempts li')).toHaveCount(0);
  await page.locator('#part3-pin').click();
  await expect(page.locator('#part3-pins summary')).toContainText('1');
  await expect(page.locator('#part3-replay-attempts li')).toHaveCount(0);
  await page.reload();
  await connected(page);
  await expect(page).toHaveURL(url);
  await expect(page.locator('#part3-pins summary')).toContainText('1');
  await expect(page.locator('#part3-ai-consent')).not.toBeChecked();
});

test('structured inconsistent candidate is not silently repaired or pinned', async ({page}) => {
  test.skip(!hasSnapshots, 'Requires staged local snapshot fixture');
  await create(page);
  await page.locator('#part3-structured-editor > summary').click();
  await page.locator('button[phx-value-action="add_entry"][phx-value-section="candidate"]').click();
  await expect(page.locator('#candidate-0-status')).toHaveValue('reserved');
  await expect(page.locator('#candidate-used_amount')).toHaveValue('0');
  await expect(page.locator('#part3-pins summary')).toContainText('0');
  await page.locator('button[phx-value-action="recalculate"][phx-value-section="candidate"]').click();
  await expect(page.locator('#candidate-used_amount')).toHaveValue('1');
  await expect(page.locator('#part3-pins summary')).toContainText('0');
});

test('learning reveal is explicit, expert is evidence first, AI consent is off after reload', async ({page}) => {
  test.skip(!hasSnapshots, 'Requires staged local snapshot fixture');
  await create(page);
  await page.locator('button[phx-value-mode="learning"]').click();
  await expect(page.locator('#part3-reveal')).toBeVisible();
  await page.locator('#part3-reveal').click();
  await expect(page.locator('#part3-missing-replay')).toBeVisible();
  await page.locator('button[phx-value-mode="expert"]').click();
  await expect(page.locator('#part3-missing-replay')).toBeVisible();
  await page.locator('#part3-ai summary').click();
  await expect(page.locator('#part3-ai-consent')).not.toBeChecked();
  await page.reload();
  await connected(page);
  await page.locator('#part3-ai summary').click();
  await expect(page.locator('#part3-ai-consent')).not.toBeChecked();
  await expect(page.locator('#part3-ai-jobs li')).toHaveCount(0);
});

test('human finding survives reload and stale two-tab answer is not silently rebased', async ({page, context}) => {
  test.skip(!hasSnapshots, 'Requires staged local snapshot fixture');
  const url = await create(page);
  const second = await context.newPage();
  await second.goto(url);
  await connected(second);
  await page.locator('#part3-finding-scope').fill('One source-bound question');
  await page.locator('#part3-finding-rationale').fill('The source edit is not a general semantic claim.');
  await page.locator('#part3-finding button[type="submit"]').click();
  await expect(page.locator('#part3-decision')).toContainText('revision 1');
  await expect(second.locator('button[phx-click="refresh_human_revision"]')).toBeVisible();
  await second.locator('#part3-finding-scope').fill('Stale scope');
  await second.locator('#part3-finding-rationale').fill('This stale browser submission must not overwrite a finding.');
  await second.locator('#part3-finding button[type="submit"]').click();
  await expect(second.locator('[role="alert"]')).toContainText('Another tab');
  await page.reload();
  await connected(page);
  await expect(page.locator('#part3-decision')).toContainText('The source edit is not a general semantic claim.');
});

test('mobile navigation, keyboard access and no default external send', async ({browser}) => {
  test.skip(!hasSnapshots, 'Requires staged local snapshot fixture');
  const context = await browser.newContext({...devices['iPhone 13']});
  const page = await context.newPage();
  try {
    await create(page);
    await page.locator('#part3-structured-editor > summary').focus();
    await page.keyboard.press('Enter');
    await expect(page.locator('#before-used_amount')).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true);
    await page.locator('#part3-ai summary').click();
    await expect(page.locator('#part3-ai-consent')).not.toBeChecked();
    await expect(page.locator('#part3-ai-jobs li')).toHaveCount(0);
  } finally { await context.close(); }
});

test('editable fields and JSON round trip keep save, replay, answer and conclusion separate', async ({page}) => {
  test.skip(!hasSnapshots, 'Requires staged local snapshots');
  await create(page);
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.locator('#part3-structured-editor > summary').click();
  await page.locator('#candidate-used_amount').fill('7');
  await page.locator('#candidate-used_amount').press('Tab');
  await expect(page.locator('#part3-comparison')).toContainText('Used amount 7');
  await expect(page.locator('#part3-pins summary')).toContainText('0');
  await page.locator('#part3-advanced-json > summary').click();
  let draft = JSON.parse(await page.locator('#part3-export-json').innerText());
  expect(draft.output.after.used_amount).toBe(7);
  draft.output.after.used_holds = 2;
  await page.locator('#part3-raw').fill(JSON.stringify(draft));
  await page.locator('#part3-import button').click();
  await expect(page.locator('#candidate-used_holds')).toHaveValue('2');
  await page.locator('#part3-raw').fill('{broken');
  await page.locator('#part3-import button').click();
  await expect(page.locator('#part3-structured-editor [role=alert]')).toContainText('Import refused');
  await expect(page.locator('#candidate-used_holds')).toHaveValue('2');
  await expect(page.locator('#part3-replay-attempts li')).toHaveCount(0);
  await page.locator('#part3-pin').click();
  await expect(page.locator('#part3-pins summary')).toContainText('1');
  await expect(page.locator('#part3-replay-attempts li')).toHaveCount(0);
  expect(errors).toEqual([]);
});

test('actual isolated replay and source-bound proof inspector expose results with limits', async ({page}) => {
  test.skip(!hasSnapshots, 'Requires provisioned local snapshots');
  test.setTimeout(150000);
  await create(page);
  await page.locator('#run-isolated-replay').click();
  await expect(page.locator('#part3-replay-result')).toBeVisible({timeout: 130000});
  await expect(page.locator('#part3-replay-attempts li')).toHaveCount(2);
  await expect(page.locator('#part3-replay-result')).toContainText('admitted');
  await expect(page.locator('#part3-evidence-list')).toContainText('lost domain input');
  await page.locator('#run-isolated-replay').click();
  await expect(page.locator('#part3-replay-attempts li')).toHaveCount(2);
  await page.locator('#part3-proof > summary').click();
  await page.locator('#part3-inspect-proof').click();
  await expect(page.locator('#part3-proof-inspection')).toContainText('49');
  await expect(page.locator('#part3-proof-inspection')).toContainText('not_run');
  await expect(page.locator('#part3-ai-jobs li')).toHaveCount(0);
  await expect(page.locator('#part3-accepted-questions li')).toHaveCount(0);
});

test('learning reveal history survives reconnect while consent resets and stale drafts remain', async ({page}) => {
  test.skip(!hasSnapshots, 'Requires staged local snapshots');
  await create(page);
  await page.locator('button[phx-value-mode="learning"]').click();
  await expect(page.locator('button[phx-value-mode="learning"]')).toHaveAttribute('aria-pressed', 'true');
  await page.locator('#part3-finding-scope').fill('Before revealing computed evidence');
  await page.locator('#part3-finding-rationale').fill('A recorded prediction context, with no proof acceptance claimed.');
  await page.locator('#part3-finding button[type=submit]').click();
  await expect(page.locator('#part3-decision')).toContainText('revealed before answer: false');
  await page.locator('#part3-ai > summary').click();
  await page.locator('#part3-ai-consent').check(); // No submit, no source send.
  await page.evaluate(() => window.liveSocket.disconnect());
  await expect(page.locator('[data-phx-main]')).not.toHaveClass(/phx-connected/);
  await page.evaluate(() => window.liveSocket.connect());
  await connected(page);
  await expect(page.locator('#part3-ai-consent')).not.toBeChecked();
  await expect(page.locator('#part3-ai-jobs li')).toHaveCount(0);
  await expect(page.locator('#part3-decision')).toContainText('A recorded prediction context');
});

test('source file and independent proof panels are read-only and source-addressed', async ({page, request}) => {
  test.skip(!hasSnapshots, 'Requires newly staged compatible source identities');
  const url = await create(page);
  const change = page.locator('#part3-source-delta li').first();
  await change.locator('summary').click();
  await expect(change).toContainText('structural source edit');
  const fullFile = change.locator('a[href*="/source/proposal/"]').first();
  await expect(fullFile).toBeVisible();
  const response = await request.get(new URL(await fullFile.getAttribute('href'), url).toString());
  expect(response.status()).toBe(200);
  expect(response.headers()['content-type']).toContain('text/plain');
  await page.locator('#part3-proof > summary').click();
  await page.locator('#part3-inspect-proof').click();
  await expect(page.locator('#part3-proof-inspection')).toContainText('49');
  await expect(page.locator('.part3-proof-version')).toHaveCount(2);
  await expect(page.locator('.part3-proof-version').first()).toContainText('not_run');
  await expect(page.locator('#part3-ai-jobs li')).toHaveCount(0);
});

test('evidence docket action is attributed, export is local and conclusion is separate', async ({page, request}) => {
  test.skip(!hasSnapshots, 'Requires controlled two-snapshot replay and fresh local setup');
  test.setTimeout(190000);
  const url = await create(page);
  await page.locator('#run-isolated-replay').click();
  await expect(page.locator('#part3-evidence-list article').first()).toBeVisible({timeout: 150000});
  const card = page.locator('#part3-evidence-list article').first();
  await expect(card).toContainText('actual Ledger output');
  const jsonLink = card.locator('a[href$=".json"]');
  const packetRes = await request.get(new URL(await jsonLink.getAttribute('href'), url).toString());
  expect(packetRes.status()).toBe(200);
  const packet = await packetRes.json();
  expect(packet.schema_version).toBe(1);
  expect(packet.content.human.policy_change_authorized).toBe(false);
  expect(packet.content.distinction.kind).toMatch(/lost_domain_input|permitted_alternative_output|observed_behavioral_difference/);
  expect(packet.content.package.human_revision).toBe(0);
  await card.locator('button[phx-value-choice="policy"]').click();
  await expect(page.locator('#part3-decision')).toContainText('needs policy/evidence decision');
  await expect(card).toContainText('Latest human disposition: unresolved');
  await expect(card.getByText('Immutable human finding history', {exact: false})).toBeVisible();
  await expect(page.locator('#part3-finish')).toBeEnabled();
  await expect(page.locator('#part3-ai-jobs li')).toHaveCount(0);
  const packet2 = await request.get(new URL(await jsonLink.getAttribute('href'), url).toString());
  expect(packet2.status()).toBe(200);
  const revised = await packet2.json();
  expect(revised.content.package.human_revision).toBe(1);
  expect(revised.content.human.findings).toHaveLength(1);
  expect(revised.content.human.conclusion).toBeNull();
});
