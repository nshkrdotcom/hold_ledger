const {test, expect} = require('@playwright/test');

for (const width of [390, 800, 1024, 1440]) {
  test(`orientation is usable without overflow at ${width}px`, async ({page}) => {
    await page.setViewportSize({width, height: 900});
    await page.goto('/');
    await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
    await expect(page.locator('#edu-overview h1')).toContainText('Understand payment holds');
    await expect(page.locator('.edu-journey')).toHaveCount(3);
    await expect(page.locator('.edu-stat-strip')).toContainText('Registered claims');
    await expect(page.locator('#edu-overview')).not.toContainText('49 proven');
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
    await page.getByRole('link', {name: /Follow a payment hold/}).first().click();
    await expect(page.locator('#edu-story')).toBeVisible();
    await page.getByRole('button', {name: /3 Timeout/}).click();
    await expect(page.locator('#edu-story')).toContainText('reply never arrives');
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  });
}

test('the atlas keeps eight families and all 49 claims with source access', async ({page}) => {
  await page.goto('/atlas');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#edu-families > a')).toHaveCount(8);
  await expect(page.locator('.edu-claim-row')).toHaveCount(49);
  await page.locator('[name=kind]').selectOption('native_lean');
  await expect(page.locator('.edu-claim-row')).toHaveCount(14);
  await page.locator('[data-claim-slug=po_composite_recovery]').click();
  await expect(page.locator('#edu-claim-profile')).toContainText('Registered');
  await expect(page.locator('#edu-claim-profile')).toContainText('Lean-only');
  await page.locator('#edu-claim-source > summary').click();
  await expect(page.locator('#edu-claim-source a[href="/claims/po_composite_recovery"]')).toBeVisible();
});

test('help is available by click and keyboard, with glossary on real screens', async ({page}) => {
  await page.goto('/lens/po_a2?mode=explore');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await page.locator('#edu-help-toggle').click();
  await expect(page.locator('#edu-help-drawer')).toBeVisible();
  await expect(page.locator('#edu-help-title')).not.toBeEmpty();
  await page.keyboard.press('Escape');
  await expect(page.locator('#edu-help-drawer')).toBeHidden();
  const term = page.locator('[data-edu-term=requires]').first();
  await term.focus();
  await expect(page.locator('#edu-tooltip')).toBeVisible();
  await expect(page.locator('#edu-tooltip [data-tooltip-short]')).not.toBeEmpty();
  await page.keyboard.press('Escape');
  await expect(page.locator('#edu-tooltip')).toBeHidden();
  await page.locator('#edu-guidance').selectOption('focused');
  await page.goto('/lab');
  await expect(page.locator('#edu-guidance')).toHaveValue('focused');
});

const destinations = ['/', '/start', '/system', '/guarantees', '/atlas',
  '/atlas/po_a2', '/atlas/po_composite_recovery', '/proofs', '/assurance',
  '/repository', '/glossary', '/lab', '/claims/po_a2', '/lens/po_a2',
  '/lens/po_exposure_retain'];

for (const width of [390, 800, 1024, 1440]) {
  test(`all educational and review destinations reflow at ${width}px`, async ({page}, testInfo) => {
    test.setTimeout(120000);
    await page.setViewportSize({width, height: 900});
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    for (const path of destinations) {
      const response = await page.goto(path);
      expect(response.status(), path).toBe(200);
      await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
      expect(await page.evaluate(() => document.documentElement.scrollWidth), path).toBeLessThanOrEqual(width);
      await page.locator('#edu-help-toggle').click();
      await expect(page.locator('#edu-help-drawer')).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(page.locator('#edu-help-drawer')).toBeHidden();
      await expect(page.locator('#edu-help-toggle')).toBeFocused();
      if (['/', '/atlas', '/lab', '/lens/po_a2'].includes(path)) {
        await page.screenshot({path: testInfo.outputPath(`${path.replaceAll('/', '_') || 'home'}-${width}.png`), fullPage: true});
      }
    }
    expect(errors).toEqual([]);
  });
}

test('touch help and patched controls preserve ordinary review actions', async ({browser}) => {
  const context = await browser.newContext({hasTouch: true, viewport: {width: 390, height: 844}});
  const page = await context.newPage();
  try {
    await page.goto('/lens/po_a2');
    await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
    const term = page.locator('[data-edu-term=requires]').first();
    await term.tap();
    await expect(page.locator('#edu-term-dialog')).toBeVisible();
    await page.getByRole('button', {name: 'Close term guide'}).tap();
    await expect(page.locator('#edu-term-dialog')).toBeHidden();
    await expect(page.locator('#lens-confirm')).toBeDisabled();
    await expect(page.locator('#lens-feedback-withheld')).toBeVisible();
    await page.goto('/claims/po_a2');
    await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
    await page.getByRole('button', {name: '1¢ more', exact: true}).tap();
    await expect(page.locator('#review-amount')).toHaveValue('101');
    await page.locator('#edu-help-toggle').tap();
    await expect(page.locator('#edu-help-drawer')).toBeVisible();
    await page.getByRole('button', {name: 'Close page guide'}).tap();
    await expect(page.locator('#edu-help-drawer')).toBeHidden();
  } finally {
    await context.close();
  }
});

test('tooltip keyboard, hover and description state survive a LiveView patch', async ({page}) => {
  await page.goto('/claims/po_a2');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await page.locator('#edu-guidance').selectOption('focused');
  await page.getByRole('button', {name: '1¢ more', exact: true}).click();
  await expect(page.locator('#review-amount')).toHaveValue('101');
  await expect(page.locator('#edu-guidance')).toHaveValue('focused');
  const term = page.locator('[data-edu-term=claim]');
  await term.evaluate(node => node.setAttribute('aria-describedby', 'policy-anchor'));
  await term.focus();
  await expect(term).toHaveAttribute('aria-describedby', 'policy-anchor edu-tooltip');
  await page.keyboard.press('Enter');
  await expect(page.locator('#edu-term-dialog')).toBeVisible();
  await expect(page.locator('#edu-tooltip')).toBeHidden();
  await page.keyboard.press('Escape');
  await expect(page.locator('#edu-term-dialog')).toBeHidden();
  await expect(term).toBeFocused();
  await expect(term).toHaveAttribute('aria-describedby', 'policy-anchor');
  await page.keyboard.press('Space');
  await expect(page.locator('#edu-term-dialog')).toBeVisible();
  await expect(page.locator('#edu-tooltip')).toBeHidden();
  await page.keyboard.press('Escape');
  await expect(page.locator('#edu-term-dialog')).toBeHidden();
  await term.evaluate(node => node.blur());
  await term.hover();
  await expect(page.locator('#edu-tooltip')).toBeVisible();
  await page.locator('#edu-tooltip').hover();
  await expect(page.locator('#edu-tooltip')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.locator('#edu-tooltip')).toBeHidden();
});


test('claim summary copy retains scope and source identity', async ({page, context}) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto('/atlas/po_a2');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#edu-claim-scope')).toBeVisible();
  await page.locator('#edu-copy-claim').click();
  await expect(page.locator('#copy-status')).toContainText('Copied');
  const copied = await page.evaluate(() => navigator.clipboard.readText());
  expect(copied).toContain('Scope:');
  expect(copied).toContain('test/laws/po_a2_test.exs');
  expect(copied).toContain('Registration does not establish formal acceptance');
});

test('ordinary glossary aliases lead to authored explanations and source paths', async ({page}) => {
  await page.goto('/glossary?q=pointwise');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#term-pointwise')).toBeVisible();
  await page.locator('#term-pointwise summary').click();
  await expect(page.locator('#term-pointwise [data-source-path]')).toBeVisible();
  await expect(page.locator('#term-pointwise [data-source-path]')).not.toBeEmpty();
});
