# Hold Ledger Review Studio

A localhost Phoenix/LiveView companion for reviewing the meaning and limits of
claims over the pure ledger. The repository root remains an independent package.

From this directory, with the repository's pinned Elixir/OTP tools:

```sh
mix deps.get
mix assets.setup
mix assets.build
mix phx.server
```

Open http://localhost:4000/review. The default scripted explainer makes no
network calls. Follow the [manual exercise](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/interactive_review.md)
for prediction, candidate comparison, original claims and a human receipt.

Configuration is resolved at startup:

- `HOLD_LEDGER_REVIEW_ROOT`: optional checkout override; must contain the ledger
  sources and guides, with Ledger/Spec bytes matching the compiled dependency.
  A mismatch requires recompilation; browser events cannot supply paths.
- `HOLD_LEDGER_REVIEW_REPORT`: optional existing JSON report, relative to the
  checkout under `tmp/verification/`. All manifest files and checked export bytes
  must match. Missing evidence is displayed as `not_supplied`.
- `HOLD_LEDGER_REVIEW_MODE=source_review`: requires the exact reviewed HEAD and a
  named scope when recording a decision. Default: `practice`.
- `HOLD_LEDGER_REVIEW_EXPLAINER=inference` and `HOLD_LEDGER_REVIEW_MODEL`: opt in
  to the OpenAI provider through `Inference.Adapters.ReqLLM`; configure
  `OPENAI_API_KEY` in the local environment. Pick a model whose adapter reports
  JSON Schema support. Unknown/unsupported capabilities fail closed. No weaker
  format fallback is attempted.

Hosted mode sends the bounded question, selected case, computed predicates and
quoted source anchors to that provider. It sends no credentials, absolute local
paths or whole-repository export in the explanation context. No external call
is a test dependency. The prompt is versioned under `priv/prompts/`; shape and
citation checks cannot establish that an explanation is true. Mark misleading
text and open the original evidence. Provider errors/timeouts leave every
review action available; switch back to scripted mode at startup as needed.

Receipts are immutable JSON under root `tmp/review_studio/receipts/`, with an
HTTP Markdown download from their read-only page. Duplicate submission within
a live session returns the same ID. Refresh starts a new independent practice
session; unfinished sessions are in memory and do not survive restart. No
accounts, database, journal, processor calls or browser proof runner are used.

## Checks

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix assets.build
mix precommit
```

For actual Chromium interaction checks, start the server, then in `test/browser`:

```sh
npm ci
npx playwright install chromium
npm test
```

Screenshots and browser state belong in ignored root `tmp/`. Tests use synthetic
checker fixtures explicitly labeled as fixtures, never bundled as proof evidence.
The root verification and package checks remain separate. Transitive hosted
provider dependencies may emit upstream warnings on the pinned Elixir version;
application compilation still uses warnings as errors.

## Limits

Three curated cases and source mappings are supported, not arbitrary theorem
parsing. Scripted explanations offer fixed prompts rather than semantic answers
to arbitrary questions. No local computation proves Phoenix, OTP scheduling,
journal durability, processor honesty or remote exactly-once behavior. Formal
status authenticates consistency of a local report and its exports; it does not
rerun independent checkers or cryptographically authenticate report authorship.
A receipt records human judgment, not deployment authorization. Local single-user
use is the supported environment; hosted releases and production auth are out of
scope. A human study remains necessary before claiming improved review outcomes.
