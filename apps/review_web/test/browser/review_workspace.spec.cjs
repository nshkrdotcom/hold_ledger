const {test,expect}=require('@playwright/test');
async function open(page,slug='po_a2') {
 await page.goto('/claims/'+slug);await expect(page).toHaveURL(new RegExp('/claims/'+slug+'/trace-'));
 await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
}
async function tab(page,name){if(['proof','premises','record'].includes(name))await page.locator('#inspector-tools [phx-value-view="'+name+'"]').click()}
test('review opens with the change, separate questions and scoped actions',async({page})=>{
 await open(page);for(const id of ['contract-diff','boundary-fork','decision-docket','timeline'])await expect(page.locator('#'+id)).toBeVisible();
 await expect(page.locator('#example-provenance')).toContainText('Example');
 await expect(page.locator('#contract-diff')).toContainText('amount <');
 await expect(page.locator('#coverage-proposal')).toHaveText('No');
 await expect(page.locator('#ledger-output')).toContainText('admitted');
 await expect(page.locator('#technical-inspector, #proof-player, #visual-timeline')).toHaveCount(0);
});
test('99/100/101 are scratch cases until explicitly appended',async({page})=>{
 await open(page);const count=await page.locator('#timeline button').count();
 for(const [name,amount,base,prop] of [['Below','99','Yes','Yes'],['Exact fit','100','Yes','No'],['Above','101','No','No']]){
  await page.getByRole('button',{name,exact:true}).click();await expect(page.locator('#review-amount')).toHaveValue(amount);
  await expect(page.locator('#coverage-baseline')).toHaveText(base);await expect(page.locator('#coverage-proposal')).toHaveText(prop);
  await expect(page.locator('#timeline button')).toHaveCount(count);
 }
 await page.locator('#append-preview').click();await expect(page.locator('#timeline button')).toHaveCount(count+1);
});
test('example repair action records scope and preserves the scratch case',async({page})=>{
 await open(page);await page.locator('#review-amount').fill('99');await expect(page.locator('#scratch-status')).toBeVisible();
 await page.locator('#request-repair').click();await expect(page.locator('#review-amount')).toHaveValue('99');
 await expect(page.locator('#decision-docket')).toContainText('Local concern');
 await tab(page,'record');await expect(page.locator('#review-history')).toContainText('99');
});
test('premise comparison uses the selected entry and does not write a trace',async({page})=>{
 await open(page,'po_exposure_retain');const count=await page.locator('#timeline button').count();await tab(page,'premises');await expect(page.locator('#premises-panel > summary')).not.toHaveAttribute('tabindex','-1');
 await page.locator('#fencing-toggle').click();await expect(page.locator('#premise-local')).toHaveText('0¢');await expect(page.locator('#premise-remote')).toHaveText('100¢');await expect(page.locator('#premise-covered')).toHaveText('No');
 await page.locator('#fencing-toggle').click();await expect(page.locator('#premise-remote')).toHaveText('0¢');await expect(page.locator('#timeline button')).toHaveCount(count);
});
test('clauses display boolean structure and actual operands',async({page})=>{
 await open(page);await tab(page,'clauses');await expect(page.locator('.logic-group').first()).toContainText('AND');await expect(page.locator('.inline-values').filter({hasText:'100 ≤ 100'}).first()).toBeVisible();
});
test('non-request controls keep a stable input strip',async({page})=>{
 await open(page,'po_exposure_retain');await expect(page.locator('#review-amount')).toBeVisible();await expect(page.locator('#review-amount')).toBeDisabled();await page.locator('#record-event').click();await expect(page.locator('#event-builder')).toBeVisible();
});

test('one active transient context drives account, candidate and visible verdict',async({page})=>{
 await open(page);await page.locator('#review-amount').fill('99');await expect(page.locator('#transient-branch')).toContainText('99');
 await expect(page.locator('#ledger-output')).toContainText('99¢ reserved');await expect(page.locator('#hypothetical-output')).toBeVisible();await expect(page.locator('#verdict')).toBeVisible();
 await page.locator('#edit-candidate').click();await page.getByRole('button',{name:'Use Ledger output',exact:true}).click();await page.getByRole('button',{name:'Zero counters',exact:true}).click();await expect(page.locator('#validity-row td').last()).toHaveText('false');
 await page.locator('#close-tools').click();await tab(page,'record');await page.locator('#note_text').fill('Keep the inconsistent counter challenge.');await page.locator('#note-form button').click();await expect(page.locator('#review-amount')).toHaveValue('99');await expect(page.locator('#validity-row td').last()).toHaveText('false');await page.locator('#hypothetical-output .status-pill').first().click();await expect(page.locator('#hypothetical-output')).toContainText('0¢ reserved');
 await page.locator('[phx-click=discard_preview]').click();await expect(page.locator('#transient-branch')).toHaveCount(0);await expect(page.locator('#ledger-output')).toContainText('100¢ reserved');
});
test('recording requires an explicit scratch save and drawer traps and restores focus',async({page})=>{
 await open(page);await page.locator('#review-amount').fill('99');await expect(page.locator('#ledger-output')).toContainText('99¢');
 await page.locator('#record-event').click();await expect(page.locator('#apply-event')).toBeDisabled();await expect(page.locator('#timeline button')).toHaveCount(2);
 await expect(page.locator('#close-tools')).toBeFocused();await page.keyboard.press('Shift+Tab');await expect(page.locator('#coupled-model')).toBeFocused();await page.keyboard.press('Tab');await expect(page.locator('#close-tools')).toBeFocused();
 await page.keyboard.press('Escape');await expect(page.locator('#tool-drawer')).toHaveCount(0);await expect(page.locator('#record-event')).toBeFocused();
 await page.locator('#append-preview').click();await page.locator('#record-event').click();await page.locator('#event_type').selectOption('dispatch');await page.locator('#event_key').fill('11');await page.locator('#apply-event').click();await page.locator('#close-tools').click();
 await expect(page.locator('#ledger-output')).toContainText('sent');await expect(page.locator('#ledger-output')).toContainText('99¢');await expect(page.locator('#timeline button')).toHaveCount(4);
});
test('proof references inspect inline while the case and verdict remain present',async({page})=>{
 await open(page,'po_exposure_retain');await page.locator('#lemma-links button').first().click();await expect(page.locator('#inline-source pre')).toContainText('theorem');await expect(page.locator('#proof-script')).toBeVisible();await expect(page.locator('#ledger-output')).toHaveCount(1);await expect(page.locator('#verdict')).toHaveCount(1);await page.locator('#inline-source button').click();await expect(page.locator('#goal-state-status')).toContainText('unavailable');
});
test('premises offer a worked case instead of an unactionable empty result',async({page})=>{
 await open(page);await tab(page,'premises');await page.locator('#open-premise-case').click();await expect(page).toHaveURL(/po_exposure_retain/);await tab(page,'premises');await expect(page.locator('#premise-selector')).toBeVisible();await expect(page.locator('#fencing-toggle')).toBeVisible();
});

for(const [width,height] of [[1280,720],[1440,900],[390,844]])test(`natural review flow at ${width}×${height}`,async({page})=>{
 await page.setViewportSize({width,height});await open(page);
 await expect(page.locator('#policy-anchor')).toContainText('An exact amount fit is admitted');
 await expect(page.locator('#request-repair')).toBeInViewport();
 const layout=await page.evaluate(()=>{
  const selectors=['#contract-diff','#active-case','#case-findings','#proof-panel'];
  return {positions:selectors.map(s=>document.querySelector(s).getBoundingClientRect().top+scrollY),overflow:[...document.querySelectorAll('#review-document section,#review-document aside')].filter(el=>['auto','scroll'].includes(getComputedStyle(el).overflowY)&&el.scrollHeight>el.clientHeight+1).map(el=>el.id),width:document.documentElement.scrollWidth};
 });
 expect(layout.overflow).toEqual([]);expect(layout.width).toBeLessThanOrEqual(width);expect(layout.positions[0]).toBeLessThan(layout.positions[1]);expect(layout.positions[3]).toBeGreaterThan(layout.positions[1]);
 await expect(page.locator('#boundary-fork table')).toHaveCount(0);await expect(page.locator('#contrast-matrix')).toHaveCount(1);await expect(page.locator('[phx-click=quick_event]')).toHaveCount(0);
 await page.locator('#request-repair').click();await expect(page.locator('#request-repair')).toBeInViewport();
});

test('eight entries, eight bindings and a nonempty effect remain inspectable',async({page})=>{
 await open(page,'po_exposure_retain');await page.locator('#edit-start').click();
 await page.locator('#initial_amount_limit').fill('1000');await page.locator('#initial_hold_limit').fill('8');
 for(let n=0;n<8;n++){
  if(n)await page.getByRole('button',{name:'Add entry',exact:true}).click();
  await page.locator(`[name="initial[entries][${n}][key]"]`).fill(String(n+1));
  await page.locator(`[name="initial[entries][${n}][amount]"]`).fill('37');
  await page.locator(`[name="initial[entries][${n}][status]"]`).selectOption('authorized');
 }
 await page.getByRole('button',{name:'Recalculate totals',exact:true}).click();
 await expect(page.locator('#initial_used_amount')).toHaveValue('296');await page.locator('#save-starting').click();
 await expect(page.locator('#tool-drawer')).toHaveCount(0);await page.locator('#record-event').click();
 await page.locator('#event_type').selectOption('void');await page.locator('#event_key').fill('1');await page.locator('#apply-event').click();await page.locator('#close-tools').click();
 await expect(page.locator('#entries tbody tr')).toHaveCount(8);await expect(page.locator('#ledger-output')).toContainText('296¢ reserved');await expect(page.locator('#ledger-output')).toContainText('Effects: void(1)');
 await expect(page.locator('#binding-count')).toContainText('8 source-derived bindings');await page.locator('#binding-choice select').selectOption('7');
 await expect(page.locator('#binding-7')).toBeVisible();await expect(page.locator('#binding-0')).toHaveCount(0);
 await expect(page.locator('#binding-7 .binding-values')).toContainText('8');expect(await page.locator('#proof-script > div').count()).toBeGreaterThan(40);
 await page.screenshot({path:'../../../../tmp/review_workspace_0708/eight-entry-case.png',fullPage:true});
});

test('temporary tools own scrolling while the review document is locked',async({page})=>{
 await open(page);await page.locator('#edit-candidate').click();
 await expect(page.locator('body')).toHaveCSS('overflow','hidden');
 await page.keyboard.press('Escape');await expect(page.locator('body')).not.toHaveCSS('overflow','hidden');
 await expect(page.locator('#edit-candidate')).toBeFocused();
});
