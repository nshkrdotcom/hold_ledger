const {test, expect} = require('@playwright/test');

for (const width of [390, 800, 1024, 1440]) {
  test(`orientation is usable without overflow at ${width}px`, async ({page}) => {
    await page.setViewportSize({width, height: 900});
    await page.goto('/');
    await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
    await expect(page.locator('#edu-overview h1')).toContainText('Follow the code.');
    await expect(page.locator('#edu-home-example')).toHaveAttribute('data-moment', '0');
    await expect(page.locator('#edu-home-capacity-held')).toHaveText('0¢');
    await expect(page.locator('.edu-journey')).toHaveCount(3);
    await expect(page.locator('.edu-stat-strip')).toContainText('Registered claims');
    await expect(page.locator('#edu-overview')).not.toContainText('49 proven');
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
    await page.getByRole('link', {name: /Follow a payment hold/}).first().click();
    await expect(page.locator('#edu-story')).toBeVisible();
    await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
    await page.getByRole('button', {name: /3 Timeout/}).click();
    await expect(page.locator('#edu-story')).toContainText('reply never arrives');
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  });
}

test('the payment story opens the exact computed prefix in Case Lab', async ({page}) => {
  await page.goto('/start');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#edu-story')).toHaveAttribute('data-moment', '0');
  await expect(page.locator('#edu-story-initial-held')).toHaveText('0¢');
  await expect(page.locator('#edu-story-initial-available')).toHaveText('100¢');
  await expect(page.locator('#edu-story-prev')).toBeDisabled();
  await page.locator('#edu-story-next').click();
  await expect(page.locator('#edu-story')).toHaveAttribute('data-moment', '1');
  await expect(page.locator('#edu-story-before-held')).toHaveText('0¢');
  await expect(page.locator('#edu-story-after-held')).toHaveText('100¢');
  await expect(page.locator('#edu-story-result code')).toContainText(':admitted');
  await page.locator('#edu-story-next').click();
  await expect(page.locator('#edu-story-result')).toContainText('100¢');
  await page.locator('#edu-story-next').click();
  await expect(page.locator('#edu-story')).toHaveAttribute('data-moment', '3');
  await expect(page.locator('#edu-story-after')).toContainText('Outcome unknown');
  await expect(page.locator('#edu-story-after-available')).toHaveText('0¢');
  await expect(page.locator('#edu-story-after-slots-free')).toHaveText('1');
  await page.locator('#edu-story-next').click();
  await expect(page.locator('#edu-story-result code')).toContainText(':insufficient_amount');
  await expect(page.locator('#edu-story-after-held')).toHaveText('100¢');
  await page.locator('#edu-story-prev').click();
  await page.locator('#edu-open-moment').click();
  await expect(page).toHaveURL(/\/claims\/po_b2\/trace-[^/?]+$/);
  await expect(page.locator('#timeline > button')).toHaveCount(4);
  await expect(page.locator('#timeline [aria-current=step]')).toContainText('timeout');
  await expect(page.locator('#trace-revision')).toContainText('Saved history');
});

test('home controls update the account and retain the selected moment in the walkthrough link', async ({page}) => {
  await page.goto('/');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await page.locator('#edu-home-next').click();
  await expect(page.locator('#edu-home-example')).toHaveAttribute('data-moment', '1');
  await expect(page.locator('#edu-home-capacity-held')).toHaveText('100¢');
  await expect(page.locator('#edu-home-result code')).toContainText(':admitted');
  await page.locator('#edu-home-example a[href="/start?moment=1"]').click();
  await expect(page.locator('#edu-story')).toHaveAttribute('data-moment', '1');
  await expect(page.locator('#edu-story-before-held')).toHaveText('0¢');
});

test('the focused mutation directory exposes M7 source and its actual target', async ({page}) => {
  await page.goto('/examples');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('.learning-example-picker button')).toHaveCount(10);
  await page.locator('#edu-mutation-M7').click();
  await expect(page).toHaveURL(/\/examples\?example=M7$/);
  await expect(page.locator('#edu-selected-mutation')).toHaveAttribute('data-example-id', 'M7');
  await expect(page.locator('#edu-mutation-M7')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('#edu-mutation-claim')).toHaveAttribute('href', '/atlas/po_b3');
  await expect(page.locator('#edu-mutation-patch')).toContainText(':voiding, []}');
  await expect(page.locator('#edu-examples-scope')).toContainText('does not run the mutation');
  await page.goto('/examples?example=missing');
  await expect(page.locator('#edu-mutation-unavailable')).toBeVisible();
  await page.locator('#edu-mutation-M4').click();
  await expect(page.locator('#edu-selected-mutation')).toHaveAttribute('data-example-id', 'M4');
});

test('translation distinguishes actual law, generated material and supplied theorem', async ({page}) => {
  await page.goto('/translation');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#translation-elixir')).toContainText('request_eligible?');
  await expect(page.locator('#translation-generated-source, #translation-generated-unavailable')).toHaveCount(1);
  await expect(page.locator('#translation-theorem')).toContainText('Source text');
  await expect(page.locator('#translation-theorem-header')).toContainText('Lynx.Term');
  await expect(page.locator('#translation-proof')).not.toHaveAttribute('open', '');
  await page.locator('#translation-implementation > summary').click();
  await expect(page.locator('#translation-implementation')).toContainText('def request(');
  await expect(page.locator('#translation-implementation')).toContainText('amount <= amount_limit - used_amount');
  await page.locator('#translation-proof > summary').focus();
  await page.keyboard.press('Enter');
  await expect(page.locator('#translation-proof')).toHaveAttribute('open', '');
  await expect(page.locator('#translation-proof pre')).toBeVisible();
});

test('learning source panels and controls reflow with enlarged text', async ({page}) => {
  await page.setViewportSize({width: 390, height: 900});
  for (const path of ['/', '/start?moment=3', '/how-it-fits', '/examples?example=M7', '/translation']) {
    await page.goto(path);
    await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
    await page.addStyleTag({content: 'html {font-size: 200%}'});
    expect(await page.evaluate(() => document.documentElement.scrollWidth), path).toBeLessThanOrEqual(390);
  }
  await page.locator('#translation-proof > summary').click();
  await page.locator('#translation-implementation > summary').click();
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
});

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
  await page.locator('#edu-help-toggle').click();
  await page.locator('#edu-guidance').selectOption('focused');
  await page.keyboard.press('Escape');
  await page.goto('/lab');
  await expect(page.locator('#edu-guidance')).toHaveValue('focused');
});

const destinations = ['/', '/start', '/how-it-fits', '/examples', '/translation', '/system', '/guarantees', '/atlas',
  '/atlas/po_a2', '/atlas/po_composite_recovery', '/proofs', '/assurance',
  '/repository', '/glossary', '/lab', '/claims/po_a2', '/claims/po_b7', '/lens/po_a2',
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
  await page.locator('#edu-help-toggle').click();
  await page.locator('#edu-guidance').selectOption('focused');
  await page.keyboard.press('Escape');
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

test('glossary finds authored aliases and shows an empty search honestly', async ({page}) => {
  await page.goto('/glossary?q=semantic%20gap');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#term-policy-gap')).toBeVisible();
  await page.locator('#edu-term-query').fill('no-such-glossary-entry');
  await expect(page.locator('#edu-glossary-results details')).toHaveCount(0);
  await expect(page.locator('.edu-empty')).toContainText('No matching terms.');
});

test('claim context stays local and examples explain their source without a detour', async ({page}) => {
  await page.goto('/');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#claim-navigation')).toHaveCount(0);
  await expect(page.locator('#edu-overview-lesson')).toContainText('refuse every request');
  await page.goto('/atlas/po_a2');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#claim-navigation a[aria-current=page]')).toHaveAttribute('href', '/atlas/po_a2');
  await expect(page.locator('#edu-claim-editorial')).toContainText('Editorial draft');
  await expect(page.locator('#edu-claim-editorial')).toContainText('Owner review of this explanation is not recorded here.');
  const example = page.locator('#example-m4');
  await expect(example).toContainText('Expected from the source');
  await example.locator('summary').click();
  await expect(example.locator('code').filter({hasText: '{:request, 11, 100}'})).toBeVisible();
  await expect(example.locator('a[href="/atlas/po_a2"]')).toContainText('Read the claim:');
  await expect(page.locator('a[href="/repository#mutation-examples"]')).toHaveCount(0);
  await page.goto('/atlas/po_composite_recovery');
  await expect(page.locator('#claim-navigation a[href^="/lens/"]')).toHaveCount(0);
});

test('the example directory preserves the local-cancellation control', async ({page}) => {
  await page.goto('/repository');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('.edu-example-card')).toHaveCount(18);
  const control = page.locator('#example-p08');
  await expect(control).toContainText('Correct local cancellation');
  await control.locator('summary').click();
  await expect(control.locator('pre')).toBeVisible();
  await expect(control.locator('pre')).toContainText('"reserved"');
  await expect(control.locator('pre')).toContainText('"effects": []');
  const fixture = control.getByRole('region', {name: 'Source fixture for P08'});
  await fixture.focus();
  await expect(fixture).toBeFocused();
  await fixture.press('End');
  await expect.poll(() => fixture.evaluate(node => node.scrollTop)).toBeGreaterThan(0);
});

test('optional background reading has keyboard-accessible answer disclosures', async ({page}) => {
  await page.goto('/start');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  const question = page.locator('#edu-hold-primer .edu-self-check summary');
  await question.focus();
  await page.keyboard.press('Enter');
  await expect(page.locator('#edu-hold-primer .edu-self-check p')).toBeVisible();
  await expect(page.locator('#edu-hold-primer')).toContainText('possible later capture');
  await page.goto('/assurance');
  await expect(page.locator('#edu-kernel-primer')).toContainText('formal statement');
  await expect(page.locator('#edu-kernel-primer a[href="https://lean-lang.org/doc/reference/latest/ValidatingProofs/"]')).toBeVisible();
});

test('authored Lab help remains available on request and processor controls', async ({page}) => {
  await page.goto('/claims/po_a2');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await page.locator('#record-event').click();
  const requestId = page.locator('#next-event input[data-edu-term="request-id"]');
  await requestId.focus();
  await expect(page.locator('#edu-tooltip')).toBeVisible();
  await expect(page.locator('#edu-tooltip [data-tooltip-short]')).not.toBeEmpty();
  await page.keyboard.press('Escape');
  await expect(requestId).toBeFocused();
  const amount = page.locator('#event_amount');
  await page.locator('#event_type').selectOption('dispatch');
  await expect(amount).toBeDisabled();
  await page.locator('#event_type').selectOption('request');
  await expect(amount).toBeEnabled();
  await expect(amount).toHaveAttribute('data-help', 'lab.amount');
  await amount.focus();
  await expect(page.locator('#edu-tooltip')).toBeVisible();
  await expect(page.locator('#edu-tooltip [data-tooltip-short]')).toContainText('Amounts are whole cents');
  await page.keyboard.press('Escape');
  await expect(amount).toBeFocused();
  await page.locator('#coupled-model').click();
  await expect(page.locator('#remote-state')).toBeVisible();
  await page.locator('#coupled-event-guide summary').click();
  await page.locator('#coupled-event-guide [data-edu-term="issued"]').focus();
  await expect(page.locator('#edu-tooltip')).toBeVisible();
  await expect(page.locator('#edu-tooltip [data-tooltip-short]')).toContainText('recorded');
  await page.keyboard.press('Escape');
  await page.goto('/claims/po_exposure_retain');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await page.locator('#inspector-tools [phx-value-view="premises"]').click();
  const fencing = page.locator('#fencing-toggle[data-edu-term="terminal-fence"]');
  await fencing.focus();
  await expect(page.locator('#edu-tooltip')).toBeVisible();
  await page.keyboard.press('Escape');
  const prior = await fencing.getAttribute('aria-checked');
  await fencing.click();
  await expect(fencing).toHaveAttribute('aria-checked', prior === 'true' ? 'false' : 'true');
});

for (const [width, route] of [[390, '/'], [390, '/start?moment=3'], [390, '/glossary'], [390, '/guarantees'], [1024, '/how-it-fits']]) {
  test(`enlarged text wraps with disclosures open on ${route} at ${width}px`, async ({page}) => {
    await page.setViewportSize({width, height: 900});
    await page.goto(route);
    await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
    await page.evaluate(async () => {
      document.documentElement.style.fontSize = '200%';
      document.querySelectorAll('details').forEach(node => { node.open = true; });
      await document.fonts.ready;
    });
    await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  });
}
