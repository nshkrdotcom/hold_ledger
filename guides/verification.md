# Verification

Lynx translates the compiled Elixir ledger and its laws into Lean. Handwritten
Lean scripts establish the law statements. A separate export stage lets six
checker configurations validate the proof objects. This is assurance about the
specified pure functions, not verification of the complete payment runtime.

## Coverage and provenance

The catalog in `verification/laws.json` contains 29 supported groups: six
structural, 17 P0 and six P1. Every group has a Lean proof. PO-B5/declined and
PO-B5/voided establish one-step terminal absorption; PO-C3 lifts identity,
terminal preservation, approval evidence and independent-oracle agreement to
proper finite event histories. No cataloged obligation is excluded by
`--supported-only`.

The current dependency is Lynx `3b44de83fb63503e12b84233de70cf0647e7e63e`,
with Lean 4.35.0. Proof-only checks establish the Lean law statements; full-stage
acceptance additionally requires fresh exports, all six checker acknowledgments,
and the permitted-axiom audit. A launched or partially completed run is not
acceptance. Keep the generated report with the exact source hashes for any
claim about a particular checkout.

The recorded cold full run on 2026-10-25 accepted all 29 groups with this Lynx pin. Source-file hashes and export hash/size identify the checked program; removed repository history is not required for that identity. Compare those hashes before carrying the result forward.
All six checker configurations accepted the export;
the axiom dependencies were exactly `propext`, `Quot.sound`, `Classical.choice`.
The [human review guide](human_review.md#full-run-evidence-inspected) records the
export hash and evidence location, alongside the source assessment and the
decisions that still require human approval.

The retained `verification/baseline.json` is historical evidence for an earlier
26-group run identified by its source hashes and
Lynx `4a7e9db0655b67b6b9fc1e5511eb3fe12625b52c`. It includes export and source
hashes, checker and axiom results, 119 ordinary checks, 22 properties/220,000
examples and 26 runtime tests. Its three then-unproved obligations and its
performance figures describe that earlier source; they do not certify the
current 29-group proof library.

The historical B3 run required a sandboxed Nanoda serial retry after a worker-stack overflow.
The permitted axioms are `propext`, `Quot.sound` and `Classical.choice`.
No extra admissions or custom axioms are permitted.

## Run checks

After setup, validate the catalog without running BEAM or Lean:

```sh
uv run --locked python scripts/run_laws.py --supported-only --inspect-only
```

For an uncached proof-only run:

```sh
uv run --locked python scripts/run_laws.py --supported-only --stage proofs \
  --report tmp/verification/proofs.json
```

For fresh exports and all six checker configurations:

```sh
uv run --locked python scripts/onboard.py --profile proofs
uv run --locked python scripts/run_laws.py --supported-only --stage full \
  --report tmp/verification/checked.json
```

The full stage already includes uncached proof verification: running proof-only
first is unnecessary when the full stage is the goal. Both are expensive.
To check just one group, use `--slug po_a2` instead of `--supported-only`.
All 29 groups, including B5 and C3, are included in the supported selection.

For multiple groups, the runner submits one dependency-ordered cold request:
shared theory is checked once within that request, followed by every selected
law. It exports one combined `suite.ndjson`, which the six checker configurations
check in full. Single-group commands retain their own group export. Lean default
and paranoid are configurations of Lean; the other checkers add implementation
diversity.

The runner removes prior exports, rejects missing or skipped theorem results,
and requires the expected nonempty export and all checker acknowledgments.
Missing tools, timeouts, extra axioms and partial success fail acceptance. Reports,
logs and exports stay under ignored `tmp/verification/`. Acceptance always disables
both Lynx caching and the shared-module development cache.

## Shared proof theory

`test/support/lean/` contains the reusable shape, lookup, accounting, list-structure,
identity, terminal and authorization lemmas. The Step, Replay, Oracle and History
modules compose those results. Laws in `test/laws/` retain the executable
`requires:` and `expects:` contracts and cite checked theorems.

`test/support/proof_case.ex` adapts the pinned Lynx translation/runner APIs. It
generates shared contract predicates directly from the law declarations,
translates Ledger and Spec, then loads the Lean theory before checking each
original law against its own predicates. This ordering matters: Lynx preludes
load before translated definitions and cannot directly contain concrete Ledger
lemmas. Induction support is generated once to avoid duplicate helper declarations
when sibling modules import recursive-function proofs.

The runner scans every shared `.lean` source for proof escapes and records its
hash, along with law sources and the adapter, in the execution report. Runtime
Ledger and Spec remain independent and unchanged by the proof library.

For development only, `HOLD_LEDGER_PROOF_CACHE=1` allows source/dependency-keyed
reuse during direct `mix test` proof attempts. Editing a shared source invalidates
its dependents. These attempts do not establish cold acceptance; use
`scripts/run_laws.py` for that.

## Detached verification

After committing the checkout, start a durable full run with:

```sh
uv run --locked python scripts/background_laws.py
```

The command prints a unique directory under `tmp/verification/`. Its `status.json`
records the commit, process IDs and final exit status; `output.log` retains progress.
The worker checks a local snapshot of the committed source, so subsequent checkout
edits do not change its inputs. On completion it preserves `report.json`, native
results, logs and exports in the run directory. `passed` requires the complete
full-stage result, not merely a zero exit from an empty test command. The process
survives the launching terminal closing; it cannot survive machine shutdown.

## Law catalog

| Group | Purpose | Set |
|---|---|---|
| L1 | proper unique list lookup compatibility | supported |
| L2 | status replacement retains all existing key/amount identities | supported |
| L3 | changing one holding status produces exact delta | supported |
| L4 | replacement by known status retains a well-formed unique list | supported |
| L5 | fresh positive entry contributes exactly one hold | supported |
| L6 | sent-to-unknown preserves both accounting totals | supported |
| PO-I | valid init at every nonnegative pair including zero | supported |
| PO-A1 | request preserves validity for arbitrary key and amount terms | supported |
| PO-A2 | obligatory positive admission including exact fit and exact counters | supported |
| PO-A3 | any not-applied operation returns input unchanged and no intents | supported |
| PO-A4 | all seen keys including terminal matching-amount requests duplicate | supported |
| PO-A4 | seen key different positive amount conflicts across all statuses | supported |
| PO-B1/dispatch | dispatch preserves validity for all valid states and arbitrary arguments | supported |
| PO-B1/timeout | timeout preserves validity for all valid states and arbitrary arguments | supported |
| PO-B1/restart | restart preserves validity for all valid states and arbitrary arguments | supported |
| PO-B1/retry | retry preserves validity for all valid states and arbitrary arguments | supported |
| PO-B1/processor_result | processor_result preserves validity for all valid states and arbitrary arguments | supported |
| PO-B1/void | void preserves validity for all valid states and arbitrary arguments | supported |
| PO-B2 | unknown key amount persists as holding (unknown/sent) until its valid result | supported |
| PO-B3 | all authorize and void intents match stored identity; rejected emits no intents | supported |
| PO-S | one arbitrary event preserves valid state | supported |
| PO-C1 | induct over every proper finite list of arbitrary event terms | supported |
| PO-C2 | validity of every modeled journal prefix from initial limits | supported |
| PO-B4 | no first authorization without approved result for that key | supported |
| PO-B5/declined | declined remains absorbing under arbitrary next event | supported |
| PO-B5/voided | voided remains absorbing under arbitrary next event | supported |
| PO-B6 | all previously seen identities and amounts remain recorded | supported |
| PO-B7 | restart removes all sent without reducing holding counters | supported |
| PO-C3 | finite histories retain terminal/identity and require independent approval evidence | supported |

## Domains and limits

`Spec.valid?/1` is the preservation precondition. `step/2` accepts arbitrary
event terms on valid ledgers. `run/2` is specified for proper finite event
lists. Effects are pure descriptions of intended processor actions.
The precise executable `requires:` and `expects:` are in each law file.

Proofs do not establish the compiler/translator's correctness, authenticated
processor outcomes, receiver deduplication, durable hardware flushes, BEAM/OS
correctness, physical power-loss recovery, remote exactly-once execution,
key expiry or distributed ownership. OTP behavior is tested separately.
A failed proof can reflect resources or tactics rather than a false statement.

## Cost

The historical 26-group baseline's uncached proof commands summed to 1,553.463 seconds;
bundled checker commands to 501.254 seconds, with another 31.037 seconds for
B3's axiom audit and serial retry. The full cold stage took 2,086.524 seconds.
A cache-fill pass took 1,419.621 seconds and a warm repeat 55.321 seconds.
These are command durations, not human proof-authoring time.

The 26 exports totaled 928,451,517 bytes. Each contains elaborated proof terms
and dependencies; separate exports repeat shared definitions. They are local
scratch artifacts and are not included in the source package. Source proof
bodies total 9,172 nonblank lines for a 183-line reducer and 326-line Spec
under the baseline's counting convention. Proof size and maintenance cost are
material considerations when choosing which rules to verify.

The shared refactor's 26-group cold proof-only regression took 564.757 seconds.
This is a native proof measurement, not an all-29 exported-checker measurement.
Shared source removes repeated proof authoring and within-run elaboration, but
exports still contain dependencies; source reduction alone does not establish
an export-size, memory-use or checker-time reduction.

For the shared refactor, counting nonblank shared `.lean` lines plus embedded
Lean blocks gives 3,939 lines, versus 9,276 embedded Lean lines before the
refactor (including the three unfinished attempts): a 57.5% source reduction.
This includes module headers and proof helpers, and differs from the historical
baseline's proof-body-only counting convention.

## CI acceptance gate

The workflow always runs change detection and a final formal gate on push/PR. Proof-relevant changes require a cold full 29-group run, fresh exports, all six checker configurations and allowed-axiom audit. Failed detection or a required skipped/cancelled/failed formal job fails the gate. Missing diff-base data conservatively requires verification. Documentation-only changes may pass without a new proof claim. Native mutation experiments remain dispatchable separately. Hosting branch protection must require the stable `formal-gate` check; workflow code does not configure that setting. Reports and exports are retained as CI artifacts, including failure diagnostics.
