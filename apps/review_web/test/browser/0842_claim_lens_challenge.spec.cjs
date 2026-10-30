const {test, expect} = require('@playwright/test');

test.beforeEach(async ({page}) => {
  page.qaErrors = [];
  page.on('pageerror', error => page.qaErrors.push(error.message));
  page.on('console', message => {
    if (message.type() === 'error') page.qaErrors.push(message.text());
  });
});
test.afterEach(async ({page}) => expect(page.qaErrors).toEqual([]));

async function connected(page) {
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
}
async function confirm(page, decision = 'concern') {
  await page.locator(`#lens-decision-${decision}`).click();
  await page.getByRole('textbox', {name: 'Your explanation'}).fill('Initial synthetic answer');
  await page.locator('#lens-confirm').click();
  await expect(page.locator('#lens-initial-answer')).toContainText('Initial synthetic answer');
}
async function withheld(page) {
  await expect(page.locator('#lens-feedback-withheld')).toBeVisible();
  // Omitted from the DOM, rather than CSS-hidden answers.
  for (const id of ['lens-policy-verdict', 'lens-baseline-verdict', 'lens-hypothetical-verdict',
    'lens-gap', 'lens-coverage', 'lens-worked-challenge', 'lens-selected-clause']) {
    await expect(page.locator(`#${id}`)).toHaveCount(0);
  }
}

for (const width of [1280, 390]) {
  test(`Challenge requires an explicit answer and reveals source-bound coverage at ${width}px`, async ({page}) => {
    await page.setViewportSize({width, height: 900});
    await page.goto('/lens/po_a2?mode=challenge');
    await connected(page);
    await withheld(page);
    await expect(page.locator('.lens-decisions [aria-pressed=true]')).toHaveCount(0);
    await expect(page.locator('#lens-confirm')).toBeDisabled();
    await expect(page.locator('#lens-policy')).toContainText('An exact amount fit is admitted.');
    await expect(page.locator('#lens-case-brief')).toContainText('Challenged output');
    await expect(page.locator('#lens-evidence-legend')).toContainText('Pointwise Evaluation');
    await expect(page.locator('#lens-source-contract')).toContainText('request_eligible?');
    const choice = page.locator('#lens-decision-unresolved');
    await choice.focus();
    await expect(choice).toHaveCSS('outline-style', 'solid');
    await choice.press('Enter');
    await expect(choice).toHaveAttribute('aria-pressed', 'true');
    // Choosing is still a draft; reveal is a separate deliberate action.
    await withheld(page);
    await expect(page.locator('#lens-confirm')).toBeEnabled();
    await page.getByRole('textbox', {name: 'Your explanation'}).fill('Inspect the boundary');
    await page.locator('#lens-confirm').click();
    await expect(page.locator('#lens-initial-answer')).toContainText('needs more evidence');
    await expect(page.locator('#lens-near-misses')).toContainText('Legitimate local release');
    await expect(page.locator('#lens-copy-packet')).toBeVisible();
    await expect(page.locator('#lens-gap')).toContainText('Potential loss of required coverage');
    await expect(choice).toBeDisabled();
    await expect(page.locator('#lens-review-form textarea')).toBeDisabled();
    await expect(page.locator('#lens-coverage-below')).toHaveAttribute('data-change', 'same');
    await expect(page.locator('#lens-coverage-exact')).toHaveAttribute('data-change', 'removed');
    await expect(page.locator('#lens-coverage-above')).toHaveAttribute('data-change', 'same');
    await expect(page.locator('#lens-hypothetical-verdict')).toContainText("Doesn't apply");
    await expect(page.locator('#lens-hypothetical-verdict')).toHaveCSS('border-top-style', 'dashed');
    await page.locator('#lens-worked-challenge summary').click();
    await expect(page.locator('#lens-worked-challenge pre')).toContainText('insufficient_amount');
    await expect(page.locator('#lens-worked-challenge pre')).toContainText('100');
    await expect(page.getByRole('main')).toHaveCount(1);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
    await page.reload();
    await connected(page);
    await withheld(page);
    await expect(page.locator('.lens-decisions [aria-pressed=true]')).toHaveCount(0);
  });
}

test('changing context resets the answer and Challenge remains in the study URL', async ({page}) => {
  await page.goto('/lens/po_a2?mode=challenge');
  await connected(page);
  await confirm(page);
  await expect(page.locator('#lens-decision-concern')).toHaveCSS('border-top-color', 'rgb(183, 121, 31)');
  await page.locator('#lens-variation-proof_only').click();
  await withheld(page);
  await expect(page.locator('#lens-proof-control')).toContainText('Proof-body-only change proposed');
  await confirm(page, 'no-change');
  await expect(page.locator('#lens-gap')).toContainText('No claim-level change');
  await expect(page.locator('#lens-proof-control')).toContainText('No semantic delta in specification');
  await expect(page.locator('.lens-clause-edited')).toHaveCount(0);
  await page.locator('#lens-study-picker a[href="/lens/po_exposure_retain"]').click();
  await connected(page);
  await withheld(page);
  await expect(page.locator('#lens-confirm')).toBeDisabled();
  await confirm(page, 'expected');
  await expect(page.locator('#lens-gap')).toContainText('Potential overconstraint');
  await expect(page.locator('#lens-coverage-confirmed')).toHaveAttribute('data-change', 'added');
  await page.locator('#lens-try-again').click();
  await withheld(page);
  await expect(page.locator('#lens-review-form textarea')).toHaveValue('');
  await page.locator('#lens-exercise-modes a').filter({hasText: 'Explore'}).click();
  await expect(page.locator('#lens-gap')).toBeVisible();
  await page.locator('#lens-exercise-modes a').filter({hasText: 'Review first'}).click();
  await withheld(page);
});
