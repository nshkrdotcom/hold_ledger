# Verification browser checks

Start Phoenix from the repository root:

```sh
uv run --locked python scripts/local_run.py --cwd apps/review_web mix phx.server
```

In this directory:

```sh
npm ci
npx playwright install chromium
npm test
```

These tests cover the separate review application's behavior. They are not
formal-verification acceptance criteria and require no externally supplied
snapshot identities. The fixture-dependent hypothetical exact-fit replay was
removed from this suite under the 2026-11-10 scope correction. Source chooser,
claim lens and existing comparison unit tests remain. The optional source
comparison feature accepts deliberately selected local source trees; it is
neither historical-data migration nor evidence of mathematical correctness.

Tests wait for connected LiveViews and concrete outcomes. They exercise creation/reopen, contrast, contract clauses, actual Lean sources and assumptions, timeline branches, candidate JSON, explicit recalculation, structured starting states, remote delivery/observation, two-tab CAS, reconnect, source/proof access, favicon, keyboard and mobile layout. They make no provider calls or formal acceptance claims. Generated records, command requests and screenshots belong under ignored local paths.

## Claim Lens interaction checks

`0810_claim_lens.spec.cjs` covers the two curated, explicitly hypothetical
claim edits at desktop and narrow viewports, the no-contract-delta control,
source-reading evidence labels and the trusted comparison chooser deep link.
The checks need a running Phoenix server; they do not launch Lean, run mutant
patches, or replace server-side unit/LiveView tests. Run a focused check with:

```sh
npx playwright test 0810_claim_lens.spec.cjs
```
