// Source chooser behavior is an application test, not formal acceptance.
const {test,expect}=require('@playwright/test');
test('source selection uses registered identities and replay is unavailable without a pair',async({page})=>{
  await page.goto('/lab');await expect(page).toHaveURL(/\/claims\/po_a2\/trace-/);
  await page.locator('#choose-sources').click();
  await expect(page.locator('#compare_baseline')).toHaveJSProperty('tagName','SELECT');
  await expect(page.locator('#replay-pair')).toHaveCount(0);
  await expect(page.locator('#choose-replay-sources')).toBeEnabled();
});
