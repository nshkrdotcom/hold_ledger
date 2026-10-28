const {test,expect}=require('@playwright/test');
async function open(page,slug='po_exposure_retain') {
  await page.goto('/claims/'+slug);await expect(page).toHaveURL(new RegExp('/claims/'+slug+'/trace-'));
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);await expect(page.locator('#visual-lab')).toBeVisible();
}
test('visual landing exposes contrast before source machinery',async({page})=>{
  await open(page);await expect(page.locator('#visual-after')).toContainText('voided');await expect(page.locator('#visual-verdicts')).toContainText('Rejects');
  await expect(page.locator('#technical-inspector')).not.toHaveAttribute('open');await expect(page.locator('#illustrated-infoview')).toContainText('valid : Spec.valid?');
});
test('hover, keyboard focus and pin connect clauses to actual capacity',async({page})=>{
  await open(page,'po_a2');const clause=page.locator('.expression-leaf').filter({hasText:'amount <= amount_limit - used_amount'}).first();
  await clause.hover();await expect(page.locator('#visual-before [data-link-target="capacity"]')).toHaveClass(/linked-value/);
  await clause.focus();await page.keyboard.press('Enter');await expect(clause).toHaveAttribute('aria-pressed','true');
  await page.locator('.scene-caption').hover();await expect(page.locator('#visual-before [data-link-target="capacity"]')).toHaveClass(/linked-value/);
  await clause.click();await page.locator('#visual-lab').dispatchEvent('pointerleave');await expect(clause).toHaveAttribute('aria-pressed','false');
});
test('dial changes actual clauses and only explicit add writes a branch',async({page})=>{
  await open(page,'po_a2');const count=await page.locator('#visual-timeline button').count();
  await page.getByRole('button',{name:'Above',exact:true}).click();await expect(page.locator('#visual-amount')).toHaveValue('101');await expect(page.locator('#visual-domain-silence')).toBeVisible();
  expect(await page.locator('#visual-timeline button').count()).toBe(count);
  await page.getByRole('button',{name:'Exact fit',exact:true}).click();await expect(page.locator('#visual-amount')).toHaveValue('100');await expect(page.locator('#visual-domain-silence')).toHaveCount(0);
  await page.locator('#visual-amount').fill('99');await expect(page.locator('.expression-leaf').filter({hasText:'amount <= amount_limit - used_amount'})).toContainText('99 → 100');
  await page.getByRole('button',{name:'Add to trace',exact:true}).click();await expect(page.locator('#visual-timeline button')).toHaveCount(count+1);
});
test('fencing fault resurrects remote exposure while local stays zero',async({page})=>{
  await open(page);await page.locator('#fencing-toggle').click();await expect(page.locator('#fencing-toggle')).toHaveAttribute('aria-checked','false');await page.locator('#show-delayed').click();
  await expect(page.locator('#sandbox-local')).toHaveText('0¢');await expect(page.locator('#sandbox-remote')).toHaveText('100¢');await expect(page.locator('#sandbox-coverage')).toContainText('Uncovered authorization');await expect(page.locator('#sandbox-provenance')).toContainText('counterfactual illustration');
  await page.locator('#fencing-toggle').click();await page.locator('#show-delayed').click();await expect(page.locator('#sandbox-remote')).toHaveText('0¢');await expect(page.locator('#sandbox-coverage')).toContainText('Covered');
});
test('durability fault and keyboard scrubbing show lost local coverage',async({page})=>{
  await open(page);await page.locator('#durability-toggle').click();await page.locator('#environment-position').fill('4');
  await expect(page.locator('.theater-event')).toContainText('Lose unsynced local state');await expect(page.locator('#sandbox-local')).toHaveText('0¢');await expect(page.locator('#sandbox-remote')).toHaveText('100¢');
  await page.locator('#environment-position').focus();await page.keyboard.press('Home');await expect(page.locator('#sandbox-coverage')).toContainText('Covered');
});
test('proof playback advances facts and pauses; reduced motion keeps manual steps',async({page})=>{
  await open(page);const player=page.locator('#proof-player');await player.locator('[data-play="proof"]').click();await expect(page.locator('#visual-lab')).toHaveAttribute('data-stage','1');
  await player.locator('[data-play="proof"]').click();await expect(player.locator('[data-play="proof"]')).toHaveAttribute('aria-pressed','false');await expect(page.locator('#illustrated-infoview')).toContainText('found : lookup');
  await page.emulateMedia({reducedMotion:'reduce'});await player.locator('[data-step="proof:1"]').click();await expect(page.locator('#visual-lab')).toHaveAttribute('data-stage','2');await expect(page.locator('.provenance-note').first()).toContainText('not captured Lean tactic states');
});
test('assumption playback pauses and accepts manual advancement',async({page})=>{
  await open(page);const play=page.locator('#environment-player [data-play="environment"]');await play.click();await expect(page.locator('#visual-lab')).toHaveAttribute('data-environment-position','1');await play.click();await expect(play).toHaveAttribute('aria-pressed','false');
  await page.locator('#environment-player [data-step="environment:1"]').click();await expect(page.locator('#visual-lab')).toHaveAttribute('data-environment-position','2');
});
test('bounded candidate discovery reports seed, cost and actual rejection',async({page})=>{
  await open(page);await page.locator('#hunt-candidate').click();await expect(page.locator('#hunt-status')).toContainText('found');await expect(page.locator('#hunt-status')).toContainText('seed 71');await expect(page.locator('#visual-verdicts')).toContainText('Rejects');await expect(page.locator('#visual-timeline button')).toHaveCount(2);
});
test('mobile fits and advanced editing remains open across actions',async({page})=>{
  await page.setViewportSize({width:390,height:844});await open(page);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.getByRole('button',{name:'Build an output ↗',exact:true}).click();await expect(page.locator('#technical-inspector')).toHaveAttribute('open');await expect(page.locator('#candidate-form')).toBeVisible();await page.locator('#recalculate').click();await expect(page.locator('#candidate-form')).toBeVisible();
});
test('source helper definitions expand inside the linked expression tree',async({page})=>{
  await open(page);const summary=page.locator('.expression-expansion > summary').first();await summary.click();
  await expect(page.locator('.expression-expansion[open]').first()).toContainText('valid?');
  await expect(page.locator('.expression-expansion[open] .expression-leaf').first()).toBeVisible();
});
