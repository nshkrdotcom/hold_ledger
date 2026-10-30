const {test,expect}=require('@playwright/test');
for(const width of [1440,1280,1024,800,768,640,390])test(`rule controls align and remain usable at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});await page.goto('/claims/po_a2');await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
 if(width>=768){
  const summary=page.locator('#selected-claim > summary');
  const metrics=await summary.evaluate(node=>({height:node.getBoundingClientRect().height,lineHeight:parseFloat(getComputedStyle(node).lineHeight)}));
  expect(metrics.height).toBeLessThanOrEqual(metrics.lineHeight*2);
 }
 const select=page.locator('#law-picker select'),compare=page.locator('#choose-sources');
 const s=await select.boundingBox(),c=await compare.boundingBox(),title=await page.locator('.rule-identity').boundingBox();
 expect(Math.abs(s.height-c.height)).toBeLessThanOrEqual(1);
 if(width>480){expect(Math.abs(s.y-c.y)).toBeLessThanOrEqual(1);expect(s.x+s.width).toBeLessThanOrEqual(c.x-7)}
 // The selector fills the title column inside the redesigned card padding.
 else{expect(c.y).toBeGreaterThanOrEqual(s.y+s.height+7);expect(Math.abs(s.width-title.width)).toBeLessThanOrEqual(1)}
 if(width<=1000)expect(s.y).toBeGreaterThanOrEqual(title.y+title.height+7);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
 await select.selectOption('po_b1_void');await expect(page).toHaveURL(/\/claims\/po_b1_void\//);
 await compare.click();await expect(page.locator('.source-chooser')).toBeVisible();
 await page.screenshot({path:`../../../../tmp/acceptance_0755/controls-${width}.png`});
});
