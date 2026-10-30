const {test,expect}=require('@playwright/test');
for(const [width,height] of [[1440,900],[1280,800],[390,844]])test(`Guided follows the case in reading order at ${width}x${height}`,async({page})=>{
 await page.setViewportSize({width,height});await page.goto('/claims/po_a2');
 await expect(page).toHaveURL(/trace-/);await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
 await expect(page.locator('#review-document')).toHaveAttribute('data-case-view','guided');
 const geometry=await page.evaluate(()=>({orientation:document.querySelector('#case-review-map').getBoundingClientRect().bottom,experiment:document.querySelector('#case-experiment').getBoundingClientRect().bottom,checksTop:document.querySelector('#case-findings').getBoundingClientRect().top,width:document.documentElement.scrollWidth}));
 expect(geometry.orientation).toBeLessThan(geometry.experiment);expect(geometry.checksTop).toBeGreaterThan(geometry.experiment);expect(geometry.width).toBeLessThanOrEqual(width);
 await expect(page.locator('#case-conditions-depth')).toHaveJSProperty('open',false);
 for(const target of ['review-comparison','case-experiment','case-findings']){
  await page.locator(`#case-review-map a[href="#${target}"]`).click();await expect(page.locator('#'+target)).toBeFocused();
 }

 await page.getByRole('button',{name:'1¢ more',exact:true}).click();await expect(page.locator('#ledger-output')).toContainText('Not enough available money');await expect(page.locator('#applicability-row')).toContainText('Claim says nothing about this input');
 await page.getByRole('button',{name:'All available',exact:true}).click();await expect(page.locator('#ledger-output')).toContainText('Accepted');
 await page.locator('#inspector-tools [phx-value-view=clauses]').click();await expect(page.locator('#group-0-requires-eligibility')).toBeVisible();
 await page.screenshot({path:`../../../../tmp/acceptance_0752/cockpit-${width}.png`,fullPage:true});
});
