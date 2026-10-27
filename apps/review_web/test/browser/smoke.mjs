import {chromium} from 'playwright';
import assert from 'node:assert/strict';
const base = process.env.REVIEW_URL || 'http://localhost:4000';
const browser = await chromium.launch({headless: true});
const page = await browser.newPage();
const errors = [];
page.on('pageerror', error => errors.push(error.message));
try {
  await page.goto(`${base}/review`);
  await page.keyboard.press('Tab');
  assert.equal(await page.locator(':focus').textContent(), 'Skip to workspace');
  for (const [id,choice] of [['void_pending','retain'],['timeout_unknown','uncertain'],['exact_fit','admit']]) {
    await page.goto(`${base}/review/${id}`);
    await page.locator('[data-phx-main].phx-connected').waitFor();
    assert.equal(await page.locator('#actual-output').count(),0);
    await page.locator(`#predict-${choice}`).click();
    await page.locator('#actual-output').waitFor();
    await page.locator('#predicate-matrix').waitFor();
    if (id === 'void_pending') {
      await page.locator('#candidate-early_release_no_effect').click();
      await page.locator('#follow-event').click();
      await page.waitForFunction(() => document.querySelector('#follow-output')?.textContent.includes(':admitted'));
      await page.locator('#claim-retention').click();
      await page.waitForFunction(() => document.querySelector('#matrix-early_release_no_effect')?.textContent.includes('passes selected'));
      assert.match(await page.locator('#matrix-early_release_no_effect').textContent(),/passes selected/);
      await page.locator('#question-form textarea').fill('Why can validity permit release?');
      await page.locator('#ask-explainer').click();
      await page.waitForFunction(() => document.querySelector('#explanation-status')?.textContent.trim() === 'ready');
      await page.locator('#flag-explanation').click();
      await page.locator('#law-po_exposure_retain').click();
      await page.locator('.source-excerpt').waitFor();
      if (process.env.REVIEW_SCREENSHOT) await page.screenshot({path:process.env.REVIEW_SCREENSHOT,fullPage:true});
    }
    await page.setViewportSize({width:390,height:844});
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'mobile horizontal overflow');
    await page.setViewportSize({width:1440,height:1000});
  }
  await page.locator('#decision-form select').selectOption('insufficient_evidence');
  await page.locator('#record-review').click();
  await page.waitForURL(/\/review\/receipts\//);
  assert.match(await page.locator('#receipt-decision').textContent(),/insufficient_evidence/);
  assert.equal((await page.request.get(`${page.url()}/export`)).status(),200);
  assert.deepEqual(errors,[]);
  console.log('Chromium: all three offline cases, keyboard entry, mobile layout, explainer and receipt/export passed.');
} finally { await browser.close(); }
