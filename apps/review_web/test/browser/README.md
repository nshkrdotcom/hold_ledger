# Milestone B localhost browser checks (NOT RUN in the ChatGPT.com first half)

Start Phoenix from the repository root using the pinned toolchain:

```sh
uv run --locked python scripts/local_run.py --cwd apps/review_web mix phx.server
```

In another terminal, from `apps/review_web/test/browser`:

```sh
npm install
npx playwright install chromium
npm test
```

Set `PLAYWRIGHT_BASE_URL` if the server is on a different loopback port.
These tests make new local review files in ignored `tmp/review_studio/reviews/`.
They do not start Phoenix, run formal checkers, send model data, or execute
mutants. A browser failure is a local QC failure, not an expected pass.
