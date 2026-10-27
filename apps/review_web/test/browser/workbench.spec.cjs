const { test, expect } = require('@playwright/test');

async function newReview(page, seed) {
  await page.goto('/workbench');
  await expect(page.locator('#new-review-choices')).toBeVisible();
  if (seed === 'P01' || seed === 'P03' || seed === 'P04') {
    await page.locator(`[phx-value-seed="${seed}"]`).first().click();
  } else {
    await page.locator('[phx-value-seed="P01"]').first().click();
    await expect(page.locator('#candidate-form')).toBeVisible();
    await page.locator(`#load-${seed}`).click();
  }
  await expect(page).toHaveURL(/\/workbench\/[A-Za-z0-9_-]{16,80}$/);
  await expect(page.locator('#candidate-form')).toBeVisible();
}

test('source-linked reading, all registered source nodes, exports and repeat navigation', async ({page}) => {
  await newReview(page, 'P01');
  await expect(page.locator('#candidate-ok')).toBeVisible();
  await page.locator('#map-toggle').click();
  await expect(page.locator('#design-map')).toContainText('law.po_exposure_retain');
  await expect(page.locator('#design-map')).toContainText('Not a pointwise DSL probe');
  await page.locator('#source-toggle').click();
  await expect(page.locator('#source-panel')).toContainText('guides/specification.md');
  const fullSource = page.locator('#source-panel a').first();
  const href = await fullSource.getAttribute('href');
  const response = await page.request.get(href);
  expect(response.status()).toBe(200);
  expect(await response.text()).toContain('Event');
  await expect(page.locator('a[href$="/export.md"]')).toBeVisible();
  const url = new URL(page.url());
  const md = await page.request.get(`${url.pathname}/export.md`);
  expect(md.status()).toBe(200);
  expect(await md.text()).toContain('Unfinished review');
  const json = await page.request.get(`${url.pathname}/export.json`);
  expect(json.status()).toBe(200);
  const record = await json.json();
  expect(record.pinned_probes).toHaveLength(0);
  expect(record.seed_id).toBe('P01');
});

test('a changed full hypothetical is saved with its judgment and survives reload', async ({page}) => {
  await newReview(page, 'P04');
  const output = page.locator('#draft_output_json');
  const original = JSON.parse(await output.inputValue());
  original.after.used_amount = 99;
  await output.fill(JSON.stringify(original));
  await expect(page.locator('#candidate-ok')).toBeVisible();
  await page.locator('#escape-unacceptable').click();
  await expect(page.locator('#latest-answer')).toContainText('unacceptable');
  await page.reload();
  await expect(page.locator('#latest-answer')).toContainText('unacceptable');
  const record = await (await page.request.get(`${new URL(page.url()).pathname}/export.json`)).json();
  expect(record.pinned_probes).toHaveLength(1);
  expect(record.answers).toHaveLength(1);
  expect(record.answers[0].probe_id).toBe(record.pinned_probes[0].fingerprint);
  expect(record.pinned_probes[0].witness.output.after.used_amount).toBe(99);
});

test('invalid visible input disables acceptance; a final unblurred change is not reverted', async ({page}) => {
  await newReview(page, 'P04');
  const output = page.locator('#draft_output_json');
  const originally = JSON.parse(await output.inputValue());
  await output.fill('{');
  await expect(page.locator('#draft-error')).toBeVisible();
  await expect(page.locator('#escape-unacceptable')).toBeDisabled();
  let latest = await (await page.request.get(`${new URL(page.url()).pathname}/export.json`)).json();
  expect(latest.answers).toHaveLength(0);
  originally.after.used_amount = 98;
  await output.fill(JSON.stringify(originally));
  await expect(page.locator('#escape-unacceptable')).toBeEnabled();
  await page.locator('#escape-unacceptable').click();
  await expect(page.locator('#latest-answer')).toContainText('unacceptable');
  latest = await (await page.request.get(`${new URL(page.url()).pathname}/export.json`)).json();
  expect(latest.pinned_probes[0].witness.output.after.used_amount).toBe(98);
});

test('P06 and P07 have null follow-on and a Spec-invalid candidate remains evaluable', async ({page}) => {
  for (const id of ['P06','P07']) {
    await newReview(page,id);
    await expect(page.locator('#no-follow-on')).toBeVisible();
    await expect(page.locator('#candidate-ok')).toBeVisible();
    const record = await (await page.request.get(`${new URL(page.url()).pathname}/export.json`)).json();
    expect(record.seed_id).toBe(id);
    await expect(page.locator('#escape-unacceptable')).toBeEnabled();
  }
});

test('read, trace and a critical deferral stay human-owned and conclude only by confirmation', async ({page}) => {
  await newReview(page,'P03');
  await page.locator('#card-reading').click();
  await expect(page.locator('#active-question')).toContainText('reading');
  await page.locator('#card-answer-form button[value="accurate"]').click();
  await expect(page.locator('#latest-answer')).toContainText('accurate');
  await page.locator('#card-trace').click();
  await page.locator('#card-answer-form button[value="sufficient_for_review"]').click();
  await page.locator('#card-escape').click();
  await page.locator('#escape-deferred').click();
  await expect(page.locator('#latest-answer')).not.toContainText('deferred'); // explicit reason required
  await page.locator('#escape-unacceptable').click();
  await expect(page.locator('#latest-answer')).toContainText('unacceptable');
  await page.locator('#finish_rationale').fill('Named human review, release guarantee remains under investigation');
  await page.locator('#confirm-finish').click();
  await expect(page.locator('#review-summary')).toContainText('needs_policy_or_evidence');
  await page.reload();
  await expect(page.locator('#review-summary')).toContainText('needs_policy_or_evidence');
});
