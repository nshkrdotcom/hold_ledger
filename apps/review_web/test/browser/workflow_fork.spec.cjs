const {test, expect} = require('@playwright/test');

async function open(page, slug = 'po_exposure_retain') {
  await page.goto(`/claims/${slug}`);
  await expect(page).toHaveURL(new RegExp(`/claims/${slug}/trace-`));
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
}

async function saved(page) {
  const id = new URL(page.url()).pathname.split('/').at(-1);
  return (await (await page.request.get(`/sessions/${id}/export`)).json()).trace;
}

test('rule-accepts-changed-alternative has its own visual state', async ({page}) => {
  await open(page, 'po_b1_void');
  await expect(page.locator('#verdict-signal')).toHaveAttribute('data-state', 'permits');
  await expect(page.locator('#verdict-signal')).toContainText('Rule permits the changed alternative');
  await expect(page.locator('#selected-law-row td').last()).toHaveText('Accepts alternative');
  await page.locator('#edit-candidate').click();
  await page.getByRole('button', {name: 'Reset to code result'}).click();
  await expect(page.locator('#verdict-signal')).toHaveAttribute('data-state', 'same');
  await page.locator('#alternative-result select').selectOption('insufficient_amount');
  await expect(page.locator('#verdict-signal')).not.toHaveAttribute('data-state', 'same');
});

test('two real follow-on results stay visible in a fork and persist only on save', async ({page}) => {
  await open(page);
  const initial = await saved(page);
  await expect(page.locator('#verdict-signal')).toHaveAttribute('data-state', 'rejects');
  await page.locator('#edit-candidate').click();
  await page.locator('#branch-candidate').click();
  await expect(page.locator('#code-branch .timeline-step')).toHaveCount(1);
  await expect(page.locator('#alternative-branch .timeline-step')).toHaveCount(1);
  await page.locator('#record-event').click();
  await page.locator('#event_type').selectOption('request');
  await page.locator('#event_key').fill('77');
  await page.locator('#event_amount').fill('100');
  await page.locator('#apply-event-pair').click();
  await expect(page.locator('#code-branch .timeline-step')).toHaveCount(2);
  await expect(page.locator('#alternative-branch .timeline-step')).toHaveCount(2);
  await expect(page.locator('#code-branch')).toContainText('Not enough available money');
  await expect(page.locator('#alternative-branch')).toContainText('Accepted');
  await expect(page.locator('#scratch-status')).toBeVisible();
  expect((await saved(page)).steps).toEqual(initial.steps);
  await page.locator('#append-preview').click();
  await expect(page.locator('#scratch-status')).toHaveCount(0);
  const after = await saved(page);
  expect(after.steps.length).toBe(initial.steps.length + 3);
  await expect(page.locator('#code-branch')).toContainText('Not enough available money');
  await expect(page.locator('#alternative-branch')).toContainText('Accepted');
});

for (const [width, height] of [[1440, 900], [390, 844]]) {
  test(`evidence precedes decisions and remains accessible at ${width}px`, async ({page}) => {
    await page.setViewportSize({width, height});
    await open(page);
    const geometry = await page.evaluate(() => {
      const selectors = ['#verdict', '#dissector', '#proof-panel', '#nearby-observation'];
      const nodes = selectors.map(selector => document.querySelector(selector));
      return {
        inOrder: nodes.every((node, i) => i === 0 || Boolean(nodes[i - 1].compareDocumentPosition(node) & Node.DOCUMENT_POSITION_FOLLOWING)),
        sticky: getComputedStyle(nodes[0]).position,
        overflow: document.documentElement.scrollWidth > innerWidth,
      };
    });
    expect(geometry.inOrder).toBe(true);
    expect(geometry.sticky).toBe(width > 950 ? 'sticky' : 'static');
    expect(geometry.overflow).toBe(false);
    await expect(page.locator('#nearby-observation')).toBeVisible();
    await expect(page.locator('#review-help')).toContainText('source-reading aids');
    await expect(page.locator('#inspect-retention')).toHaveCount(0);
    await expect(page.locator('#early-release')).toHaveCount(0);
  });
}
