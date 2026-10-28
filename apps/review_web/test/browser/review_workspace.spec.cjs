const {test,expect}=require('@playwright/test');
async function open(page,slug='po_a2') {
 await page.goto('/claims/'+slug);await expect(page).toHaveURL(new RegExp('/claims/'+slug+'/trace-'));
 await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
}
async function tab(page,name){await page.locator('#workspace-tabs [phx-value-view="'+name+'"]').click()}
test('review opens with the change, separate questions and scoped actions',async({page})=>{
 await open(page);for(const id of ['contract-diff','boundary-fork','decision-docket','timeline'])await expect(page.locator('#'+id)).toBeVisible();
 await expect(page.locator('#example-provenance')).toContainText('Example');
 await expect(page.locator('#contract-diff')).toContainText('amount <');
 await expect(page.locator('#coverage-row td').last()).toHaveText('No');
 await expect(page.locator('#execution-row')).toContainText('admitted');
 await expect(page.locator('#technical-inspector, #proof-player, #visual-timeline')).toHaveCount(0);
});
test('99/100/101 are scratch cases until explicitly appended',async({page})=>{
 await open(page);const count=await page.locator('#timeline button').count();
 for(const [name,amount,base,prop] of [['Below','99','Yes','Yes'],['Exact fit','100','Yes','No'],['Above','101','No','No']]){
  await page.getByRole('button',{name,exact:true}).click();await expect(page.locator('#review-amount')).toHaveValue(amount);
  await expect(page.locator('#coverage-row td').first()).toHaveText(base);await expect(page.locator('#coverage-row td').last()).toHaveText(prop);
  await expect(page.locator('#timeline button')).toHaveCount(count);
 }
 await page.locator('#append-preview').click();await expect(page.locator('#timeline button')).toHaveCount(count+1);
});
test('example repair action records scope and preserves the scratch case',async({page})=>{
 await open(page);await page.locator('#review-amount').fill('99');await expect(page.locator('#scratch-status')).toBeVisible();
 await page.locator('#request-repair').click();await expect(page.locator('#review-amount')).toHaveValue('99');
 await expect(page.locator('#decision-docket')).toContainText('Example review');
 await tab(page,'record');await expect(page.locator('#session-record')).toContainText('99');
});
test('premise comparison uses the selected entry and does not write a trace',async({page})=>{
 await open(page,'po_exposure_retain');const count=await page.locator('#timeline button').count();await tab(page,'premises');
 await page.locator('#fencing-toggle').click();await expect(page.locator('#premise-local')).toHaveText('0¢');await expect(page.locator('#premise-remote')).toHaveText('100¢');await expect(page.locator('#premise-covered')).toHaveText('No');
 await page.locator('#fencing-toggle').click();await expect(page.locator('#premise-remote')).toHaveText('0¢');await expect(page.locator('#timeline button')).toHaveCount(count);
});
test('clauses display boolean structure and actual operands',async({page})=>{
 await open(page);await tab(page,'clauses');await expect(page.locator('.logic-group').first()).toContainText('AND');await expect(page.locator('.inline-values').filter({hasText:'100 ≤ 100'}).first()).toBeVisible();
});
test('non-request controls keep a stable input strip',async({page})=>{
 await open(page,'po_exposure_retain');await expect(page.locator('#review-amount')).toBeVisible();await expect(page.locator('#review-amount')).toBeDisabled();await expect(page.locator('#event_amount')).toBeVisible();
});
