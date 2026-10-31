const {test,expect}=require('@playwright/test');
for(const [width,height] of [[1440,900],[1280,800],[390,844]])test(`Guided keeps the input and result connected at ${width}x${height}`,async({page})=>{
 await page.setViewportSize({width,height});await page.goto('/claims/po_a2');
 await expect(page).toHaveURL(/trace-/);await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
 await expect(page.locator('#review-document')).toHaveAttribute('data-case-view','guided');
 const geometry=await page.evaluate(()=>{const experiment=document.querySelector('#case-experiment').getBoundingClientRect(),checks=document.querySelector('#case-findings').getBoundingClientRect();return {orientation:document.querySelector('#case-review-map').getBoundingClientRect().bottom,experimentTop:experiment.top,experimentBottom:experiment.bottom,experimentLeft:experiment.left,checksTop:checks.top,checksLeft:checks.left,width:document.documentElement.scrollWidth}});
 expect(geometry.orientation).toBeLessThanOrEqual(geometry.experimentTop);
 if(width>=1160){expect(Math.abs(geometry.checksTop-geometry.experimentTop)).toBeLessThan(35);expect(geometry.checksLeft).toBeGreaterThan(geometry.experimentLeft)}
 else expect(geometry.checksTop).toBeGreaterThan(geometry.experimentBottom);
 expect(geometry.width).toBeLessThanOrEqual(width);
 await expect(page.locator('#case-conditions-depth')).toHaveJSProperty('open',false);
 for(const target of ['review-comparison','case-experiment','case-findings']){
  await page.locator(`#case-review-map a[href="#${target}"]`).click();await expect(page.locator('#'+target)).toBeFocused();
 }

 await page.getByRole('button',{name:'1¢ more',exact:true}).click();await expect(page.locator('#ledger-output')).toContainText('Not enough available capacity');await expect(page.locator('#applicability-row')).toContainText('Claim says nothing about this input');
 await page.getByRole('button',{name:'All available',exact:true}).click();await expect(page.locator('#ledger-output')).toContainText('Accepted');
 await page.locator('#inspector-tools [phx-value-view=clauses]').click();await expect(page.locator('#group-0-requires-eligibility')).toBeVisible();
 await page.screenshot({path:`../../../../tmp/acceptance_0752/cockpit-${width}.png`,fullPage:true});
});
