const {test, expect} = require('@playwright/test');

for (const width of [390, 800, 1024, 1440]) {
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
  await expect(page.locator('.edu-profile-panel').filter({hasText: 'SOURCE IDENTITY'})).toContainText('Native Lean');
});

test('help is available by click and keyboard, with glossary on real screens', async ({page}) => {
  await page.goto('/lens/po_a2?mode=explore');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await page.locator('#edu-help-toggle').click();
  await expect(page.locator('#edu-help-drawer')).toBeVisible();
  await expect(page.locator('#edu-help-title')).toContainText('Claim Lens');
  await page.keyboard.press('Escape');
  await expect(page.locator('#edu-help-drawer')).toBeHidden();
  const term = page.locator('[data-edu-term=requires]').first();
  await term.focus();
  await expect(page.locator('#edu-tooltip')).toBeVisible();
  await expect(page.locator('#edu-tooltip')).toContainText('precondition');
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
    await expect(page.locator('#edu-tooltip')).toBeVisible();
    await term.tap();
    await expect(page.locator('#edu-tooltip')).toBeHidden();
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
  await expect(page.locator('#edu-tooltip')).toHaveAttribute('data-pinned', 'true');
  await page.keyboard.press('Escape');
  await expect(page.locator('#edu-tooltip')).toBeHidden();
  await expect(term).toHaveAttribute('aria-describedby', 'policy-anchor');
  await page.keyboard.press('Space');
  await expect(page.locator('#edu-tooltip')).toHaveAttribute('data-pinned', 'true');
  await page.keyboard.press('Escape');
  await term.evaluate(node => node.blur());
  await term.hover();
  await expect(page.locator('#edu-tooltip')).toBeVisible();
  await page.locator('#edu-tooltip').hover();
  await expect(page.locator('#edu-tooltip')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.locator('#edu-tooltip')).toBeHidden();
});
