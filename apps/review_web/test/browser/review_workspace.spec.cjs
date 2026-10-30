const {test,expect}=require('@playwright/test');
async function open(page,slug='po_a2') {
 await page.goto('/claims/'+slug);await expect(page).toHaveURL(new RegExp('/claims/'+slug+'/trace-'));
 await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
}
async function inspect(page,name){await page.locator('#inspector-tools [phx-value-view="'+name+'"]').click()}
async function run(page,type,key='11'){
 await page.locator('#record-event').click();await page.locator('#event_type').selectOption(type);await page.locator('#event_key').fill(key);await page.locator('#apply-event').click();await page.locator('#close-tools').click();
}
async function saved(page){const id=new URL(page.url()).pathname.split('/').at(-1);return (await (await page.request.get('/sessions/'+id+'/export')).json()).trace}

test('opens with the rule, proof and experiment instead of sign-off controls',async({page})=>{
 await open(page);await expect(page.locator('h1')).toHaveText('Admit a request that fits exactly');
 await expect(page.locator('#policy-anchor')).toContainText('all remaining capacity');await expect(page.locator('#proof-script')).toBeVisible();
 await expect(page.locator('#tool-drawer,[role=dialog]:visible,#review-document > details')).toHaveCount(0);await expect(page.locator('#decision-docket button')).toHaveCount(3);
 await expect(page.locator('#review-document')).not.toContainText('no policy approval');await expect(page.locator('#review-document')).not.toContainText('Exact-fit admission');
 await expect(page.locator('#ledger-output h3')).toHaveText('Code returned');await expect(page.locator('#hypothetical-output h3')).toHaveText('Proposed output · not run');
});

test('nearby amounts update coverage and output without saving a trace',async({page})=>{
 await open(page);const initial=await saved(page);
 for(const [name,amount,before,after] of [['1¢ less','99','Yes','Yes'],['All available','100','Yes','No'],['1¢ more','101','No','No']]){
  await page.getByRole('button',{name,exact:true}).click();await expect(page.locator('#review-amount')).toHaveValue(amount);
  await expect(page.locator('#coverage-baseline')).toHaveText(before);await expect(page.locator('#coverage-proposal')).toHaveText(after);
 }
 expect((await saved(page)).steps).toEqual(initial.steps);await page.locator('#append-preview').click();await expect(page.locator('#append-preview')).toBeDisabled();expect((await saved(page)).steps.length).toBe(initial.steps.length+1);
});

test('review notes follow analysis and preserve its active input',async({page})=>{
 await open(page);await page.locator('#review-amount').fill('99');await page.locator('#request-repair').click();await inspect(page,'record');
 await expect(page.locator('#review-amount')).toHaveValue('99');await expect(page.locator('#review-history')).toContainText('99');
 await expect(page.locator('#proof-script')).toBeVisible();
});

test('processor assumption experiment is separate from saved history',async({page})=>{
 await open(page,'po_exposure_retain');const initial=await saved(page);await inspect(page,'premises');
 await page.locator('#fencing-toggle').click();await expect(page.locator('#premise-local')).toHaveText('0¢');await expect(page.locator('#premise-remote')).toHaveText('100¢');await expect(page.locator('#premise-covered')).toHaveText('No');
 await page.locator('#fencing-toggle').click();await expect(page.locator('#premise-remote')).toHaveText('0¢');expect((await saved(page)).steps).toEqual(initial.steps);
});

test('original observed conditions show the operands used for this input',async({page})=>{
 await open(page);await expect(page.locator('#dissector .condition-group').first()).toBeVisible();await expect(page.locator('.condition-rows .inline-values').filter({hasText:'100 ≤ 100'}).first()).toBeVisible();await page.locator('#complete-tree-0-requires > summary').click();await page.locator('#tree-clause-0-requires-root > .logic-line > button[phx-click=helper]').click();await expect(page.locator('#helper-definition')).toBeVisible();
});

test('events without an amount retain the same input layout',async({page})=>{
 await open(page,'po_exposure_retain');await expect(page.locator('#review-amount')).toBeDisabled();await page.locator('#record-event').click();await expect(page.locator('#event-builder')).toBeVisible();await expect(page.locator('#apply-event')).toBeEnabled();
});

test('inline alternative edits and notes preserve live checks and the scratch input',async({page})=>{
 await open(page);await page.locator('#review-amount').fill('99');await page.locator('#edit-candidate').click();
 await page.getByRole('button',{name:'Reset to code result',exact:true}).click();await page.locator('#alternative-counter input').fill('0');
 await expect(page.locator('#validity-row td').last()).toHaveText('Accounting does not balance');await expect(page.locator('#ledger-output')).toContainText('99¢ reserved');
 await expect(page.locator('body')).not.toHaveCSS('overflow','hidden');expect(await page.locator('#review-document').evaluate(el=>el.inert)).toBe(false);
 await page.locator('#close-tools').click();await page.locator('#add-observation').click();await page.locator('#note_text').fill('Keep the inconsistent accounting example.');await page.locator('#note-form button').click();
 await expect(page.locator('#review-amount')).toHaveValue('99');await expect(page.locator('#validity-row td').last()).toHaveText('Accounting does not balance');await expect(page.locator('#hypothetical-output')).toContainText('0¢ reserved');
});

test('run through an unsaved request, dispatch and timeout, then save once',async({page})=>{
 await open(page);const initial=await saved(page);await page.locator('#review-amount').fill('99');
 await run(page,'dispatch');await expect(page.locator('#ledger-output')).toContainText('Authorization pending');await run(page,'timeout');await expect(page.locator('#ledger-output')).toContainText('Outcome unknown');
 expect((await saved(page)).steps).toEqual(initial.steps);await page.locator('#add-observation').click();await page.locator('#note_text').fill('Review the unsaved authorization.');await page.locator('#note-form button').click();await inspect(page,'record');await expect(page.locator('#review-history')).toContainText('Review the unsaved authorization.');expect((await saved(page)).steps).toEqual(initial.steps);await page.locator('#append-preview').click();await expect(page.locator('#append-preview')).toBeDisabled();
 const recorded=await saved(page);expect(recorded.steps.length).toBe(initial.steps.length+3);expect(recorded.steps.at(-1).before.used_amount).toBe(99);
 await page.locator('#timeline button').nth(1).click();await expect(page.locator('#ledger-output')).toContainText('100¢ reserved');
});

test('dependencies add their exact source while the proof stays available',async({page})=>{
 await open(page,'po_exposure_retain');await page.locator('#lemma-links button').first().click();await expect(page.locator('#inline-source pre')).toContainText('theorem');await expect(page.locator('#proof-script')).toBeVisible();
 await inspect(page,'artifacts');await expect(page.locator('#goal-state-status')).toContainText('unavailable');await expect(page.locator('#formal-status')).toHaveText('Not supplied');
});

test('a worked cancellation case is available when the current case has no eligible entry',async({page})=>{
 await open(page);await inspect(page,'premises');await page.locator('#open-premise-case').click();await expect(page).toHaveURL(/po_exposure_retain/);await inspect(page,'premises');await expect(page.locator('#premise-selector')).toBeVisible();
});

for(const [width,height] of [[1280,720],[1440,900],[390,844]])test(`correlated editing at ${width}×${height}`,async({page})=>{
 await page.setViewportSize({width,height});await open(page);
 const rule=await page.locator('#review-comparison').boundingBox(),checks=await page.locator('#case-findings').boundingBox(),proof=await page.locator('#proof-panel').boundingBox(),caseBox=await page.locator('.case-stage').boundingBox();
 expect(checks.y).toBeGreaterThan(rule.y);expect(proof.y).toBeGreaterThan(checks.y);
 if(width>=1120){expect(Math.abs(caseBox.y-checks.y)).toBeLessThan(30);expect(checks.x).toBeGreaterThan(caseBox.x)}
 else{expect(checks.y).toBeGreaterThan(caseBox.y)}
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.locator('#edit-candidate').click();await page.getByRole('button',{name:'Reset to code result',exact:true}).click();await page.locator('#alternative-counter input').fill('0');await expect(page.locator('#validity-row td').last()).toHaveText('Accounting does not balance');
 await expect(page.locator('#validity-row')).toHaveCount(1)
 await expect(page.locator('[inert],.tool-backdrop,[role=dialog]:visible')).toHaveCount(0);
 await page.screenshot({path:`../../../../tmp/review_workspace_0711/edit-${width}.png`,fullPage:true});
});

test('eight entries and their eight bindings remain inspectable without a giant proof dump',async({page})=>{
 await open(page,'po_exposure_retain');await page.locator('#edit-start').click();await page.locator('#initial_amount_limit').fill('1000');await page.locator('#initial_hold_limit').fill('8');
 for(let n=0;n<8;n++){
  if(n)await page.getByRole('button',{name:'Add entry',exact:true}).click();
  await page.locator(`[name="initial[entries][${n}][key]"]`).fill(String(n+1));await page.locator(`[name="initial[entries][${n}][amount]"]`).fill('37');await page.locator(`[name="initial[entries][${n}][status]"]`).selectOption('authorized');
 }
 await page.getByRole('button',{name:'Recalculate totals',exact:true}).click();await expect(page.locator('#initial_used_amount')).toHaveValue('296');await expect(page.locator('#initial_used_holds')).toHaveValue('8');await page.locator('#save-starting').click();await expect(page.locator('#case-tools')).toHaveCount(0);
 await run(page,'void','1');await expect(page.locator('#entries tbody tr')).toHaveCount(8);await expect(page.locator('#ledger-output')).toContainText('296¢ reserved');await expect(page.locator('#ledger-output .effect-list')).toContainText('Cancel hold 1');
 await expect(page.locator('#binding-count')).toContainText('8 combinations checked');await page.locator('#binding-choice select').selectOption('7');await expect(page.locator('#binding-7')).toBeVisible();await expect(page.locator('#binding-0')).toHaveCount(0);
 expect(await page.locator('#proof-script > div').count()).toBeLessThan(15);await page.locator('#full-proof').click();await expect.poll(()=>page.locator('#proof-script > div').count()).toBeGreaterThan(40);
});

test('keyboard can leave inline editing and still inspect the rule',async({page})=>{
 await open(page);await page.locator('#edit-candidate').click();await page.locator('#alternative-counter input').focus();await page.keyboard.press('Escape');await expect(page.locator('#case-tools')).toHaveCount(0);await expect(page.locator('#edit-candidate')).toBeFocused();
 await page.locator('#edit-candidate').click();await page.locator('#policy-source').click();await expect(page.locator('#inline-source')).toContainText('Specification');await expect(page.locator('#case-tools')).toBeVisible();
});
