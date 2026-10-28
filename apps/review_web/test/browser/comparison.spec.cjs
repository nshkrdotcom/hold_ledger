const {test, expect} = require('@playwright/test');
const baseline = process.env.PART3_TEST_BASELINE_ID;
const proposal = process.env.PART3_TEST_PROPOSAL_ID;
const ready = /^[0-9a-f]{64}$/.test(baseline || '') && /^[0-9a-f]{64}$/.test(proposal || '');

test('actual isolated replay exposes exact-fit lost coverage and readable source evidence', async ({page}) => {
  test.skip(!ready, 'NOT RUN: set real freshly staged baseline/proposal IDs for isolated worker QC');
  await page.goto('/');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await page.locator('#create-trace').click();
  await expect(page.locator('#explorer')).toBeVisible();
  await page.locator('#apply-event').click();
  await expect(page.locator('#actual-result')).toHaveText('admitted');
  await page.locator('#compare_baseline').fill(baseline);
  await page.locator('#compare_proposal').fill(proposal);
  await page.locator('#comparison-form button').click();
  await expect(page.locator('#source-changes')).toContainText('po_a2_test.exs');
  await page.locator('#replay').click();
  await expect(page.locator('#comparison-results .attempt')).toHaveCount(2);
  await expect(page.locator('#comparison-results .attempt').filter({hasText:'succeeded'})).toHaveCount(2, {timeout:90000});
  await expect(page.locator('.comparison-evidence')).toContainText(['lost_domain_input']);
  const source = page.getByRole('link', {name:'Read proposal source'}).first();
  const response = await page.request.get(await source.getAttribute('href'));
  expect(response.status()).toBe(200);
  expect(await response.text()).toContain('amount <');
  await page.locator('#inspect-proof').click();
  await expect(page.locator('#proof-detail')).toContainText('baseline');
  await expect(page.locator('#proof-detail')).toContainText('proposal');
  await expect(page.locator('#proof-detail')).toContainText('Statement missing');
  const repair = page.getByRole('link', {name:/Download repair packet/}).first();
  const exported = await page.request.get(await repair.getAttribute('href'));
  expect(exported.status()).toBe(200);
  const packet = await exported.json();
  expect(packet.content_sha256).toMatch(/^[0-9a-f]{64}$/);
});

test('invalid source pair is refused without fake replay or approval', async ({page}) => {
  await page.goto('/'); await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/); await page.locator('#create-trace').click();
  await expect(page.locator('#explorer')).toBeVisible();
  await page.locator('#compare_baseline').fill('0'.repeat(64));
  await page.locator('#compare_proposal').fill('1'.repeat(64));
  await page.locator('#comparison-form button').click();
  await expect(page.locator('[role=alert]')).toContainText('compatible');
  await expect(page.locator('#comparison-results')).toHaveCount(0);
});
