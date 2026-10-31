const {test,expect}=require('@playwright/test');

test('helper law shows scope neutrally and keeps evidence navigation usable',async({page})=>{
 await page.goto('/claims/l2_identity');
 await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
 await expect(page.locator('#unavailable-binding')).toContainText('set_status/3');
 await expect(page.locator('#unavailable-binding')).toContainText('request IDs and amounts');
 await expect(page.locator('#dissector')).not.toContainText(':outside_initial_probe_scope');
 await expect(page.locator('#verdict')).not.toContainText(':outside_initial_probe_scope');
 await expect(page.locator('#selected-law-row')).toHaveClass('check-unavailable');
 await expect(page.locator('#selected-law-row')).toHaveCSS('background-color','rgba(0, 0, 0, 0)');
 const dock=page.getByRole('navigation',{name:'Evidence tools'});
 await expect(dock).toHaveCSS('border-top-style','solid');
 await dock.getByRole('button',{name:'Assumptions',exact:true}).click();
 await expect(page.locator('#premises-panel')).toBeVisible();
 await dock.getByRole('button',{name:'Proof',exact:true}).click();
 await expect(page.locator('#proof-source-workspace')).toBeVisible();
 await page.screenshot({path:'../../../../tmp/acceptance_0753/helper-law.png',fullPage:true});
});

for(const width of [1440,1280,1024,800,640,390])test(`header stays within viewport at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});
 await page.goto('/claims/po_a2');
 await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
 const brand=page.getByRole('link',{name:'Hold Ledger, explore',exact:true});
 const box=await brand.boundingBox();
 expect(box.x).toBeGreaterThanOrEqual(16);
 expect(box.x+box.width).toBeLessThanOrEqual(width-16);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
 if(width>650)await expect(brand.locator('.brand-name')).toBeVisible();
});
