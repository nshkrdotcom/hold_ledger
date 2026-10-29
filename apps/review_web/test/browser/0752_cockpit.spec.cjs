const {test,expect}=require('@playwright/test');
for(const [width,height] of [[1440,900],[1280,800]])test(`working loop fits ${width}x${height}`,async({page})=>{
 await page.setViewportSize({width,height});await page.goto('/claims/po_a2');
 await expect(page).toHaveURL(/trace-/);await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
 const geometry=await page.evaluate(()=>({header:document.querySelector('#review-comparison').getBoundingClientRect().height,outputs:document.querySelector('.output-pair').getBoundingClientRect().bottom,input:document.querySelector('#selected-input').getBoundingClientRect().bottom,check:document.querySelector('#active-predicate-result').getBoundingClientRect().bottom,gates:document.querySelector('#group-0-requires-eligibility').getBoundingClientRect().top,width:document.documentElement.scrollWidth}));
 expect(geometry.header).toBeLessThanOrEqual(125);expect(geometry.outputs).toBeLessThan(800);expect(geometry.input).toBeLessThan(500);expect(geometry.check).toBeLessThan(500);expect(geometry.width).toBeLessThanOrEqual(width);expect(geometry.gates).toBeLessThan(800);
 await page.getByRole('button',{name:'1¢ more',exact:true}).click();await expect(page.locator('#ledger-output')).toContainText('Not enough available money');await expect(page.locator('#applicability-row')).toContainText('Does not apply');
 await page.getByRole('button',{name:'All available',exact:true}).click();await expect(page.locator('#ledger-output')).toContainText('Accepted');await expect(page.locator('#group-0-requires-eligibility')).toBeVisible();
 await page.screenshot({path:`../../../../tmp/acceptance_0752/cockpit-${width}.png`,fullPage:true});
});
