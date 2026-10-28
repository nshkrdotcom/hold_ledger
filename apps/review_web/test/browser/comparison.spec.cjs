const {test,expect}=require('@playwright/test');
const baseline=process.env.PART3_TEST_BASELINE_ID, proposal=process.env.PART3_TEST_PROPOSAL_ID;
test('actual isolated source replay distinguishes a tightened exact-fit premise',async({page})=>{
  test.skip(!/^[a-f0-9]{64}$/.test(baseline||'')||!/^[a-f0-9]{64}$/.test(proposal||''),'NOT RUN: real staged compatible IDs required');
  await page.goto('/claims/po_a2');await expect(page).toHaveURL(/\/claims\/po_a2\/trace-/);
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await page.locator('#source-comparison summary').click();
  await page.locator('#compare_baseline').fill(baseline);await page.locator('#compare_proposal').fill(proposal);await page.locator('#compare-form button').click();
  await expect(page.locator('#replay-pair')).toBeVisible();await page.locator('#replay-pair').click();
  await expect(page.locator('.attempt').filter({hasText:'succeeded'})).toHaveCount(2,{timeout:90000});
  await expect(page.locator('.pair-evidence')).toContainText('lost_domain_input');
  const source=await page.getByRole('link',{name:'Read proposal source ↗'}).first().getAttribute('href');
  const response=await page.request.get(source);expect(response.status()).toBe(200);expect(await response.text()).toContain('amount <');
  await page.locator('#pair-proof').click();await expect(page.locator('#pair-proof-artifacts')).toContainText('missing');
  const repair=await page.getByRole('link',{name:'Download local repair packet'}).first().getAttribute('href');
  const exported=await page.request.get(repair);expect(exported.status()).toBe(200);expect((await exported.json()).content_sha256).toMatch(/^[a-f0-9]{64}$/);
});
test('unknown source snapshots are refused',async({page})=>{
  await page.goto('/');await expect(page).toHaveURL(/\/claims\/po_exposure_retain\/trace-/);
  await page.locator('#source-comparison summary').click();await page.locator('#compare_baseline').fill('0'.repeat(64));await page.locator('#compare_proposal').fill('1'.repeat(64));
  await page.locator('#compare-form button').click();await expect(page.locator('[role=alert]')).toContainText('Compatible locally staged snapshots required');await expect(page.locator('#replay-pair')).toHaveCount(0);
});
