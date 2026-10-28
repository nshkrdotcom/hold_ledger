const {test,expect}=require('@playwright/test');
async function open(page,slug='po_exposure_retain') {
  await page.goto('/claims/'+slug);
  await expect(page).toHaveURL(new RegExp('/claims/'+slug+'/trace-'));
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('#timeline')).toBeVisible();
  return page.url();
}
async function tab(page,name) {
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  if(['proof','premises','record'].includes(name))await page.locator('#inspector-tools [phx-value-view="'+name+'"]').click();
}
async function inspect(page) { await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/); }
async function event(page,type,key='2',amount='100') {
  await inspect(page);
  await page.locator('#record-event').click();
  const revision=await page.locator('#trace-revision').innerText();
  await page.locator('#event_type').selectOption(type);
  if(type!=='restart') await page.locator('#event_key').fill(key);
  if(type==='request') await page.locator('#event_amount').fill(amount);
  await page.locator('#apply-event').click();
  await expect(page.locator('#trace-revision')).not.toHaveText(revision);
  await page.locator('#close-tools').click();
}

test('early release: valid accounting is distinct from required retention',async({page})=>{
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  const url=await open(page);
  await tab(page,'outputs');
  await expect(page.locator('#ledger-output')).toContainText(/100¢ reserved[\s\S]*voiding/);
  await expect(page.locator('#hypothetical-output')).toContainText(/0¢ reserved[\s\S]*voided/);
  await expect(page.locator('#validity-row td').nth(1)).toHaveText('true');
  await expect(page.locator('#validity-row td').nth(2)).toHaveText('true');
  await expect(page.locator('#selected-law-row td').nth(2)).toHaveText('false');
  await tab(page,'clauses');
  await expect(page.locator('#dissector')).toContainText(':voided');
  await expect(page.locator('#dissector')).toContainText(':sent, :unknown, :authorized, :voiding');
  await page.reload();await tab(page,'outputs');await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  expect(new URL(page.url()).pathname).toBe(new URL(url).pathname);await expect(page.locator('#selected-law-row td').nth(2)).toHaveText('false');
  expect(errors).toEqual([]);
});

test('the same output passes validity; inspect its helper definition',async({page})=>{
  await open(page,'po_b1_void');await tab(page,'outputs');
  await expect(page.locator('#selected-law-row td').nth(2)).toHaveText('true');
  await tab(page,'clauses');
  await page.locator('#dissector').getByRole('button',{name:'Definition',exact:true}).first().click();
  await expect(page.locator('#helper-definition')).toContainText('Definition on these values');
  await page.locator('#helper-definition').getByRole('button',{name:'Close',exact:true}).click();
  await tab(page,'outputs');await page.locator('#edit-candidate').click();await page.locator('#inspect-retention').click();await page.locator('#close-tools').click();
  await expect(page.locator('#selected-law-row td').nth(2)).toHaveText('false');
});

test('99, 100 and 101 expose actual eligibility operands and outside-domain silence',async({page})=>{
  await open(page,'po_a2');
  for(const amount of ['99','100','101']) {
    await page.locator('#timeline button').first().click();
    await event(page,'request','11',amount);
    await tab(page,'clauses');
    const clause=page.locator('#dissector .logic-leaf').filter({hasText:'amount <= amount_limit - used_amount'});
    await expect(clause).toContainText(amount+' ≤ 100');
    await expect(clause).toContainText(amount==='101'?'false':'true');
    await tab(page,'outputs');
    if(amount==='101') {
      await expect(page.locator('#ledger-output')).toContainText('insufficient_amount');await tab(page,'clauses');
      await expect(page.locator('#outside-domain')).toBeVisible();
    } else await expect(page.locator('#ledger-output')).toContainText('admitted');
  }
  await expect(page.locator('#timeline button')).toHaveCount(4);
});

test('full actual proof source stays beside selected source stage',async({page})=>{
  await open(page);await tab(page,'proof');
  await expect(page.locator('#proof-source-workspace')).toContainText('po_exposure_retain');
  await page.locator('#proof-source-workspace .proof-source-stages button').last().click();
  await expect(page.locator('.active-proof-line').first()).toBeVisible();
  await expect(page.locator('.active-proof-line').first()).toBeInViewport();
  expect(await page.locator('#proof-script > div').count()).toBeGreaterThan(40);
  expect(await page.locator('#proof-script').evaluate(el=>el.scrollHeight<=el.clientHeight+1)).toBe(true);
  const link=page.locator('#lemma-links a').first();
  const response=await page.request.get(await link.getAttribute('href'));expect(response.status()).toBe(200);
  const stale=await page.request.get((await link.getAttribute('href')).replace(/[a-f0-9]{64}$/,'0'.repeat(64)));expect(stale.status()).toBe(404);
  await expect(page.locator('#formal-status')).toHaveText('not_supplied');
});

test('hypothetical early release changes the next request; actual branch is retained',async({page})=>{
  await open(page);await tab(page,'outputs');await page.locator('#edit-candidate').click();await page.locator('#branch-candidate').click();await page.locator('#close-tools').click();
  await expect(page.locator('#hypothetical-lineage')).toBeVisible();
  await event(page,'request');await expect(page.locator('#ledger-output')).toContainText('admitted');
  await expect(page.locator('#hypothetical-lineage')).toBeVisible();
  await page.locator('#timeline button').nth(1).click();
  await event(page,'request');await expect(page.locator('#ledger-output')).toContainText('insufficient_amount');
  await expect(page.locator('#hypothetical-lineage')).toHaveCount(0);
});

test('structured candidate and JSON round trip keep inconsistent totals until recalculation',async({page})=>{
  await open(page);await tab(page,'outputs');await page.locator('#edit-candidate').click();
  await page.locator('#advanced-editor').click();
  await page.locator('#output_used_amount').fill('50');
  await expect(page.locator('#validity-row td').nth(2)).toHaveText('false');
  await expect(page.locator('#branch-candidate')).toBeDisabled();
  await page.locator('#recalculate').click();await expect(page.locator('#output_used_amount')).toHaveValue('0');
  const candidate=JSON.parse(await page.locator('#candidate-json').inputValue());
  candidate.after.used_amount=99;
  await page.locator('#candidate-json').fill(JSON.stringify(candidate));
  await page.locator('#candidate-json-form button').click();
  await expect(page.locator('#output_used_amount')).toHaveValue('99');
  await expect(page.locator('#validity-row td').nth(2)).toHaveText('false');
  await page.locator('#candidate-json').fill('{broken');await page.locator('#candidate-json-form button').click();
  await expect(page.locator('#invalid-candidate')).toBeVisible();await expect(page.locator('#contrast-matrix')).toHaveCount(0);
});

test('adjusting initial state creates a separate session',async({page})=>{
  const old=await open(page,'po_a2');await page.locator('#timeline button').first().click();await expect(page.locator('#entries')).toContainText('No entries');await page.locator('#edit-start').click();
  await page.locator('#initial_amount_limit').fill('101');await page.locator('#save-starting').click();
  await expect(page).not.toHaveURL(old);
  await event(page,'request','11','101');await tab(page,'outputs');await expect(page.locator('#ledger-output')).toContainText('admitted');
  await page.goto(old);await expect(page.locator('#ledger-output')).toContainText('100¢ reserved');
});

test('timeline supports keyboard selection and preserves branches',async({page})=>{
  await open(page);await event(page,'request');
  await page.locator('#timeline button').first().focus();await page.keyboard.press('Enter');
  await expect(page.locator('#timeline button').first()).toHaveAttribute('aria-current','step');
  await page.locator('#timeline button').last().focus();await page.keyboard.press('Enter');
  await expect(page.locator('#ledger-output')).toContainText('insufficient_amount');
  await page.locator('#timeline button').nth(1).click();await expect(page.locator('#ledger-output')).toContainText('voiding');
  await expect(page.locator('#timeline button')).toHaveCount(3);
});

test('coupled model separates remote delivery, observation and terminal fencing',async({page})=>{
  await open(page);await page.locator('#record-event').click();await page.locator('#coupled-model').click();
  await expect(page).toHaveURL(/po_exposure_model/);
  await inspect(page);
  await expect(page.locator('#remote-state')).toBeVisible();
  for(const type of ['request','dispatch','authorize','timeout']) await event(page,type,'11');
  await expect(page.locator('#remote-state')).toContainText('unknown');await expect(page.locator('#remote-state')).toContainText('approved');
  await event(page,'observe','11');await expect(page.locator('#coupled-local-after')).toContainText('authorized');
  await event(page,'void','11');await event(page,'remote_void','11');
  await expect(page.locator('#amount-counter')).toHaveText('100¢ / 100¢');
  await event(page,'confirm','11');await event(page,'authorize','11');
  await expect(page.locator('#coupled-amount-counter')).toContainText('0¢ / 100¢');await expect(page.locator('#remote-state')).toContainText('voided');
  await tab(page,'clauses');await expect(page.locator('#dissector')).toContainText('Native Lean statement');
});

test('two tabs preserve CAS conflict and reconnect source identity',async({page,context})=>{
  const url=await open(page);const right=await context.newPage();await right.goto(url);
  await inspect(right);
  await expect(right.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await tab(page,'record');await tab(right,'record');
  await page.locator('#note_text').fill('Check actual processor evidence.');await page.locator('#note-form button').click();
  await right.locator('#note_text').fill('Stale reviewer edit.');await right.locator('#note-form button').click();
  await expect(right.locator('[role=alert]')).toContainText('Another tab');
  await right.reload();await tab(right,'record');await expect(right.locator('#review-history')).toContainText('Check actual processor evidence.');
  await right.evaluate(()=>window.liveSocket.disconnect());await right.evaluate(()=>window.liveSocket.connect());
  await expect(right.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(right.locator('#review-history')).toContainText('Check actual processor evidence.');
});

test('mobile stays within viewport and requests no provider',async({page})=>{
  const requests=[];page.on('request',r=>{if(!/^https?:\/\/(localhost|127\.0\.0\.1):4000\//.test(r.url()))requests.push(r.url())});
  await page.setViewportSize({width:390,height:844});await open(page);
  await expect(page.locator('#contract-diff')).toBeVisible();await expect(page.locator('#boundary-fork')).toBeVisible();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await expect(page.locator('#ai-consent, #review-primer, #glossary')).toHaveCount(0);expect(requests).toEqual([]);
});

test('generated Lean artifacts are readable when fresh and cannot become full acceptance',async({page})=>{
  await open(page);await tab(page,'proof');
  const status=await page.locator('#focused-status').innerText();
  if(status==='elaborated') {
    const links=page.locator('#generated-artifacts a');expect(await links.count()).toBeGreaterThan(0);
    const response=await page.request.get(await links.first().getAttribute('href'));
    expect(response.status()).toBe(200);expect((await response.text()).length).toBeGreaterThan(20);
  } else await expect(page.locator('#generated-artifacts a')).toHaveCount(0);
  await expect(page.locator('#formal-status')).toHaveText('not_supplied');
});

test('command and interface share the same law reading and clause observations',async({page})=>{
  const fs=require('node:fs'),path=require('node:path'),{execFileSync}=require('node:child_process');
  const root=path.resolve(__dirname,'../../../..'),dir=path.join(root,'tmp/claim_proof_completion/commands');fs.mkdirSync(dir,{recursive:true});
  const file=path.join(dir,'read.json');fs.writeFileSync(file,JSON.stringify({operation:'read_claim',slug:'po_a2'}));
  const output=execFileSync('uv',['run','--locked','python','scripts/local_run.py','--cwd','apps/review_web','mix','run','--no-start','scripts/explore.exs','--',file],{cwd:root,encoding:'utf8'});
  const doc=JSON.parse(output.trim().split('\n').at(-1));
  await open(page,'po_a2');await tab(page,'clauses');await expect(page.locator('#requires-expression')).toHaveText(doc.receipt.contract.requires);
  const witness=JSON.parse(fs.readFileSync(path.join(root,'apps/review_web/priv/scenarios/P04.json')));
  fs.writeFileSync(file,JSON.stringify({operation:'explain_claim',slug:'po_a2',witness}));
  const explained=execFileSync('uv',['run','--locked','python','scripts/local_run.py','--cwd','apps/review_web','mix','run','--no-start','scripts/explore.exs','--',file],{cwd:root,encoding:'utf8'});
  const data=JSON.parse(explained.trim().split('\n').at(-1));expect(data.receipt.bindings[0].requires.value).toBe(true);
  expect(data.identity.source).toBe(doc.identity.source);
});

test('lambda favicon is served as SVG and ICO',async({page})=>{
  await open(page);
  const href=await page.locator('link[rel="icon"][type="image/svg+xml"]').getAttribute('href');
  const svg=await page.request.get(href);expect(svg.status()).toBe(200);expect(await svg.text()).toContain('<svg');
  const ico=await page.request.get('/favicon.ico');expect(ico.status()).toBe(200);
  const bytes=await ico.body();expect(Array.from(bytes.subarray(0,4))).toEqual([0,0,1,0]);
});
