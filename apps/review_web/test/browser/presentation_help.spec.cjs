// These browser fixtures exercise the app's actual delegated help code without
// a Phoenix server. The normal browser suite verifies the rendered LiveViews.
const {test, expect} = require('playwright/test');
const fs = require('node:fs');
const path = require('node:path');

const app = path.resolve(__dirname, '../..');
const source = fs.readFileSync(path.join(app, 'assets/js/app.js'), 'utf8');
const glossary = fs.readFileSync(path.join(app, 'priv/education_glossary.json'), 'utf8');
const registryPath = path.join(app, 'priv/education_help.json');
const registry = fs.readFileSync(registryPath, 'utf8');
const start = source.indexOf('const eduTerms =');
const end = source.indexOf('const csrfToken =');
if (start < 0 || end <= start) throw new Error('Cannot locate the application help code');
const helpCode = `const educationGlossary = ${glossary};\nconst educationHelp = ${registry};\n${source.slice(start, end)}`;

test.use({hasTouch: true});

test('learning navigation marks the chapter section without marking Overview', async ({page}) => {
  await page.route('http://review.test/translation', route => route.fulfill({
    contentType: 'text/html',
    body: `<html><body><header id="global-header"><nav data-global-nav>
      <a href="/" data-nav="/">Overview</a>
      <a href="/start" data-nav="/start" data-nav-group="learn">Learn</a>
      <a href="/lab" data-nav="/lab">Case Lab</a>
      <a href="/atlas" data-nav="/atlas">Claim Atlas</a>
    </nav></header></body></html>`,
  }));
  await page.goto('http://review.test/translation');
  await page.addScriptTag({content: helpCode});
  await expect(page.locator('[data-nav-group="learn"]')).toHaveAttribute('aria-current', 'page');
  await expect(page.locator('[data-nav="/"]')).not.toHaveAttribute('aria-current', 'page');
});

test('a source shortcut opens its disclosure and focuses the source region', async ({page}) => {
  await page.goto('about:blank');
  await page.setContent(`<html><body>
    <a href="#source-detail" data-reveal-source>Read the source</a>
    <details id="source-detail"><summary>Source</summary><pre>actual source</pre></details>
  </body></html>`);
  await page.addScriptTag({content: helpCode});
  await page.locator('[data-reveal-source]').click();
  await expect(page.locator('#source-detail')).toHaveAttribute('open', '');
  await expect(page.locator('#source-detail')).toBeFocused();
});

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
      <button id="append-preview" phx-click="apply_preview">Save to timeline</button>
      <input id="question-field" aria-label="Draft question" />
    </section>
    <aside id="edu-help-drawer" hidden role="dialog" aria-modal="false">
      <button data-edu-help-close>Close page guide</button><h2 id="edu-help-title"></h2>
      <p id="edu-help-description"></p><p id="edu-help-limit"></p>
      <section data-control-guide><h3>Help with controls</h3><div id="edu-control-help"></div></section>
    </aside>
    <div id="edu-tooltip" role="tooltip" hidden><strong data-tooltip-title></strong><p data-tooltip-short></p></div>
    <aside id="edu-term-dialog" role="dialog" aria-modal="false" aria-labelledby="edu-term-title" hidden tabindex="-1">
      <button data-edu-term-close>Close term guide</button><h2 id="edu-term-title"></h2>
      <p data-term-meaning></p><p data-term-detail></p><p data-term-example></p>
      <section data-term-why-section><p data-term-why></p></section>
      <section data-term-limit-section><p data-term-limit></p></section>
      <div data-term-lookups></div>
      <code data-term-source></code><a data-term-link>Read glossary</a>
      <button data-copy-explanation>Copy explanation</button><p data-copy-status role="status"></p>
    </aside><p id="copy-status" role="status"></p>
  </body></html>`);
  await page.evaluate(() => {
    window.caseRuns = 0;
    window.timelineSaves = 0;
    document.getElementById('ordinary').addEventListener('click', () => window.caseRuns++);
    document.getElementById('append-preview').addEventListener('click', () => window.timelineSaves++);
  });
  await page.addScriptTag({content: helpCode});
});

test('touch users can explain a control without running it', async ({page}) => {
  await page.locator('#edu-help-toggle').tap();
  const help = page.locator('[data-help-control="lab.save_to_timeline"]');
  await expect(help).toBeVisible();
  await help.tap();
  await expect(page.locator('#edu-term-dialog')).toBeVisible();
  await expect(page.locator('#edu-term-title')).toHaveText('Save to timeline');
  await expect(page.locator('[data-term-meaning]')).toContainText('review session');
  expect(await page.evaluate(() => window.timelineSaves)).toBe(0);
  await page.keyboard.press('Escape');
  await expect(page.locator('#append-preview')).toBeFocused();
  await page.locator('#append-preview').tap();
  expect(await page.evaluate(() => window.timelineSaves)).toBe(1);
});

test('registry help follows a patched control and discards detached context', async ({page}) => {
  await page.locator('#append-preview').focus();
  await expect(page.locator('#edu-tooltip [data-tooltip-short]')).toContainText('review session');
  await page.locator('#append-preview').evaluate(node => node.replaceWith(node.cloneNode(true)));
  await expect(page.locator('#edu-tooltip')).toBeHidden();
  await page.locator('#edu-help-toggle').click();
  await page.locator('[data-help-control="lab.save_to_timeline"]').click();
  await expect(page.locator('#edu-term-dialog')).toBeVisible();
  await page.locator('#append-preview').evaluate(node => node.remove());
  await expect(page.locator('#edu-term-dialog')).toBeHidden();
});

test('question-mark shortcut opens help only outside text entry', async ({page}) => {
  await page.locator('#question-field').focus();
  await page.keyboard.type('?');
  await expect(page.locator('#edu-help-drawer')).toBeHidden();
  await expect(page.locator('#question-field')).toHaveValue('?');
  await page.locator('#append-preview').focus();
  await page.keyboard.press('?');
  await expect(page.locator('#edu-help-drawer')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.locator('#append-preview')).toBeFocused();
});

test('changing an action replaces its registered explanation', async ({page}) => {
  const action = page.locator('#append-preview');
  await action.focus();
  await expect(page.locator('#edu-tooltip [data-tooltip-short]')).toContainText('review session');
  await action.evaluate(node => node.setAttribute('phx-click', 'reset_experiment'));
  await expect(page.locator('#edu-tooltip')).toBeHidden();
  await page.locator('#question-field').focus();
  await action.focus();
  await expect(page.locator('#edu-tooltip [data-tooltip-short]')).toContainText('Discard temporary changes');
});

test('closing help for a disabled control returns focus to Help', async ({page}) => {
  await page.locator('#append-preview').evaluate(node => {node.disabled = true;});
  await page.locator('#edu-help-toggle').click();
  await page.locator('[data-help-control="lab.save_to_timeline"]').click();
  await expect(page.locator('#edu-term-dialog')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.locator('#edu-term-dialog')).toBeHidden();
  await expect(page.locator('#edu-help-toggle')).toBeFocused();
});

test('proposed result, hold status and effect type have distinct help', async ({page}) => {
  await page.locator('#review-document').evaluate(node => node.insertAdjacentHTML('beforeend', `
    <form id="candidate-form">
      <select id="result-field" name="output[result]"><option>admitted</option></select>
      <select id="status-field" name="output[entries][0][status]"><option>reserved</option></select>
      <select id="effect-field" name="output[effects][0][type]"><option>authorize</option></select>
    </form>`));
  await page.locator('#result-field').focus();
  await expect(page.locator('#edu-tooltip [data-tooltip-title]')).toHaveText('Proposed result');
  await page.locator('#status-field').focus();
  await expect(page.locator('#edu-tooltip [data-tooltip-title]')).toHaveText('Change a proposed hold state');
  await page.locator('#effect-field').focus();
  await expect(page.locator('#edu-tooltip [data-tooltip-title]')).toHaveText('What-if outside work');
});

test('Guides retains the current-page marker outside primary navigation', async ({page}) => {
  await page.evaluate(() => document.body.insertAdjacentHTML('afterbegin', `
    <header id="global-header">
      <nav data-global-nav><a href="/" data-nav="/">Explore</a></nav>
      <details id="reference-nav"><summary>Guides</summary>
        <a href="/system" data-nav="/system">How the system works</a>
      </details>
    </header>`));
  const markup = (await page.content()).replace(/<script\b[^>]*>[\s\S]*?<\/script>/g, '');
  await page.route('http://review.test/system', route => route.fulfill({body: markup, contentType: 'text/html'}));
  await page.goto('http://review.test/system');
  await page.addScriptTag({content: helpCode});
  await expect(page.locator('#reference-nav [data-nav="/system"]')).toHaveAttribute('aria-current', 'page');
  await expect(page.locator('[data-global-nav] [data-nav="/"]')).not.toHaveAttribute('aria-current', 'page');
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


test('pointer entry after keyboard scrolling preserves the focused explanation', async ({page}) => {
  const term = page.locator('#term');
  await term.focus();
  await expect(term).toHaveAttribute('aria-describedby', 'existing edu-tooltip');
  const title = await page.locator('[data-tooltip-title]').innerText();
  await page.locator('#ordinary').dispatchEvent('pointerover', {pointerType: 'mouse'});
  await expect(page.locator('[data-tooltip-title]')).toHaveText(title);
  await expect(term).toHaveAttribute('aria-describedby', 'existing edu-tooltip');
  await expect(term).toBeFocused();
  await page.keyboard.press('Escape');
  await page.locator('#ordinary').dispatchEvent('pointerover', {pointerType: 'mouse'});
  await expect(page.locator('#edu-tooltip')).toBeHidden();
  await term.evaluate(node => node.blur());
  await page.locator('#ordinary').hover();
  await expect(page.locator('[data-tooltip-short]')).toHaveText('Runs this example.');
  expect(await page.evaluate(() => window.caseRuns)).toBe(0);
});

test('an open question panel keeps background hover help out of its controls', async ({page}) => {
  await page.evaluate(() => {
    const panel = document.createElement('section');
    panel.id = 'question-panel';
    panel.innerHTML = '<input id="panel-field"><button id="panel-help" data-edu-term="requires">Input condition</button>';
    document.body.append(panel);
    panel.querySelector('input').focus();
  });
  await page.locator('#ordinary').dispatchEvent('pointerover', {pointerType: 'mouse'});
  await expect(page.locator('#edu-tooltip')).toBeHidden();
  await page.locator('#panel-help').focus();
  await expect(page.locator('#edu-tooltip')).toBeVisible();
  await expect(page.locator('#panel-help')).toHaveAttribute('aria-describedby', 'edu-tooltip');
});

test('attribute-only patches restore registered control help', async ({page}) => {
  const save = page.locator('#append-preview');
  await expect(save).toHaveAttribute('data-help', 'lab.save_to_timeline');
  await save.evaluate(node => node.removeAttribute('data-help'));
  await expect(save).toHaveAttribute('data-help', 'lab.save_to_timeline');
  await save.focus();
  await expect(page.locator('[data-tooltip-title]')).toHaveText('Save to timeline');
  expect(await page.evaluate(() => window.timelineSaves)).toBe(0);
});
