const {test, expect} = require('@playwright/test');

test('Guided keeps optional review tools local and evidence directly accessible', async ({page}) => {
  await page.goto('/claims/po_a2');
  await expect(page).toHaveURL(/\/claims\/po_a2\/trace-/);
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  const traceId = new URL(page.url()).pathname.split('/').at(-1);
  const read = async () => (await (await page.request.get(`/sessions/${traceId}/export`)).json()).trace;
  const before = await read();

  await expect(page.locator('#hypothetical-output h3')).toHaveText('What-if output');
  await expect(page.locator('#what-if-guide')).toContainText('the ledger did not return it');
  await expect(page.locator('#case-review-tools')).toHaveJSProperty('open', false);
  await page.locator('#review-amount').fill('99');
  await expect(page.locator('#ledger-output')).toContainText('99¢ reserved');
  await page.locator('#case-review-tools > summary').click();
  await expect(page.locator('#add-observation')).toBeVisible();
  expect((await read()).steps).toEqual(before.steps);

  await page.locator('#case-review-tools > summary').click();
  await page.locator('#inspector-tools [phx-value-view=proof]').click();
  await expect(page.locator('#case-proof-depth')).toHaveJSProperty('open', true);
  await expect(page.locator('#proof-script')).toBeVisible();
  await expect(page.locator('#proof-panel')).toBeFocused();
  await expect(page.locator('#case-review-tools')).toHaveJSProperty('open', false);
  await expect(page.locator('#review-amount')).toHaveValue('99');
  expect((await read()).steps).toEqual(before.steps);
});

for (const width of [320, 768, 1440]) {
  test(`account, what-if and case result remain usable at ${width}px`, async ({page}) => {
    await page.setViewportSize({width, height: 900});
    await page.goto('/claims/po_exposure_retain');
    await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
    await expect(page.locator('#ledger-output h3')).toHaveText('Code returned');
    await expect(page.locator('#hypothetical-output h3')).toHaveText('What-if output');
    await expect(page.locator('#verdict-signal')).toHaveAttribute('data-state', 'rejects');
    await expect(page.locator('#validity-row td').last()).toHaveText('Account is valid');
    await expect(page.locator('#selected-law-row td').last()).toHaveText('Rejects what-if output');
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
    await page.locator('#edit-candidate').focus();
    await page.keyboard.press('Enter');
    await expect(page.locator('#case-tools')).toBeVisible();
    await page.locator('#case-view-inspector').click();
    await expect(page.locator('#case-review-tools')).toHaveJSProperty('open', true);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  });
}
