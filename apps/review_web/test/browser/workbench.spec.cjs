const fs = require('node:fs');
const path = require('node:path');
const evidenceDir = path.resolve(__dirname, '../../../../tmp/verification/gate-b/browser-records');
fs.mkdirSync(evidenceDir, {recursive:true});
async function record(page, name) {
  const response = await page.request.get(`${new URL(page.url()).pathname}/export.json`);
  expect(response.status()).toBe(200);
  const record = await response.json();
  fs.writeFileSync(path.join(evidenceDir, `${name}.json`), JSON.stringify(record, null, 2));
  return record;
}
const { test, expect } = require('@playwright/test');

async function newReview(page, seed) {
  await page.goto('/workbench');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
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
  await expect(page.locator('#workbench-top')).toContainText(seed);
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
}

test('source-linked reading, all registered source nodes, exports and repeat navigation', async ({page}) => {
  await newReview(page, 'P01');
  await expect(page.locator('#candidate-ok')).toBeVisible();
  await page.locator('#map-toggle').click();
  await expect(page.locator('#design-map')).toContainText('law.po_exposure_retain');
  await expect(page.locator('#design-map')).toContainText('Not a pointwise DSL probe');
  await page.locator('#source-toggle').click();
  await expect(page.locator('#source-panel')).toContainText('guides/specification.md');
  const fullSource = page.locator('#source-panel li').filter({hasText:'guides/specification.md'}).locator('a');
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
  await expect(page.locator('#flash-group [role=alert]').filter({hasText:'Add a reason'})).toBeVisible();
  await expect(page.locator('#latest-answer')).toHaveCount(0);
  await page.locator('#escape-unacceptable').click();
  await expect(page.locator('#latest-answer')).toContainText('unacceptable');
  await page.locator('#finish_rationale').fill('Named human review, release guarantee remains under investigation');
  await page.locator('#confirm-finish').click();
  await expect(page.locator('#review-summary')).toContainText('needs_policy_or_evidence');
  await page.reload();
  await expect(page.locator('#review-summary')).toContainText('needs_policy_or_evidence');
});


test('P01/P05 effect flip, P03 domain, and all exact graph source bytes', async ({page}) => {
  for (const [seed, effectLabel] of [['P01','Allows here'], ['P05','Catches']]) {
    await newReview(page,seed);
    await page.locator('#reveal-analysis').click();
    await expect(page.locator('#catcher-matrix tr').filter({hasText:'po_b3'})).toContainText(effectLabel);
    await expect(page.locator('#catcher-matrix tr').filter({hasText:'po_exposure_retain'})).toContainText('Catches');
  }
  await newReview(page,'P03');
  await page.locator('#reveal-analysis').click();
  await expect(page.locator('#catcher-matrix tr').filter({hasText:'po_b1_timeout'})).toContainText('Allows here');
  await expect(page.locator('#catcher-matrix tr').filter({hasText:'po_b2'})).toContainText("Doesn't apply");
  await page.locator('#map-toggle').click();
  await expect(page.locator('#design-map button[data-node-id]')).toHaveCount(49);
  const review = await record(page, 'all-sources');
  for (const source of review.graph_snapshot.excerpts) {
    const response = await page.request.get(`${new URL(page.url()).pathname}/source/${source.id}`);
    expect(response.status(), source.path).toBe(200);
    const bytes = await response.body();
    expect(bytes.equals(fs.readFileSync(path.resolve(__dirname,'../../../..',source.path))), source.path).toBe(true);
    expect(require('node:crypto').createHash('sha256').update(bytes).digest('hex')).toBe(source.sha256);
  }
  const lawButton = page.locator('#design-map button').filter({hasText:'law.po_exposure_retain'});
  await lawButton.click();
  await expect(page.locator('#selected-source')).toContainText('release_evidence?');
  await page.locator('#source-toggle').click();
  await page.locator('#source-panel button').filter({hasText:'lib/hold_ledger/spec.ex'}).click();
  await expect(page.locator('#selected-source')).toContainText('def release_evidence?');
  await expect(page.locator('#selected-source')).toContainText('void_confirmed');
});

test('P04 live eligibility at 99/100/101 and a truly immediate unblurred submit', async ({page}) => {
  await newReview(page,'P04');
  await page.locator('#reveal-analysis').click();
  const event = page.locator('#draft_event_json');
  const original = JSON.parse(await event.inputValue());
  for (const amount of [99,100,101]) {
    await event.fill(JSON.stringify({...original,amount}));
    await expect(page.locator('#diff-panel')).toContainText(`Spec.request_eligible? at this input: ${amount<=100}`);
    await expect(page.locator('#catcher-matrix tr').filter({hasText:'po_a2'})).toContainText(amount<=100?'Catches':"Doesn't apply");
  }
  const output = page.locator('#draft_output_json');
  const candidate = JSON.parse(await output.inputValue());
  candidate.after.used_amount = 97;
  // Dispatch submit synchronously in the same browser task, inside the debounce window.
  await output.evaluate((element, value) => {
    element.value = value;
    element.dispatchEvent(new Event('input',{bubbles:true}));
    document.querySelector('#candidate-form').requestSubmit(document.querySelector('#escape-unacceptable'));
  }, JSON.stringify(candidate));
  await expect(page.locator('#latest-answer')).toContainText('unacceptable');
  const saved = await record(page,'immediate-submit');
  expect(saved.pinned_probes[0].witness.output.after.used_amount).toBe(97);
  expect(saved.pinned_probes[0].witness.event.amount).toBe(101);
});

test('fast edits under latency preserve the final form and keyboard judgment on mobile', async ({page}) => {
  await page.setViewportSize({width:390,height:844});
  await page.goto('/');
  await expect(page.locator('#new-review-choices')).toBeVisible();
  await newReview(page,'P04');
  await page.evaluate(() => window.liveSocket.enableLatencySim(200));
  const output = page.locator('#draft_output_json');
  const candidate = JSON.parse(await output.inputValue());
  for (const amount of [96,95,94]) {
    candidate.after.used_amount = amount;
    await output.fill(JSON.stringify(candidate));
  }
  await page.locator('#escape-unacceptable').focus();
  await page.keyboard.press('Enter');
  await expect(page.locator('#latest-answer')).toContainText('unacceptable');
  await page.evaluate(() => window.liveSocket.disableLatencySim());
  const saved = await record(page,'mobile-keyboard');
  expect(saved.pinned_probes[0].witness.output.after.used_amount).toBe(94);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.screenshot({path:path.join(evidenceDir,'mobile.png'),fullPage:true});
  await page.reload();
  await expect(page.locator('#latest-answer')).toContainText('unacceptable');
});

test('five answer vocabularies, deferral and explicit confirmation preserve scoped history', async ({page}) => {
  await newReview(page,'P01');
  for (const [kind,choice] of [['reading','inaccurate'],['silence','should_cover'],['assumption','unknown'],['trace','gap_suspected']]) {
    await page.locator(`#card-${kind}`).click();
    await page.locator('#card-reason').fill(`Human source review: ${kind}`);
    await page.locator(`#card-answer-form button[value="${choice}"]`).click();
    await expect(page.locator('#latest-answer')).toContainText(choice);
  }
  await page.locator('#card-escape').click();
  await page.locator('#escape-reason').fill('Need independent terminal evidence');
  await page.locator('#escape-deferred').click();
  await expect(page.locator('#latest-answer')).toContainText('deferred');
  let saved = await record(page,'deferred-five-kinds');
  expect(saved.answers).toHaveLength(5);
  expect(saved.review_conclusion).toBe(null);
  await page.locator('#finish_rationale').fill('Scope retains unresolved external questions');
  await page.locator('#review-outcome').selectOption('meets_intent_in_reviewed_scope');
  await page.locator('#confirm-finish').click();
  await expect(page.locator('#flash-group [role=alert]').filter({hasText:'Resolve open questions and computed conflicts'})).toBeVisible();
  saved = await record(page,'blocked-positive');
  expect(saved.review_conclusion).toBe(null);
  await page.locator('#review-outcome').selectOption('needs_policy_or_evidence');
  await page.locator('#confirm-finish').click();
  await expect(page.locator('#review-summary')).toContainText('Human conclusion:');
  const concluded = await record(page,'confirmed-scope');
  expect(concluded.review_conclusion.unresolved_ids).toContain('core.p01.escape');
});

test('legacy workflows return 404 and a new scenario never inherits prior answers', async ({page}) => {
  for (const route of ['/review','/review/receipts/fake','/receipts']) {
    expect((await page.request.get(route)).status()).toBe(404);
  }
  await newReview(page,'P01');
  const first = new URL(page.url()).pathname;
  await page.locator('#escape-unacceptable').click();
  await expect(page.locator('#latest-answer')).toContainText('unacceptable');
  await newReview(page,'P04');
  const second = await record(page,'separate-scenario');
  expect(second.answers).toHaveLength(0);
  expect(second.core_cards.every(card => card.id.startsWith('core.p04.'))).toBe(true);
  await page.goto(first);
  await expect(page.locator('#latest-answer')).toContainText('unacceptable');
});

test('a drifted saved source identity is visibly read-only and cannot accept another answer', async ({page}) => {
  await newReview(page,'P01');
  await page.locator('#escape-unacceptable').click();
  await expect(page.locator('#latest-answer')).toContainText('unacceptable');
  const saved = await record(page,'before-hash-drift');
  // Only this test's freshly created document is altered; live checkout sources remain untouched.
  const file = path.resolve(__dirname, '../../../../tmp/review_studio/reviews', `${saved.id}.json`);
  const changed = {...saved, source:{...saved.source,evaluator_id:'0'.repeat(64)}};
  fs.writeFileSync(file,JSON.stringify(changed));
  await page.reload();
  await expect(page.getByRole('alert').filter({hasText:'code, rules or proof-report identity changed'})).toBeVisible();
  await expect(page.locator('#escape-unacceptable')).toBeDisabled();
  await expect(page.locator('#confirm-finish')).toBeDisabled();
  await expect(page.locator('#latest-answer')).toContainText('unacceptable');
  const after = await record(page,'hash-drift-read-only');
  expect(after.answers).toEqual(saved.answers);
  expect(after.pinned_probes).toEqual(saved.pinned_probes);
  expect(after.status).toBe('stale_read_only');
});


test('AI opt-in gate never sends source through a disabled workbench', async ({page}) => {
  await newReview(page, 'P01');
  await expect(page.locator('#ai-collaboration')).toBeVisible();
  await expect(page.locator('#ai-consent')).not.toBeChecked();
  for (const selector of ['#ai-deck', '#ai-challenge', '#ai-followup']) {
    await expect(page.locator(selector)).toBeDisabled();
  }
  await page.reload();
  await expect(page.locator('#ai-consent')).not.toBeChecked();
  const record = await (await page.request.get(`${new URL(page.url()).pathname}/export.json`)).json();
  expect(record.ai_jobs).toHaveLength(0);
  expect(record.answers).toHaveLength(0);
});

test('a first-time reviewer can use definitions, compare, reset and conclude', async ({page}) => {
  await page.goto('/workbench');
  await expect(page.locator('#new-review-choices button')).toHaveCount(8);
  await page.getByRole('link', {name:'Glossary', exact:true}).click();
  await expect(page.locator('#glossary')).toHaveAttribute('open', '');
  await expect(page.locator('#glossary-oracle')).toContainText('separately written');
  await newReview(page, 'P08');
  await expect(page.locator('#scenario-brief')).toContainText('Hold cancelled.');
  await expect(page.locator('.progress-count').first()).toContainText('0 of 3');
  await page.locator('#draft_output_json').fill('{');
  await expect(page.locator('#scenario-brief .scenario-facts')).toHaveCount(0);
  await page.locator('#reset-draft').click();
  await expect(page.locator('#scenario-brief .scenario-facts')).toBeVisible();
  const before = await record(page, 'reset-does-not-save');
  expect(before.answers).toHaveLength(0);
  expect(before.pinned_probes).toHaveLength(0);
  await page.locator('#escape-acceptable').click();
  for (const [kind, choice] of [['reading','accurate'], ['trace','sufficient_for_review']]) {
    await page.locator(`#card-${kind}`).click();
    await page.locator(`#card-answer-form button[value="${choice}"]`).click();
  }
  await expect(page.locator('.progress-count').first()).toContainText('3 of 3');
  await page.locator('#finish_rationale').fill('Local cancellation releases an undispatched reservation; this review covers that example.');
  await page.locator('#review-outcome').selectOption('needs_policy_or_evidence');
  await page.locator('#confirm-finish').click();
  await expect(page.locator('#review-summary')).toContainText('Human conclusion:');
});

test('the primer teaches the workflow and briefings keep rule results behind reveal', async ({page}) => {
  await page.goto('/workbench');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  const primer = page.locator('#review-primer');
  if (!(await primer.getAttribute('open') === '')) await primer.locator(':scope > summary').click();
  await expect(page.locator('#primer-people')).toContainText('This app never runs Lean');
  await expect(page.locator('#primer-self-check > details')).toHaveCount(5);
  await expect(page.locator('#new-review-choices button')).toHaveCount(8);
  await page.locator('a[href="#new-review-choices"]').click();
  await page.locator('#new-review-choices button[phx-value-seed="P08"]').click();
  await expect(page.locator('#scenario-briefing[open]')).toContainText('What the written policy says');
  await expect(page.locator('#step-coaching details[open]')).toContainText('Predict');
  await expect(page.locator('#catcher-matrix table')).toHaveCount(0);
  await expect(page.locator('#candidate-form')).toBeVisible();
});
