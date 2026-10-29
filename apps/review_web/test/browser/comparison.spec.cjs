const {test,expect}=require('@playwright/test');
const baseline=process.env.PART3_TEST_BASELINE_ID, proposal=process.env.PART3_TEST_PROPOSAL_ID;
test('actual isolated source replay distinguishes a tightened exact-fit premise',async({page})=>{
  test.skip(!/^[a-f0-9]{64}$/.test(baseline||'')||!/^[a-f0-9]{64}$/.test(proposal||''),'NOT RUN: real staged compatible IDs required');
  await page.goto('/claims/po_a2');await expect(page).toHaveURL(/\/claims\/po_a2\/trace-/);
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await page.locator('#choose-sources').click();
  await page.locator('#compare_baseline').selectOption(baseline);await page.locator('#compare_proposal').selectOption(proposal);await page.locator('#compare-form button').click();
  const traceCount=await page.locator('#timeline button').count();
  await page.locator('#review-amount').fill('101');await expect(page.locator('#scratch-status')).toBeVisible();
  await page.locator('#replay-pair').click();await expect(page.locator('.attempt').filter({hasText:'succeeded'})).toHaveCount(2,{timeout:90000});
  await expect(page.locator('#pair-execution')).toContainText('insufficient_amount');
  await page.locator('#review-amount').fill('100');await expect(page.locator('#pair-execution')).not.toContainText('insufficient_amount');
  await expect(page.locator('#replay-pair')).toBeVisible();await page.locator('#replay-pair').click();
  await expect(page.locator('.attempt').filter({hasText:'succeeded'})).toHaveCount(4,{timeout:90000});
  await expect(page.locator('#timeline button')).toHaveCount(traceCount);
  await page.locator('#inspector-tools [phx-value-view=record]').click();
  await expect(page.locator('.pair-evidence')).toContainText('lost_domain_input');
  await page.locator('#source-change-details summary').click();
  const source=await page.getByRole('link',{name:'Read proposal source ↗'}).first().getAttribute('href');
  const response=await page.request.get(source);expect(response.status()).toBe(200);expect(await response.text()).toContain('amount <');
  await page.locator('#inspector-tools [phx-value-view=artifacts]').click();await page.locator('#pair-proof').click();await expect(page.locator('#pair-proof-artifacts')).toContainText('missing');
  await page.locator('#inspector-tools [phx-value-view=artifacts]').click();
  await expect(page.locator('#pair-execution')).toContainText('admitted');
  await page.locator('#inspector-tools [phx-value-view=record]').click();
  // Disposition actions are directly visible beside the active result.
  await page.locator('#decision-docket button[phx-value-action=design]').click();
  await page.locator('#inspector-tools [phx-value-view=record]').click();
  const repair=await page.getByRole('link',{name:'Download local repair packet'}).first().getAttribute('href');
  const exported=await page.request.get(repair);expect(exported.status()).toBe(200);expect((await exported.json()).content_sha256).toMatch(/^[a-f0-9]{64}$/);
  await expect(page.locator('#repair-ready')).toBeVisible();
  await page.locator('#review-amount').fill('99');
  await expect(page.locator('#repair-ready')).toHaveCount(0);
  await expect(page.locator('#repair-unavailable')).toContainText('exact input and alternative');
  await page.locator('#review-amount').fill('100');
  await expect(page.locator('#repair-ready')).toBeVisible();
  await page.locator('#edit-candidate').click();
  await page.locator('#alternative-counter input').fill('1');
  await expect(page.locator('#repair-ready')).toHaveCount(0);
  await expect(page.locator('#repair-unavailable')).toContainText('exact input and alternative');

});
test('source selection uses registered identities and replay is unavailable without a pair',async({page})=>{
  await page.goto('/');await expect(page).toHaveURL(/\/claims\/po_a2\/trace-/);
  await page.locator('#choose-sources').click();
  await expect(page.locator('#compare_baseline')).toHaveJSProperty('tagName','SELECT');
  await expect(page.locator('#replay-pair')).toHaveCount(0);
  await expect(page.locator('#choose-replay-sources')).toBeEnabled();
});
