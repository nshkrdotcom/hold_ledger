const {test, expect} = require('@playwright/test');

async function open(page, slug = 'po_a2') {
  await page.goto(`/claims/${slug}`);
  await expect(page).toHaveURL(new RegExp(`/claims/${slug}/trace-`));
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  // These regressions exercise the detailed source workspace.
  await page.locator('#case-view-inspector').click();
  await expect(page.locator('#review-document')).toHaveAttribute('data-case-view', 'inspector');
}

async function saved(page) {
  const id = new URL(page.url()).pathname.split('/').at(-1);
  const response = await page.request.get(`/sessions/${id}/export`);
  expect(response.status()).toBe(200);
  return (await response.json()).trace;
}

test('field differences update with unsaved edits and clear when restored', async ({page}) => {
  await open(page, 'po_exposure_retain');
  const before = await saved(page);
  await expect(page.locator('#output-differences')).toContainText('Reserved');
  await expect(page.locator('#output-differences')).toContainText('Entry');
  await expect(page.locator('#output-differences')).toContainText('Result');
  await expect(page.locator('#selected-law-row td').last()).toHaveText('Rejects proposed output');
  await page.locator('#edit-candidate').click();
  await page.getByRole('button', {name: 'Reset to code result', exact: true}).click();
  await expect(page.locator('#same-output')).toHaveText('Same as code result.');
  await page.locator('#alternative-counter input').fill('0');
  await expect(page.locator('#output-differences')).toContainText('100¢');
  await expect(page.locator('#output-differences')).toContainText('0¢');
  await expect(page.locator('#validity-row td').last()).toHaveText('Accounting does not balance');
  expect((await saved(page)).steps).toEqual(before.steps);
  await expect(page.locator('#case-tools')).toBeVisible();
});

test('malformed alternative clears the checked result without saving the last valid candidate', async ({page}) => {
  await open(page, 'po_a2');
  const before = await saved(page);
  await page.locator('#edit-candidate').click();
  await page.locator('#advanced-editor').click();
  const validJSON = await page.locator('#candidate-json').inputValue();
  await page.locator('#candidate-json').fill('{broken');
  await page.locator('#candidate-json-form button').click();
  await expect(page.locator('#invalid-candidate')).toBeVisible();
  await expect(page.locator('#contrast-matrix')).toHaveCount(0);
  await expect(page.locator('#output-differences')).toHaveCount(0);
  expect((await saved(page)).steps).toEqual(before.steps);
  await expect(page.locator('#candidate-json')).toHaveValue('{broken');
  await page.locator('#candidate-json').fill(validJSON);
  await page.locator('#candidate-json-form button').click();
  await expect(page.locator('#contrast-matrix')).toBeVisible();
  await expect(page.locator('#invalid-candidate')).toHaveCount(0);
});

test('applicability, code acceptance, alternative acceptance and accounting stay distinct', async ({page}) => {
  await open(page, 'po_exposure_retain');
  await expect(page.locator('#applicability-row')).toContainText('Applies');
  await expect(page.locator('#selected-law-row td').first()).toHaveText('Accepts code result');
  await expect(page.locator('#selected-law-row td').last()).toHaveText('Rejects proposed output');
  await expect(page.locator('#validity-row td').last()).toHaveText('Accounting balances');
  await expect(page.locator('#review-help')).toContainText('not automatically a defect');
});

test('source-bound proof passage and observed clause select each other by keyboard', async ({page}) => {
  await open(page, 'po_a2');
  const source = page.locator('#proof-source-workspace');
  const step = source.locator('.proof-source-stages button').nth(2);
  await step.focus();
  await page.keyboard.press('Enter');
  await expect(page.locator('#selected-reading-links')).toBeVisible();
  await expect(page.locator('#dissector .clause-select:focus')).toHaveText('amount <= amount_limit - used_amount');
  const clauses = page.locator('#dissector .connected-clause button.clause-select');
  await expect(clauses.first()).toBeVisible();
  await clauses.first().focus();
  await page.keyboard.press('Enter');
  await expect(page.locator('#dissector .selected-clause')).toHaveCount(1);
  await expect(source.locator('.active-proof-line').first()).toBeVisible();
  await page.locator('#inspector-tools [phx-value-view=artifacts]').click();
  await expect(page.locator('#formal-status')).toHaveText('Not supplied');
});

test('unsupported links and non-executable Lean claims remain explicit', async ({page}) => {
  await open(page, 'po_exposure_model');
  await expect(page.locator('#links-unsupported')).toContainText('This claim has no reviewed clause-to-proof links yet');
  await expect(page.locator('#dissector')).toContainText('Native Lean statement');
  await expect(page.locator('#proof-panel')).toBeVisible();
  await expect(page.locator('#nearby-observation')).toBeVisible();
});

test('observation beside results records context but not pending experiment', async ({page}) => {
  await open(page, 'po_a2');
  const before = await saved(page);
  await page.locator('#review-amount').fill('99');
  await expect(page.locator('#scratch-status')).toBeVisible();
  await expect(page.locator('#repair-unavailable')).toContainText('No comparison evidence');
  await page.locator('#add-observation').click();
  await page.locator('#note_text').fill('Question the exact-fit case.');
  await page.locator('#note-form button').click();
  const after = await saved(page);
  expect(after.steps).toEqual(before.steps);
  expect(after.notes).toHaveLength(before.notes.length + 1);
  expect(after.notes.at(-1).text).toContain('Unsaved experiment');
  await expect(page.locator('#scratch-status')).toBeVisible();
  await expect(page.locator('#review-amount')).toHaveValue('99');
});

for (const [width, height] of [[1440, 900], [1280, 800], [1024, 768], [390, 844]]) {
  test(`two-lane/read-order and document scrolling at ${width}x${height}`, async ({page}) => {
    await page.setViewportSize({width, height});
    await open(page);
    const metrics = await page.evaluate(() => {
      const rect = id => {
        const {x, top, left, width, height} = document.querySelector(id).getBoundingClientRect();
        return {x, top, left, width, height};
      };
      return {
        requirement: rect('#review-comparison'),
        case: rect('.case-stage'),
        checks: rect('#case-findings'),
        proof: rect('#proof-panel'),
        width: document.documentElement.scrollWidth,
        bodyOverflow: getComputedStyle(document.body).overflowY,
      };
    });
    expect(metrics.width).toBeLessThanOrEqual(width);
    expect(metrics.requirement.top).toBeLessThan(metrics.case.top);
    expect(metrics.proof.top).toBeGreaterThan(metrics.checks.top);
    if (width > 950) {
      expect(Math.abs(metrics.case.top - metrics.checks.top)).toBeLessThan(35);
      expect(metrics.checks.left).toBeGreaterThan(metrics.case.left);
    } else {
      expect(metrics.checks.top).toBeGreaterThan(metrics.case.top);
    }
    expect(metrics.bodyOverflow).not.toBe('hidden');
    await expect(page.locator('#add-observation')).toBeVisible();
    await expect(page.locator('[role=dialog]:visible,.tool-backdrop')).toHaveCount(0);
  });
}

for (const [slug, stage] of [['po_b1_timeout', 1], ['po_exposure_retain', 4]]) {
  test(`reviewed ${slug} postcondition links both output bases without changing the case`, async ({page}) => {
    await open(page, slug);
    const before = await saved(page);
    const proof = page.locator('#proof-source-workspace');
    await proof.locator('.proof-source-stages button').nth(stage).click();
    await expect(page.locator('#selected-reading-links')).toBeVisible();
    await expect(page.locator('#dissector .connected-clause[id*=candidate]')).not.toHaveCount(0);
    await page.getByRole('button', {name: 'Code result', exact: true}).click();
    await proof.locator('.proof-source-stages button').nth(stage).click();
    await expect(page.locator('#dissector .connected-clause[id*=actual]')).not.toHaveCount(0);
    expect((await saved(page)).steps).toEqual(before.steps);
    await page.locator('#law-picker select').selectOption('po_a4_duplicate');
    await expect(page).toHaveURL(/po_a4_duplicate/);
    await expect(page.locator('#selected-reading-links')).toHaveCount(0);
    await expect(page.locator('#dissector .selected-clause')).toHaveCount(0);
  });
}

test('200 percent effective desktop viewport keeps editing and evidence accessible', async ({browser}) => {
  // Native desktop zoom halves the CSS viewport. Render that layout at DPR 2;
  // this checks reflow, not the browser chrome's zoom control.
  const context = await browser.newContext({viewport: {width: 640, height: 400}, deviceScaleFactor: 2});
  const page = await context.newPage();
  try {
    await open(page, 'po_exposure_retain');
    await expect(page.locator('#selected-law-row')).toContainText('Rejects proposed output');
    await page.locator('#edit-candidate').click();
    await page.locator('#alternative-counter input').fill('7');
    await expect(page.locator('#validity-row')).toContainText('Accounting does not balance');
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await page.locator('#alternative-counter input').focus();
    await page.keyboard.press('Escape');
    await expect(page.locator('#edit-candidate')).toBeFocused();
    await page.locator('#proof-source-workspace .proof-source-stages button').nth(4).click();
    await expect(page.locator('#selected-reading-links')).toBeVisible();
    await page.screenshot({path: '../../../../tmp/acceptance_0711/zoom-200-effective.png', fullPage: true});
  } finally {
    await context.close();
  }
});
