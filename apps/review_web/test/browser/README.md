# Localhost workbench browser checks

Start Phoenix from the repository root using the pinned toolchain:

```sh
uv run --locked python scripts/local_run.py --cwd apps/review_web mix phx.server
```

In another terminal, from `apps/review_web/test/browser`:

```sh
npm ci
npx playwright install chromium
npm test
```

Set `PLAYWRIGHT_BASE_URL` if the server is on a different loopback port.
These tests make new local review files in ignored `tmp/review_studio/reviews/`.
They do not start Phoenix, run formal checkers, send model data, or execute
mutants. A browser failure is a local QC failure, not an expected pass.

The lockfile records an actual npm resolution. Tests wait for a connected LiveView
before interacting and cover whole-form submission inside the debounce window,
rapid edits under latency, keyboard/mobile use, all graph source bytes, five
answer vocabularies, scoped confirmation and source-identity drift. Only freshly
created synthetic review documents are changed by the drift test. Actual law-file
drift is covered by the Phoenix tests using disposable source copies.
