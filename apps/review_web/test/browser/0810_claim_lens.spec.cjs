const {test, expect} = require('@playwright/test');

test.beforeEach(async ({page}) => {
  page.qaErrors = [];
  page.on('pageerror', error => page.qaErrors.push(error.message));
  page.on('console', message => {
    if (message.type() === 'error') page.qaErrors.push(message.text());
  });
});
test.afterEach(async ({page}) => {
  expect(page.qaErrors).toEqual([]);
});

for (const width of [1280, 390]) {
  test(`Claim Lens reveals input-domain loss and proof provenance at ${width}px`, async ({page}) => {
    await page.setViewportSize({width, height: 900});
    await page.goto('/lens/po_a2');
    await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
    await expect(page.locator('#lens-gap')).toContainText('Potential loss of required coverage');
    await expect(page.locator('#lens-baseline-verdict')).toContainText('Rejects this output');
    await expect(page.locator('#lens-hypothetical-verdict')).toContainText('Outside the claim');
    await page.locator('#lens-witness-below').click();
    await expect(page.locator('#lens-hypothetical-verdict')).toContainText('Rejects this output');
    await page.locator('#lens-witness-above').click();
    await expect(page.locator('#lens-policy-verdict')).toContainText('Policy permits');
    await expect(page.locator('#lens-baseline-verdict')).toContainText('Outside the claim');
    await expect(page.locator('#lens-hypothetical-verdict')).toContainText('Outside the claim');
    await page.locator('#lens-witness-exact').click();
    await page.locator('#lens-variation-proof_only').click();
    await expect(page.locator('#lens-gap')).toContainText('No claim-level change');
    await expect(page.locator('#lens-evidence-status')).toContainText('Not run / unavailable');
    await expect(page.locator('#lens-evidence-status')).toContainText('Not collected / unavailable');
    await expect(page.getByRole('main')).toHaveCount(1);
    await expect(page.locator('.lens-layout')).toHaveCSS('grid-template-columns',
      width === 1280 ? /\S+ \S+ \S+/ : /^\S+$/);
    const passage = page.locator('#lens-proof-steps pre').first();
    await passage.focus();
    await expect(passage).toBeFocused();
    await passage.press('ArrowDown');
    await expect.poll(() => passage.evaluate(el => el.scrollTop)).toBeGreaterThan(0);
    await page.locator('#lens-pointwise-details summary').click();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  });
}

test('retention lens distinguishes terminal evidence and source-linked statements', async ({page}) => {
  await page.goto('/lens/po_exposure_retain');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#lens-policy-verdict')).toContainText('Policy permits this output');
  await expect(page.locator('#lens-hypothetical-verdict')).toContainText('Rejects this output');
  await expect(page.locator('#lens-proof-steps')).toBeVisible();
  await expect(page.locator('#lens-baseline-verdict')).toContainText('Outside the claim');
  await page.locator('#lens-witness-timeout').click();
  await expect(page.locator('#lens-policy-verdict')).toContainText('Policy forbids');
  await expect(page.locator('#lens-baseline-verdict')).toContainText('Rejects this output');
  await expect(page.locator('#lens-hypothetical-verdict')).toContainText('Rejects this output');
  await expect(page.locator('.lens-witness-data')).toContainText('100¢ reserved');
  await page.locator('#lens-witness-void').click();
  await expect(page.locator('#lens-baseline-verdict')).toContainText('Rejects this output');
  await page.locator('#lens-clause-retain-protected').click();
  await expect(page.locator('#lens-selected-clause')).toBeVisible();
  await page.locator('#lens-decision-concern').click();
  await expect(page.locator('#lens-draft-state')).toContainText('possible guarantee loss');
  const url = await page.locator('#lens-source-contract a').first().getAttribute('href');
  expect(url).toMatch(/^\/claims\/po_exposure_retain\/source\//);
  const response = await page.request.get(url);
  expect(response.status()).toBe(200);
  expect(await response.text()).toContain('not Spec.release_evidence?');
  const stale = await page.request.get(url.replace(/[a-f0-9]{64}$/, '0'.repeat(64)));
  expect(stale.status()).toBe(404);
  const policy = await page.locator('#lens-policy a').getAttribute('href');
  const policyResponse = await page.request.get(policy);
  expect(policyResponse.status()).toBe(200);
  expect(await policyResponse.text()).toContain('An issued or potentially issued authorization');
  const lean = await page.locator('.lens-lean-decl a').first().getAttribute('href');
  const leanResponse = await page.request.get(lean);
  expect(leanResponse.status()).toBe(200);
  expect(await leanResponse.text()).toContain('po_exposure_retain/5');
});

test('compare mode deeplink opens trusted version picker without staging anything', async ({page}) => {
  await page.goto('/lens/po_a2');
  await page.locator('#lens-modes a').filter({hasText: 'Compare versions'}).click();
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#source-comparison')).toBeVisible();
  await expect(page.locator('#compare-form')).toBeVisible();
});

test('keyboard decisions and drafts reset across study navigation and reload', async ({page}) => {
  await page.goto('/lens/po_a2');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  const decision = page.getByRole('button', {name: 'Possible guarantee loss', exact: true});
  await decision.focus();
  await expect(decision).toBeFocused();
  await expect(decision).toHaveCSS('outline-style', 'solid');
  await decision.press('Enter');
  await expect(decision).toHaveAttribute('aria-pressed', 'true');
  const note = page.getByRole('textbox', {name: 'Your explanation'});
  await note.fill('Check the exact-fit boundary');
  await page.locator('#lens-study-picker a[href="/lens/po_exposure_retain"]').click();
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(note).toHaveValue('');
  await expect(page.locator('#lens-decision-unresolved')).toHaveAttribute('aria-pressed', 'true');
  await note.fill('Temporary retention note');
  await page.reload();
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(note).toHaveValue('');

  await page.goto('/claims/l2_identity');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#case-review-modes a[href^="/lens/"]')).toHaveCount(0);
  await expect(page.locator('.lens-mode-unavailable')).toContainText('two studies');
});
