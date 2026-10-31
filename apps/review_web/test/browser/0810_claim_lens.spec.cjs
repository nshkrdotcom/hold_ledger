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
    await page.goto('/lens/po_a2?mode=explore');
    await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
    await expect(page.locator('#lens-gap')).toContainText('Potential loss of required coverage');
    await expect(page.locator('#lens-baseline-verdict')).toContainText('Claim rejects this output');
    await expect(page.locator('#lens-hypothetical-verdict')).toContainText("Claim says nothing about this input");
    await page.locator('#lens-witness-below').click();
    await expect(page.locator('#lens-hypothetical-verdict')).toContainText('Claim rejects this output');
    await page.locator('#lens-witness-above').click();
    await expect(page.locator('#lens-policy-verdict')).toContainText('Policy permits');
    await expect(page.locator('#lens-baseline-verdict')).toContainText("Claim says nothing about this input");
    await expect(page.locator('#lens-hypothetical-verdict')).toContainText("Claim says nothing about this input");
    await page.locator('#lens-witness-exact').click();
    await page.locator('#lens-variation-proof_only').click();
    await expect(page.locator('#lens-gap')).toContainText('No claim-level change');
    await expect(page.locator('#lens-evidence-status dt').filter({hasText: 'Proof check for proposed change'}).locator('+ dd')).toHaveText('Not run');
    await expect(page.locator('#lens-evidence-status')).toContainText('Not collected / unavailable');
    await expect(page.getByRole('main')).toHaveCount(1);
    await expect(page.locator('.lens-layout')).toHaveCSS('grid-template-columns',
      width === 1280 ? /\S+ \S+/ : /^\S+$/);
    const passage = page.locator('#lens-proof-steps pre').first();
    await passage.focus();
    await expect(passage).toBeFocused();
    expect(await passage.evaluate(el => el.scrollHeight <= el.clientHeight)).toBe(true);
    await page.locator('#lens-pointwise-details summary').click();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  });
}

test('retention lens distinguishes terminal evidence and source-linked statements', async ({page}) => {
  await page.goto('/lens/po_exposure_retain?mode=explore');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#lens-policy-verdict')).toContainText('Policy permits this output');
  await expect(page.locator('#lens-hypothetical-verdict')).toContainText('Claim rejects this output');
  await expect(page.locator('#lens-proof-steps')).toBeVisible();
  await expect(page.locator('#lens-baseline-verdict')).toContainText("Claim says nothing about this input");
  await page.locator('#lens-witness-timeout').click();
  await expect(page.locator('#lens-policy-verdict')).toContainText('Policy forbids');
  await expect(page.locator('#lens-baseline-verdict')).toContainText('Claim rejects this output');
  await expect(page.locator('#lens-hypothetical-verdict')).toContainText('Claim rejects this output');
  await expect(page.locator('.lens-witness-data')).toContainText('100¢ reserved');
  await page.locator('#lens-witness-void').click();
  await expect(page.locator('#lens-baseline-verdict')).toContainText('Claim rejects this output');
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
  await page.goto('/lens/po_a2?mode=explore');
  await page.locator('#lens-modes a').filter({hasText: 'Compare source versions'}).click();
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#source-comparison')).toBeVisible();
  await expect(page.locator('#compare-form')).toBeVisible();
});

test('keyboard decisions and drafts reset across study navigation and reload', async ({page}) => {
  await page.goto('/lens/po_a2?mode=explore');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  const decision = page.getByRole('button', {name: /Leaves out a required input/});
  await decision.focus();
  await expect(decision).toBeFocused();
  await expect(decision).toHaveCSS('outline-style', 'solid');
  await decision.press('Enter');
  await expect(decision).toHaveAttribute('aria-pressed', 'true');
  await page.locator('#lens-review-notes > summary').click();
  const note = page.locator('#lens-review-form textarea');
  await note.fill('Check the exact-fit boundary');
  await page.locator('#lens-study-picker a[href="/lens/po_exposure_retain?mode=explore"]').click();
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(note).toHaveValue('');
  await expect(page.locator('.lens-decisions [aria-pressed=true]')).toHaveCount(0);
  await page.locator('#lens-review-notes > summary').click();
  await note.fill('Temporary retention note');
  await page.reload();
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(note).toHaveValue('');

  await page.goto('/claims/l2_identity');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#claim-navigation a[href^="/lens/"]')).toHaveCount(0);
  await expect(page.locator('#decision-docket')).toContainText('Mark reviewed');
  await page.locator('#reference-nav > summary').click();
  await page.locator('#reference-nav').getByRole('link', {name: 'Practice a review'}).click();
  await expect(page).toHaveURL(/\/lens\/po_a2\?mode=explore$/);
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#lens-policy-verdict')).toBeVisible();
  await page.locator('#lens-exercise-modes a').filter({hasText: 'Review first'}).click();
  await expect(page).toHaveURL(/\/lens\/po_a2$/);
  await expect(page.locator('#lens-demo-scope')).toContainText('Two reviews to practice');
  await page.locator('#lens-demo-scope a[href="/lens/po_exposure_retain"]').click();
  await expect(page).toHaveURL(/\/lens\/po_exposure_retain$/);
  await expect(page.locator('#lens-feedback-withheld')).toBeVisible();
});

test('Review first permits empty notes and exposes an explicit worked-explanation path', async ({page}) => {
  await page.goto('/lens/po_a2');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#lens-review-notes')).toHaveJSProperty('open', false);
  await expect(page.locator('#lens-confirm')).toBeDisabled();
  await page.locator('#lens-decision-concern').click();
  await page.locator('#lens-confirm').click();
  await expect(page.locator('#lens-initial-answer')).toContainText('possible guarantee loss');
  await expect(page.locator('#lens-policy-verdict')).toBeVisible();
  await page.locator('#lens-try-again').click();
  await expect(page.locator('#lens-policy-verdict')).toHaveCount(0);
  await page.locator('#lens-see-explanation').click();
  await expect(page).toHaveURL(/mode=explore$/);
  await expect(page.locator('#lens-policy-verdict')).toBeVisible();
  await expect(page.locator('#lens-initial-answer')).toHaveCount(0);
});

async function expectReadable(locator) {
  const ratio = await locator.evaluate(node => {
    const rgb = value => value.match(/[\d.]+/g).map(Number);
    const luminance = channels => channels.slice(0, 3).map(channel => {
      const value = channel / 255;
      return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
    }).reduce((sum, value, index) => sum + value * [0.2126, 0.7152, 0.0722][index], 0);
    const foreground = luminance(rgb(getComputedStyle(node).color));
    let background = [255, 255, 255];
    for (let parent = node; parent; parent = parent.parentElement) {
      const color = rgb(getComputedStyle(parent).backgroundColor);
      if (color.length === 3 || color[3] === 1) { background = color; break; }
    }
    const behind = luminance(background);
    return (Math.max(foreground, behind) + 0.05) / (Math.min(foreground, behind) + 0.05);
  });
  expect(ratio).toBeGreaterThanOrEqual(4.5);
}

for (const width of [1440, 390]) {
  test(`Lens controls and disclosed evidence stay readable at ${width}px`, async ({page}) => {
    await page.setViewportSize({width, height: 900});
    await page.goto('/lens/po_a2');
    await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
    const compare = page.locator('#lens-modes a');
    await expectReadable(compare);
    await compare.hover();
    await expectReadable(compare);
    await expectReadable(page.locator('#lens-exercise-modes a:not([aria-current]) small'));
    await expectReadable(page.locator('#lens-challenge-scope'));
    const disclosure = page.locator('#lens-evidence-legend summary');
    await disclosure.focus();
    await disclosure.press('Enter');
    await expect(page.locator('.lens-legend-list')).toBeVisible();
    await expectReadable(page.locator('.lens-legend-list'));
    await expectReadable(page.locator('.lens-legend-list strong').first());
    await expectReadable(page.locator('#lens-evidence-legend p'));
  });
}
