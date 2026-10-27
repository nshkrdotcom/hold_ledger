# Hold Ledger Review Studio

Review Studio is a local Phoenix app for exploring how people can review formal
verification produced with coding agents. You predict a ledger transition, try
an incorrect alternative, inspect the claim and its sources, and record what
you think the evidence supports.

An agent can produce a passing proof of a statement that misses a requirement.
Consider an authorized payment hold: asking to void it should leave capacity
reserved until confirmation arrives. A claim that checks only whether the next
state is internally consistent can still permit an early release. Review Studio
lets you try that output and see which additional requirement excludes it.

This is a spike to work out a human-in-the-loop (HITL) workflow. Over time, we
want a person to be able to state a requirement, challenge the contract an agent
proposes, and review the resulting code and proof against that requirement.
The agent can do the drafting and proof work, explain unfamiliar terms, and
suggest questions. The person resolves disputed requirements and decides
whether the claim is adequate.

The current app exercises that idea with three cases from Hold Ledger. We still
need to observe developers using it: can they spot an inadequate claim, explain
why it fails, and recognize when evidence is missing? That will tell us which
parts of the workflow are useful before we try broader automation or other
systems. We haven't established that the interface improves review outcomes.

## Run it locally

Use Erlang/OTP **29.1.2** and Elixir **1.20.4**, as pinned by the repository.
From the repository root:

```sh
cd apps/review_web
mix deps.get
mix assets.setup
mix assets.build
mix phx.server
```

Open [localhost:4000/review](http://localhost:4000/review). The server binds to
`127.0.0.1`. Stop it with Ctrl+C in the terminal where you started it.

The default explainer uses your local Codex login through ASM, with
`gpt-6.1-sol` at low reasoning effort. Run `codex login` if needed. For offline
scripted explanations, start with `HOLD_LEDGER_REVIEW_EXPLAINER=scripted`.
The app calls the pure ledger and specification functions on fixed inputs;
starting it doesn't start a ledger server or open a journal.

You can also follow the
[manual review exercise](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/interactive_review.md)
without running Phoenix.

## Work through a review

Start with **Pending void** at `/review/void_pending`.

1. Read the initial state and event. Predict whether the hold should keep its
   capacity, release it, or require more investigation. Add a reason if useful.
2. Reveal the computed transition. Inspect the status, counters, result and
   emitted effects. Ledger and the independent Spec are evaluated separately;
   a disagreement blocks acceptance until someone resolves it.
3. Choose an incorrect alternative. The predicate table shows which concrete
   checks accept it. Toggle conclusions to see what a weaker contract permits.
4. Apply the next request to the selected branch. Early release can admit a
   second hold while the first remote authorization might still exist.
5. Open the law's original `requires` and `expects`, the predicate definitions,
   and the shared Lean theorem. Check whether the displayed input qualifies.
6. Ask for an explanation if you need one. Follow its citations and flag text
   that seems misleading or unsupported.
7. Record a judgment: accept for scope, reject, needs policy, or insufficient
   evidence. Acceptance and rejection require your own rationale and evidence
   selections.

The other cases examine a **lost reply** (`/review/timeout_unknown`) and
**exact-fit admission** (`/review/exact_fit`). A timeout leaves the remote
outcome unresolved, so capacity stays held. Exact fit illustrates a positive
requirement: a reducer that refuses every request could preserve valid states
while failing to admit requests that should succeed.

Each row in the predicate table describes one concrete evaluation. Changing a
selection doesn't edit a law or rerun Lean. A branch labeled counterfactual is
a hypothetical local execution; it doesn't establish a remote processor trace.

## Read the proof evidence

A review packet records the case inputs, computed outputs, source excerpts and
digests used in the session. The app can also read an existing report from
`scripts/run_laws.py`. To supply one, start the app with a path relative to the checkout:

```sh
HOLD_LEDGER_REVIEW_REPORT=tmp/verification/checked.json mix phx.server
```

The report must be under the repository's `tmp/verification/` directory. The app
checks every file in its source manifest, the required case laws, and the saved
export bytes and checker records. It displays the scope reported by that run:

| Status | Meaning |
|---|---|
| `not_supplied` | No report was supplied. |
| `development_only` | A proof-only or cached run doesn't supply independent checker acceptance. |
| `selected_checked` | The current report and exports support its selected law groups. |
| `full_catalog_checked` | The current report also records complete required catalog coverage. |
| `incomplete` | Required report fields or evidence are missing or invalid. |
| `failed` | A required case law is recorded as failed. |
| `stale` | Sources or the recorded source manifest no longer match. |

The app validates a local report's consistency. It doesn't rerun the checkers or
cryptographically authenticate who wrote the report. See the root
[verification guide](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/verification.md)
for the commands and requirements for formal acceptance. A catalog entry marked
`supported` is never treated as a successful proof run.

## Save a human decision

The app writes an immutable JSON receipt under the repository's
`tmp/review_studio/receipts/` directory. Its read-only page offers a Markdown
export. The receipt records your prediction, examined alternatives, selected
claims, rationale, cited evidence, proof status, and source and packet digests.

A repeated submission in the same live session returns the existing receipt.
Refreshing the page starts a new review; unfinished sessions live in memory and
are lost on restart. Saved receipts survive. If sources change, an old receipt
remains available and is marked stale. Acceptance is blocked for a stale packet;
you can still record that the evidence is insufficient.

Practice mode is the default. Set `HOLD_LEDGER_REVIEW_MODE=source_review` to
require the exact reviewed HEAD revision and a description of the change or claim.
A human's acceptance remains separate from the formal evidence status. A receipt
records judgment about the stated scope; it grants no deployment authority.

## Use an AI explainer

The configured client uses `Inference.Adapters.ASM`, provider `:codex`, and
the Codex SDK lane. Its default model is `gpt-6.1-sol` with
`reasoning_effort: :low`. Codex manages authentication through its local login.

```sh
codex login
mix phx.server
```

To change the model or effort at startup:

```sh
HOLD_LEDGER_REVIEW_MODEL=gpt-6.1-sol \
HOLD_LEDGER_REVIEW_REASONING_EFFORT=low mix phx.server
```

Client construction belongs to `inference_client_options` in `config/config.exs`.
The explainer consumes the configured `Inference.Client` without choosing an
adapter or provider. An explicitly supplied `:inference_client` is preserved.
The adapter must report JSON Schema support for this app's structured responses.
Set `HOLD_LEDGER_REVIEW_EXPLAINER=scripted` for fixed offline explanations.
Tests and CI explicitly use scripted mode or mock clients.

In inference mode, the provider receives your question, the selected case and
candidate, computed predicates, proof status, and quoted source anchors. The
explanation context contains no API credentials or absolute local filesystem
paths. Source text and questions are treated as data. The prompt is versioned
in `priv/prompts/review_explainer_v1.md`.

Responses must fit a bounded schema and cite sources in the current packet.
These checks catch malformed output and invented citation IDs; they can't tell
whether a cited passage supports a sentence. Open the source and judge that
connection yourself. Model errors and timeouts leave the evidence and review
controls available. The model cannot supply a proof verdict or record a human
decision. Tests use mocks and require no provider credentials.

## Configuration

All environment settings are read at startup.

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `4000` | Local HTTP port. The development origin check allows port 4000; configure the endpoint's `check_origin` list if you change it. |
| `HOLD_LEDGER_REVIEW_ROOT` | Checkout root | Source checkout to inspect. Ledger and Spec bytes must match the compiled dependency. |
| `HOLD_LEDGER_REVIEW_REPORT` | Unset | Existing report under root `tmp/verification/`. |
| `HOLD_LEDGER_REVIEW_MODE` | `practice` | `practice` or `source_review`. |
| `HOLD_LEDGER_REVIEW_EXPLAINER` | `inference` (`scripted` in tests) | `scripted` or `inference`. |
| `HOLD_LEDGER_REVIEW_MODEL` | `gpt-6.1-sol` | Overrides the configured client model. |
| `HOLD_LEDGER_REVIEW_REASONING_EFFORT` | `low` | Overrides the configured reasoning effort. |

Browser events can't supply source or report paths. The root override is checked
against the compiled Ledger and Spec so computed facts can't be paired with a
different implementation's source. Recompile against the intended checkout if
those bytes differ.

## Develop and check the app

This directory is a separate Mix project with its own dependencies and lockfile.
It depends on the root `:hold_ledger` package through `path: "../.."`. Phoenix,
inference and the review UI stay outside the ledger package and its proof tooling.

| Code | Responsibility |
|---|---|
| `lib/hold_ledger_review/cases.ex`, `facts.ex` | Fixed scenarios and pure computations. |
| `packet.ex`, `anchor.ex`, `proof_evidence.ex` | Source excerpts, digests and report validation. |
| `session.ex`, `receipts.ex` | Allowed review actions and saved judgments. |
| `explainer/` | Scripted and model explanations with response validation. |
| `lib/hold_ledger_review_web/` | LiveViews, components and receipt download. |

From this directory:

```sh
mix format
mix precommit
mix docs --warnings-as-errors
mix assets.build
```

`mix precommit` compiles with warnings as errors, checks formatting, runs strict
Credo and Dialyzer, and runs the tests. You can also run `mix credo --strict` or
`mix dialyzer` separately. The first Dialyzer run builds its dependency table and
can take several minutes. Generated docs are written under `doc/`.

For Chromium checks, leave the server running and use another terminal:

```sh
cd test/browser
npm ci
npx playwright install chromium
npm test
```

These checks cover the three offline cases, keyboard entry, mobile layout,
scripted explanations, and receipt/export. The web CI workflow runs analysis,
tests, docs, assets and browser checks separately from the root project checks.
Synthetic checker reports appear only in tests and are never bundled as evidence
for the current checkout.

## Troubleshooting and limits

If startup rejects the source root, check `HOLD_LEDGER_REVIEW_ROOT` and recompile
against the checkout you intend to inspect. If a packet becomes stale, reload to
begin a new review. If the explainer is unavailable, check its mode, model,
credentials and schema capability; the rest of the review still works.

The app supports three curated cases and source mappings. It doesn't parse
arbitrary laws, run proof commands from the browser, edit repository files, or
execute arbitrary Elixir. It also doesn't verify Phoenix, OTP scheduling,
journal durability, processor honesty, or remote exactly-once behavior. The root
[architecture guide](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/architecture.md)
explains those boundaries.

Local use by one person is the supported setup. Accounts, shared reviews and
production hosting are outside this spike.
