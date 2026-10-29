const {test,expect}=require('@playwright/test');
async function open(page,slug){await page.goto('/claims/'+slug);await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/)}
for(const width of [1280,390])test(`helper source controls reveal content and work repeatedly at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});await open(page,'l2_identity');
 const source=page.locator('#condition-source');await expect(source).toHaveJSProperty('open',true);
 await expect(page.locator('#conditions-requires')).toContainText('Spec.proper_entries?');await expect(page.locator('#conditions-requires')).toContainText('Spec.known_status?');await expect(page.locator('#conditions-expects')).toContainText('Ledger.set_status');
 await expect(page.locator('#condition-source-status')).toHaveText('Evaluation unavailable for this input.');await expect(page.locator('#binding-0')).toHaveCount(0);
 const count=await page.locator('#proof-script > div').count();
 await page.locator('#inspector-tools [phx-value-view=proof]').click();await expect(page.locator('#proof-script')).toHaveAttribute('data-source-view','full');expect(await page.locator('#proof-script > div').count()).toBeGreaterThan(count);await expect(page.locator('#proof-panel')).toBeFocused();
 const text=await page.locator('#proof-script code').allTextContents();await page.locator('#full-proof').click();await expect(page.locator('#proof-script')).toHaveAttribute('data-source-view','excerpt');await page.locator('#inspector-tools [phx-value-view=proof]').click();await expect(page.locator('#proof-script')).toHaveAttribute('data-source-view','full');expect(await page.locator('#proof-script code').allTextContents()).toEqual(text);
 await source.locator('summary').click();await expect(source).toHaveJSProperty('open',false);
 const conditions=page.locator('#inspector-tools [phx-value-view=clauses]');await conditions.focus();await page.keyboard.press('Enter');await expect(source).toHaveJSProperty('open',true);await expect(page.locator('#clauses-panel')).toBeFocused();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
 await page.screenshot({path:`../../../../tmp/acceptance_0757/helper-${width}.png`,fullPage:true});
});
test('Conditions opens source alongside real evaluated bindings',async({page})=>{
 await open(page,'po_a2');await page.locator('#inspector-tools [phx-value-view=clauses]').click();await expect(page.locator('#condition-source')).toHaveJSProperty('open',true);await expect(page.locator('#conditions-requires')).toContainText('request_eligible?');await expect(page.locator('#binding-0')).toBeVisible();await expect(page.locator('#condition-source-status')).toHaveCount(0);
});
test('native rule exposes every registered Lean statement and full declaration',async({page})=>{
 await open(page,'po_exposure_model');await expect(page.locator('#condition-source article')).toHaveCount(4);await page.locator('#inspector-tools [phx-value-view=proof]').click();await expect(page.locator('#proof-panel [data-declaration]')).toHaveCount(4);await expect(page.locator('#proof-panel')).toContainText('void_before_issue');
});
