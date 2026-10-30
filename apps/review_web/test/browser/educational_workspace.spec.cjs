const {test, expect} = require('@playwright/test');

for (const width of [390, 800, 1440]) {
  test(`orientation is usable without overflow at ${width}px`, async ({page}) => {
    await page.setViewportSize({width, height: 900});
    await page.goto('/');
    await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
    await expect(page.locator('#edu-overview')).toContainText('Understand the system');
    await expect(page.locator('.edu-stat-strip')).toContainText('Registered groups');
    await expect(page.locator('#edu-overview')).not.toContainText('49 proven');
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
    await page.getByRole('link', {name: /Start with the story/}).click();
    await expect(page.locator('#edu-story')).toBeVisible();
    await page.getByRole('button', {name: /3 Timeout/}).click();
    await expect(page.locator('#edu-story')).toContainText('reply never arrives');
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  });
}

test('the atlas contains all 49 source-derived groups with a native Lean profile', async ({page}) => {
  await page.goto('/atlas');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('.edu-claim-row')).toHaveCount(49);
  await page.locator('[name=kind]').selectOption('native_lean');
  await expect(page.locator('.edu-claim-row')).toHaveCount(14);
  await page.getByRole('link', {name:/Replay committed work/}).first().click();
  await expect(page.locator('#edu-claim-profile')).toContainText('Registered');
  await expect(page.locator('.edu-profile-panel')).toContainText('Lean');
});

test('help is available by click and keyboard, with glossary on real screens', async ({page}) => {
  await page.goto('/lens/po_a2?mode=explore');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await page.locator('#edu-help-toggle').click();
  await expect(page.locator('#edu-help-drawer')).toBeVisible();
  await expect(page.locator('#edu-help-description')).toContainText('Claim Lens');
  await page.keyboard.press('Escape');
  await expect(page.locator('#edu-help-drawer')).toBeHidden();
  const term = page.locator('[data-edu-term=requires]').first();
  await term.focus();
  await expect(page.locator('#edu-tooltip')).toBeVisible();
  await expect(page.locator('#edu-tooltip')).toContainText('precondition');
  await page.keyboard.press('Escape');
  await expect(page.locator('#edu-tooltip')).toBeHidden();
  await page.locator('[data-edu-guidance]').selectOption('focused');
  await page.goto('/lab');
  await expect(page.locator('#edu-guidance')).toHaveValue('focused');
});
