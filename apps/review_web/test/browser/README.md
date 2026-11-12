# Verification browser checks

From this directory:

```sh
npm ci
npx playwright install chromium
npm test
npm run test:presentation
npm run test:questions
```

The launcher compiles test code once, then runs file tasks within the detected
machine's CPU/memory budget. Each application task owns a private Phoenix
server, ephemeral port and empty stores; no development server is required.
The controlled questions profile uses the synthetic adapter. No profile invokes
a live provider. Logs, browser results and final status are retained in the
repository's ignored `tmp/browser-runs/` directory. To run all three profiles
from the repository root:

```sh
uv run --locked python scripts/run_browser.py all
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
The checks use managed private Phoenix servers; they do not launch Lean, run mutant
patches, or replace server-side unit/LiveView tests. The launcher retains a separate log/result directory for every spec file.
