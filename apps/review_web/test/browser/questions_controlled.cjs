const {test,expect}=require('@playwright/test');
const fs=require('node:fs'),path=require('node:path');
async function open(page){await page.goto('/claims/po_a2');await expect(page).toHaveURL(/trace-/);await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/)}
async function ask(page,text){await page.locator('#header-question-form input[type=text]').fill(text);await expect(page.locator('#question-sharing')).toHaveText('Shares case + source');await page.locator('#header-question-form').getByRole('button',{name:'Ask an assistant',exact:true}).click()}
async function send(page){await page.locator('#question-send').click()}

test('controlled completion, compact preview, durable history and earlier-case follow-up',async({page})=>{
 await open(page);const url=page.url();const start=await page.locator('#review-comparison').boundingBox();const revision=await page.locator('#trace-revision').getAttribute('data-revision');
 await ask(page,'Explain this capacity boundary');await expect(page.locator('#question-answer')).toContainText('Controlled fixture:');await expect(page.locator('#question-history-list')).toHaveCount(0);
 const after=await page.locator('#review-comparison').boundingBox();expect(after).toEqual(start);await expect(page.locator('#trace-revision')).toHaveAttribute('data-revision',revision);
 const href=await page.getByRole('link',{name:'Export this question'}).getAttribute('href');const row=JSON.parse(decodeURIComponent(href.slice(href.indexOf(',')+1)));
 expect(row.packet.model).toBe('gpt-6.1-terra');expect(row.packet.effort).toBe('medium');expect(row.response_metadata.response_model).toBe('gpt-6.1-terra');expect(row.status).toBe('succeeded');
 const trace=new URL(url).pathname.split('/').at(-1),root=path.resolve(__dirname,'../../../..');const events=fs.readFileSync(path.join(root,'tmp/acceptance_0752/controlled-questions',trace,'events.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
 expect(events.map(e=>e.row.status)).toEqual(['prepared','running','succeeded']);expect(events[1].row.consent.packet_digest).toBe(row.packet.digest);expect(events[2].row.answer.summary).toContain('Controlled fixture:');
 const source=page.locator('.answer-sources a').first();const sourceResponse=await page.request.get(await source.getAttribute('href'));expect(sourceResponse.status()).toBe(200);
 await page.locator('#question-close').click();await expect(page.locator('#question-preview')).toContainText('Controlled fixture:');await expect(page.locator('#question-preview')).toBeFocused();await page.reload();await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);await page.locator('#question-history').click();await page.locator('#question-history-list').getByRole('button',{name:'Explain this capacity boundary',exact:true}).click();await expect(page.locator('#question-answer')).toContainText('Controlled fixture:');
 await page.locator('#question-close').click();await page.locator('#review-amount').fill('99');await page.locator('#question-history').click();await page.locator('#question-history-list').getByRole('button',{name:'Explain this capacity boundary',exact:true}).click();await expect(page.locator('#question-earlier')).toBeVisible();
 await page.getByRole('button',{name:'Ask a follow-up',exact:true}).click();await page.locator('#panel-question-form textarea').fill('Explain the earlier result again');await expect(page.locator('#question-consent')).toHaveCount(0);await send(page);await expect(page.locator('#question-answer')).toContainText('Controlled fixture:');await expect(page.locator('#question-earlier')).toBeVisible();await expect(page.locator('#review-amount')).toHaveValue('99');
 const followHref=await page.getByRole('link',{name:'Export this question'}).getAttribute('href');const follow=JSON.parse(decodeURIComponent(followHref.slice(followHref.indexOf(',')+1)));expect(follow.packet.context.case.event.amount).toBe(100);expect(follow.packet.context.prior_generated_answers[0].question).toBe('Explain this capacity boundary');
});

test('controlled unavailable and cancellation outcomes remain recallable without retry',async({page})=>{
 await open(page);await ask(page,'[fail] show unavailable');await expect(page.locator('#question-answer')).toContainText('controlled_unavailable');
 await page.getByRole('button',{name:'Ask using current case',exact:true}).click();await page.locator('#panel-question-form textarea').fill('[wait] cancel this request');await send(page);await expect(page.locator('#question-answer')).toContainText('Answering');await page.getByRole('button',{name:'Cancel',exact:true}).click();await expect(page.locator('#question-answer')).toContainText('cancelled');await expect(page.locator('#question-send')).toHaveCount(0);
});

test('clearing question history leaves the ledger review intact',async({page})=>{
 await open(page);const revision=await page.locator('#trace-revision').getAttribute('data-revision');await page.locator('#question-history').click();await page.getByRole('button',{name:'Clear history…',exact:true}).click();await page.getByRole('button',{name:'Keep history',exact:true}).click();await expect(page.getByRole('button',{name:'Delete question history',exact:true})).toHaveCount(0);
 await page.getByRole('button',{name:'Clear history…',exact:true}).click();await page.getByRole('button',{name:'Delete question history',exact:true}).click();await expect(page.locator('#trace-revision')).toHaveAttribute('data-revision',revision);await page.locator('#question-close').click();await page.locator('#question-history').click();await expect(page.locator('#question-history-list li')).toHaveCount(0);
});

test('mobile composer sends once without preparation or a permission checkbox',async({page})=>{
 await page.setViewportSize({width:390,height:844});await open(page);
 await page.locator('.question-mobile-open').click();await page.locator('#panel-question-form textarea').fill('Explain the money meter');
 await expect(page.locator('#panel-question-form')).toContainText('Sends this question, case and included source to Codex.');
 await expect(page.getByRole('button',{name:'Prepare question',exact:true})).toHaveCount(0);
 await expect(page.locator('#question-consent')).toHaveCount(0);
 await send(page);await expect(page.locator('#question-answer')).toContainText('Controlled fixture:');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
});

for(const slug of ['po_b2','po_b3'])test(`large proof context can be submitted for ${slug}`,async({page})=>{
 await page.goto(`/claims/${slug}`);await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
 await ask(page,'Explain this rule and state what proof text is omitted');
 await expect(page.locator('#question-answer')).toContainText('Controlled fixture:');
 await expect(page.locator('#question-context')).toContainText('later proof lines are omitted');
 const href=await page.getByRole('link',{name:'Export this question'}).getAttribute('href');const row=JSON.parse(decodeURIComponent(href.slice(href.indexOf(',')+1)));
 expect(row.packet.context.sources.some(s=>s.truncated)).toBe(true);expect(row.status).toBe('succeeded');
});

test('blank questions and stale case forms show the rejection cause without dispatch',async({page})=>{
 await open(page);await page.locator('#header-question-form').getByRole('button',{name:'Ask an assistant',exact:true}).click();
 await expect(page.locator('#question-panel [role=alert]')).toHaveText('Enter a question before sending.');
 await page.locator('#question-close').click();
 const before=await page.locator('#header-question-form input[type=hidden]').inputValue();
 await page.locator('#header-question-form input[type=text]').fill('Explain the changed case');await page.locator('#review-amount').fill('99');
 await expect(page.locator('#header-question-form input[type=hidden]')).not.toHaveValue(before);
 await page.locator('#header-question-form input[type=hidden]').evaluate((e,value)=>{e.value=value},before);
 await page.locator('#header-question-form').getByRole('button',{name:'Ask an assistant',exact:true}).click();
 await expect(page.locator('#question-panel [role=alert]')).toContainText('case changed');
 await expect(page.locator('#question-answer')).toHaveCount(0);
 await page.locator('#question-close').click();await page.locator('#question-history').click();
 await expect(page.locator('#question-history-list')).not.toContainText('Explain the changed case');
});
