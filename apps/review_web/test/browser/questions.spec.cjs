const {test,expect}=require('@playwright/test');
async function open(page){await page.goto('/claims/po_a2');await expect(page).toHaveURL(/trace-/);await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/)}
async function geometry(page){return page.evaluate(()=>({header:document.querySelector('.site-header').getBoundingClientRect().height,rule:document.querySelector('#review-comparison').getBoundingClientRect().top,input:document.querySelector('#selected-input').getBoundingClientRect().top,scroll:scrollY,width:document.documentElement.scrollWidth}))}

test('typing and inspecting context stay local and never move the case',async({page})=>{
 await open(page);const before=await geometry(page);
 await page.locator('#header-question-form input[type=text]').fill('Why does this rule reject the alternative?');await page.locator('#question-sharing').click();
 await expect(page.locator('#question-panel')).toBeVisible();await expect(page.locator('#question-consent')).toHaveCount(0);await expect(page.locator('#question-send')).toBeEnabled();
 await expect(page.locator('#question-context')).toContainText('gpt-6.1-terra');await expect(page.locator('#question-context')).toContainText('lib/hold_ledger/spec.ex');
 expect(await geometry(page)).toEqual(before);
 await expect(page.locator('[inert],[role=dialog]:visible,.tool-backdrop')).toHaveCount(0);expect(await page.locator('body').evaluate(e=>getComputedStyle(e).overflow)).not.toBe('hidden');
 await page.locator('#question-close').click();await page.locator('#question-history').click();
 await expect(page.locator('#question-answer')).toHaveCount(0);await expect(page.locator('#question-history-list')).not.toContainText('Why does this rule');
 await page.locator('#question-close').click();await page.reload();await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);await expect(page.locator('#question-panel')).toHaveCount(0);
});

for(const width of [1280,390,640])test(`question overlay keyboard and reflow at ${width}`,async({page})=>{
 await page.setViewportSize({width,height:800});await open(page);const before=await geometry(page);if(width===390)await expect(page.locator('.brand')).toHaveAccessibleName('Hold Ledger, explore');
 if(width<=650)await page.locator('.question-mobile-open').click();else await page.locator('#question-history').click();
 await expect(page.locator('#question-panel')).toBeVisible();expect(await geometry(page)).toEqual(before);
 await page.locator('#question-close').focus();await page.keyboard.press('Escape');await expect(page.locator('#question-panel')).toHaveCount(0);
 await page.locator('#question-history').click();await page.getByRole('button',{name:'1¢ more',exact:true}).click();await expect(page.locator('#question-panel')).toHaveCount(0);await expect(page.locator('#review-amount')).toHaveValue('101');
 expect((await geometry(page)).width).toBeLessThanOrEqual(width);
});
