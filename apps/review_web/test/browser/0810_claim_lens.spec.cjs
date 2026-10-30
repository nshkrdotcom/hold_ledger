const {test, expect} = require('@playwright/test');

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
    await page.locator('#lens-witness-exact').click();
    await page.locator('#lens-variation-proof_only').click();
    await expect(page.locator('#lens-gap')).toContainText('No claim-level change');
    await expect(page.locator('#lens-evidence-status')).toContainText('Not run / unavailable');
    await expect(page.locator('#lens-evidence-status')).toContainText('Not collected / unavailable');
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  });
}

test('retention lens distinguishes terminal evidence and source-linked statements', async ({page}) => {
  await page.goto('/lens/po_exposure_retain');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#lens-policy-verdict')).toContainText('Policy permits this output');
  await expect(page.locator('#lens-hypothetical-verdict')).toContainText('Rejects this output');
  await expect(page.locator('#lens-proof-steps')).toBeVisible();
  await page.locator('#lens-witness-void').click();
  await expect(page.locator('#lens-baseline-verdict')).toContainText('Rejects this output');
  await page.locator('#lens-clause-retain-protected').click();
  await expect(page.locator('#lens-selected-clause')).toBeVisible();
  await page.locator('#lens-decision-concern').click();
  await expect(page.locator('#lens-draft-state')).toContainText('possible guarantee loss');
  const url = await page.locator('#lens-source-contract a').first().getAttribute('href');
  expect(url).toMatch(/^\/claims\/po_exposure_retain\/source\//);
});

test('compare mode deeplink opens trusted version picker without staging anything', async ({page}) => {
  await page.goto('/lens/po_a2');
  await page.locator('#lens-modes a').filter({hasText: 'Compare versions'}).click();
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#source-comparison')).toBeVisible();
  await expect(page.locator('#compare-form')).toBeVisible();
});
