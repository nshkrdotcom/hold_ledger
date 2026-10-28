# Explorer browser checks

Start Phoenix from the repository root:

```sh
uv run --locked python scripts/local_run.py --cwd apps/review_web mix phx.server
```

In this directory:

```sh
npm ci
npx playwright install chromium
PART3_TEST_BASELINE_ID=<fresh-baseline-id> PART3_TEST_PROPOSAL_ID=<fresh-exact-fit-proposal-id> npm test
```

Use two compatible, operator-trusted snapshots containing the current explorer and evaluator. The proposal should be a disposable exact-fit admission-law exclusion, with governing policy and actual Ledger unchanged. Provision snapshot dependencies offline before starting the test. These are controlled experiments, not production policy changes.

Without those IDs, the isolated replay test reports an explicit NOT RUN skip. A complete local run supplies the IDs and has no skipped comparison test. Other tests execute the real local reducer, reference and coupled model, including local-command/UI parity. The command test opens no listener and owns separate scratch stores.

Tests wait for connected LiveViews and concrete outcomes. They exercise creation/reopen, the four panels, timeline branches, candidate JSON, explicit recalculation, structured starting states, remote delivery/observation, two-tab CAS, reconnect, source/proof access, favicon, keyboard and mobile layout. They make no provider calls or formal acceptance claims. Generated records, command requests and screenshots belong under ignored local paths.
