const {test, expect} = require('@playwright/test');

async function open(page, slug = 'po_a2') {
  await page.goto(`/claims/${slug}`);
  await expect(page).toHaveURL(new RegExp(`/claims/${slug}/trace-`));
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
}

async function saved(page) {
  const id = new URL(page.url()).pathname.split('/').at(-1);
  return (await (await page.request.get(`/sessions/${id}/export`)).json()).trace;
}

test('compact source-linked rule header distinguishes example, full claim and real comparison', async ({page}) => {
  await open(page);
  await expect(page.locator('#law-picker select')).toHaveValue('po_a2');
  await expect(page.locator('#policy-anchor')).toContainText('all remaining capacity');
  await expect(page.locator('#example-provenance')).toContainText('Illustrative example');
  await expect(page.locator('#source-change-details')).toHaveCount(0);
  await expect(page.locator('#selected-claim')).not.toHaveAttribute('open');
  await page.locator('#selected-claim summary').click();
  await expect(page.locator('#requires-expression')).toBeVisible();
  await expect(page.locator('#expects-expression')).toBeVisible();
  await page.locator('#selected-claim summary').click();
  await page.locator('#law-picker select').selectOption('po_b1_void');
  await expect(page.locator('#standalone-law-scope')).toContainText('no proposed source change');
  await expect(page.locator('#example-provenance')).toHaveCount(0);
});

test('structured in-card differences and noninteractive ghosts are not candidate rows', async ({page}) => {
  await open(page);
  await expect(page.locator('#hypothetical-output .field-delta').first()).toBeVisible();
  await expect(page.locator('#hypothetical-output')).toContainText('(-100¢)');
  await expect(page.locator('#hypothetical-output .comparison-ghost')).toContainText('Absent from alternative');
  await expect(page.locator('#hypothetical-output .comparison-ghost button')).toHaveCount(0);
  const candidateCount = await page.locator('#hypothetical-output .output-entries li').count();
  expect(candidateCount).toBe(0);
  await expect(page.locator('#output-differences')).not.toHaveAttribute('open');
  await page.locator('#output-differences summary').click();
  await expect(page.locator('#output-differences ol')).toBeVisible();
  await expect(page.locator('#output-differences')).toContainText('Entry order / identities');
  await page.locator('#edit-candidate').click();
  await page.getByRole('button', {name: 'Reset to code result'}).click();
  await expect(page.locator('#hypothetical-output .field-delta')).toHaveCount(0);
  await expect(page.locator('#hypothetical-output .comparison-ghost')).toHaveCount(0);
  await expect(page.locator('#same-output')).toBeVisible();
});

test('observed condition groups have exact truth counts and local validated proof excerpts', async ({page}) => {
  await open(page);
  await expect(page.locator('#dissector .condition-group')).not.toHaveCount(0);
  await expect(page.locator('#group-0-requires-amount_domain')).toContainText('Positive amount domain');
  await expect(page.locator('#group-0-requires-eligibility')).toContainText('Admission eligibility');
  await expect(page.locator('#complete-tree-0-requires')).not.toHaveAttribute('open');
  await page.locator('#complete-tree-0-requires summary').click();
  await expect(page.locator('#tree-clause-0-requires-root')).toBeVisible();
  await page.locator('#complete-tree-0-requires summary').click();
  await page.locator('#proof-source-workspace .proof-source-stages button').nth(5).click();
  await expect(page.locator('#dissector .selected-clause')).toHaveCount(1);
  const excerpt = page.locator('#reading-excerpt-0-requires');
  await expect(excerpt).toBeVisible();
  await expect(excerpt).toContainText('Remaining arithmetic');
  await expect(excerpt).toContainText('not a proof of this clause in isolation');
  await expect(page.locator('#selected-reading-links')).toBeVisible();
});

test('factual accepts and rejects have equal prominence and review actions keep their target', async ({page}) => {
  await open(page);
  const initial = await saved(page);
  const focus = page.locator('#active-predicate-result');
  await expect(focus).toContainText('Accepts code result');
  await expect(focus).toContainText('Rejects alternative');
  await expect(page.locator('#applicability-row')).toContainText('Applies');
  await expect(page.locator('#local-decision-target')).toContainText('session note');
  await expect(page.locator('#decision-docket button')).toHaveCount(3);
  await page.locator('#review-amount').fill('99');
  await page.locator('#request-repair').click();
  const after = await saved(page);
  expect(after.steps).toEqual(initial.steps);
  expect(after.notes.length).toBe(initial.notes.length + 1);
  expect(after.notes.at(-1).text).toContain('Unsaved experiment');
  await expect(page.locator('#scratch-status')).toBeVisible();
});

test('a malformed candidate clears both the result and stale field markers', async ({page}) => {
  await open(page);
  await page.locator('#edit-candidate').click();
  await page.locator('#advanced-editor').click();
  await page.locator('#candidate-json').fill('{not valid');
  await page.locator('#candidate-json-form button').click();
  await expect(page.locator('#active-predicate-result')).toHaveCount(0);
  await expect(page.locator('#hypothetical-output .field-delta')).toHaveCount(0);
  await expect(page.locator('#invalid-candidate')).toBeVisible();
  await expect(page.locator('#candidate-json')).toHaveValue('{not valid');
});

for (const [width, height] of [[1440, 900], [1280, 800], [390, 844], [640, 400]]) {
  test(`reading and keyboard order survive ${width}x${height}`, async ({page}) => {
    await page.setViewportSize({width, height});
    await open(page);
    await expect(page.locator('#law-picker')).toBeVisible();
    await expect(page.locator('#review-amount')).toBeVisible();
    await expect(page.locator('#active-predicate-result')).toBeVisible();
    const geometry = await page.evaluate(() => ({
      scrollWidth: document.documentElement.scrollWidth,
      clientWidth: document.documentElement.clientWidth,
      viewport: innerWidth,
      source: document.querySelector('#review-comparison').getBoundingClientRect().top,
      input: document.querySelector('#review-amount').getBoundingClientRect().top,
      check: document.querySelector('#case-findings').getBoundingClientRect().top,
      proof: document.querySelector('#proof-panel').getBoundingClientRect().top,
    }));
    expect(geometry.scrollWidth).toBeLessThanOrEqual(geometry.viewport);
    expect(geometry.source).toBeLessThan(geometry.input);
    expect(geometry.check).toBeLessThan(geometry.proof);
    await page.locator('#edit-candidate').click();
    await page.locator('#alternative-counter input').focus();
    await page.keyboard.press('Escape');
    await expect(page.locator('#edit-candidate')).toBeFocused();
    await page.locator('#selected-claim summary').focus();
    await page.keyboard.press('Enter');
    await expect(page.locator('#requires-expression')).toBeVisible();
  });
}
