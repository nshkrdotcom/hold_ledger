// These browser fixtures exercise the app's actual delegated help code without
// a Phoenix server. The normal browser suite verifies the rendered LiveViews.
const {test, expect} = require('playwright/test');
const fs = require('node:fs');
const path = require('node:path');

const app = path.resolve(__dirname, '../..');
const source = fs.readFileSync(path.join(app, 'assets/js/app.js'), 'utf8');
const glossary = fs.readFileSync(path.join(app, 'priv/education_glossary.json'), 'utf8');
const start = source.indexOf('const eduTerms =');
const end = source.indexOf('const csrfToken =');
if (start < 0 || end <= start) throw new Error('Cannot locate the application help code');
const helpCode = `const educationGlossary = ${glossary};\n${source.slice(start, end)}`;

test.beforeEach(async ({page}) => {
  await page.setContent(`<!doctype html><html lang="en"><head><style>
    [hidden]{display:none!important}body{margin:20px;font:16px sans-serif}
    #edu-tooltip{position:fixed;width:280px;background:white;border:1px solid;padding:10px}
    #edu-term-dialog,#edu-help-drawer{position:fixed;inset:100px 16px auto;background:white;border:1px solid;padding:16px}
    button{padding:8px}#ordinary{margin-top:250px}
  </style></head><body>
    <button id="edu-help-toggle" data-edu-help-open aria-expanded="false">Page guide</button>
    <section id="review-document">
      <button id="term" data-edu-term="requires" aria-describedby="existing">Applies when</button>
      <span id="existing">Existing explanation</span>
      <table><tr><th tabindex="0" id="unmapped">Internal mystery</th></tr></table>
      <button id="ordinary" data-edu-hint="Runs this example.">Run the case</button>
    </section>
    <aside id="edu-help-drawer" hidden role="dialog" aria-modal="false">
      <button data-edu-help-close>Close page guide</button><h2 id="edu-help-title"></h2>
      <p id="edu-help-description"></p><p id="edu-help-limit"></p>
    </aside>
    <div id="edu-tooltip" role="tooltip" hidden><strong data-tooltip-title></strong><p data-tooltip-short></p></div>
    <aside id="edu-term-dialog" role="dialog" aria-modal="false" aria-labelledby="edu-term-title" hidden tabindex="-1">
      <button data-edu-term-close>Close term guide</button><h2 id="edu-term-title"></h2>
      <p data-term-meaning></p><p data-term-detail></p><p data-term-example></p>
      <code data-term-source></code><a data-term-link>Read glossary</a>
      <button data-copy-explanation>Copy explanation</button><p data-copy-status role="status"></p>
    </aside><p id="copy-status" role="status"></p>
  </body></html>`);
  await page.evaluate(() => {
    window.caseRuns = 0;
    document.getElementById('ordinary').addEventListener('click', () => window.caseRuns++);
  });
  await page.addScriptTag({content: helpCode});
});

test('authored hover help leaves ordinary controls usable and ignores unmapped text', async ({page}) => {
  await page.locator('#unmapped').focus();
  await expect(page.locator('#edu-tooltip')).toBeHidden();
  await page.locator('#ordinary').click();
  expect(await page.evaluate(() => window.caseRuns)).toBe(1);
  await expect(page.locator('#edu-term-dialog')).toBeHidden();
});

test('focus preview is passive; term dialog opens by keyboard and returns focus', async ({page}) => {
  const term = page.locator('#term');
  await term.focus();
  await expect(page.locator('#edu-tooltip')).toBeVisible();
  await expect(page.locator('#edu-tooltip')).toHaveAttribute('role', 'tooltip');
  await expect(page.locator('#edu-tooltip a, #edu-tooltip button')).toHaveCount(0);
  await expect(term).toHaveAttribute('aria-describedby', 'existing edu-tooltip');
  await page.keyboard.press('Enter');
  await expect(page.locator('#edu-term-dialog')).toBeVisible();
  await expect(page.locator('#edu-tooltip')).toBeHidden();
  await expect(term).toHaveAttribute('aria-expanded', 'true');
  await expect(page.locator('[data-edu-term-close]')).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(page.locator('#edu-term-dialog')).toBeHidden();
  await expect(term).toBeFocused();
  await expect(term).toHaveAttribute('aria-describedby', 'existing');
  await expect(term).toHaveAttribute('aria-expanded', 'false');
});

test('moving onto a tooltip keeps its explanation available', async ({page}) => {
  await page.locator('#term').hover();
  await expect(page.locator('#edu-tooltip')).toBeVisible();
  await page.locator('#edu-tooltip').hover();
  await expect(page.locator('#edu-tooltip')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.locator('#edu-tooltip')).toBeHidden();
});

test('patching the active explanation closes stale help and restores descriptions', async ({page}) => {
  await page.locator('#term').click();
  await expect(page.locator('#edu-term-dialog')).toBeVisible();
  await page.locator('#term').evaluate(node => {node.textContent = 'Updated condition';});
  await expect(page.locator('#edu-term-dialog')).toBeHidden();
  await expect(page.locator('#term')).toHaveAttribute('aria-describedby', 'existing');
  await page.locator('#term').click();
  await expect(page.locator('#edu-term-dialog')).toBeVisible();
  await page.locator('#term').evaluate(node => node.remove());
  await expect(page.locator('#edu-term-dialog')).toBeHidden();
});

test('page guide closes with Escape and returns focus to its opener', async ({page}) => {
  await page.locator('#edu-help-toggle').click();
  await expect(page.locator('#edu-help-drawer')).toBeVisible();
  await expect(page.locator('#edu-help-limit')).not.toBeEmpty();
  await page.locator('#edu-help-toggle').evaluate(node => node.setAttribute('aria-expanded', 'false'));
  await expect(page.locator('#edu-help-toggle')).toHaveAttribute('aria-expanded', 'true');
  await page.keyboard.press('Escape');
  await expect(page.locator('#edu-help-drawer')).toBeHidden();
  await expect(page.locator('#edu-help-toggle')).toBeFocused();
});

test('attribute patches update help and preserve its accessible relationship', async ({page}) => {
  const term = page.locator('#term');
  await term.click();
  await expect(page.locator('#edu-term-dialog')).toBeVisible();
  await term.evaluate(node => node.setAttribute('data-edu-term', 'expects'));
  await expect(page.locator('#edu-term-dialog')).toBeHidden();
  await term.click();
  await expect(page.locator('#edu-term-dialog')).toBeVisible();
  await term.evaluate(node => {
    node.removeAttribute('aria-haspopup');
    node.removeAttribute('aria-controls');
    node.setAttribute('aria-expanded', 'false');
  });
  await expect(term).toHaveAttribute('aria-haspopup', 'dialog');
  await expect(term).toHaveAttribute('aria-controls', 'edu-term-dialog');
  await expect(term).toHaveAttribute('aria-expanded', 'true');
  await term.evaluate(node => node.removeAttribute('data-edu-term'));
  await expect(page.locator('#edu-term-dialog')).toBeHidden();
  await expect(term).not.toHaveAttribute('aria-haspopup');
});

test('new term buttons receive dialog semantics without changing ordinary actions', async ({page}) => {
  await page.locator('#review-document').evaluate(node => {
    node.insertAdjacentHTML('beforeend', '<button id="new-term" data-edu-term="expects">Output promise</button>');
    document.getElementById('ordinary').setAttribute('data-edu-term', 'expects');
    document.getElementById('ordinary').setAttribute('phx-click', 'run-case');
  });
  await expect(page.locator('#new-term')).toHaveAttribute('aria-haspopup', 'dialog');
  await expect(page.locator('#ordinary')).not.toHaveAttribute('aria-haspopup');
  await page.locator('#ordinary').click();
  expect(await page.evaluate(() => window.caseRuns)).toBe(1);
  await expect(page.locator('#edu-term-dialog')).toBeHidden();
});
