# Verification

Lynx translates the compiled Elixir ledger and its laws into Lean. Handwritten
Lean scripts establish the law statements. A separate export stage lets six
checker configurations validate the proof objects. This is assurance about the
specified pure functions, not verification of the complete payment runtime.

## Coverage and provenance

`verification/obligations.json` records the required group identities and fully
qualified theorem names independently of execution results. The catalog in
`verification/laws.json` registers all 49 groups, including the original 29.
`supported` means a proof implementation is available;
only a matching successful execution report establishes acceptance. Every declared obligation must be checked; the catalog is not a claim that the latest source has already passed. PO-B5/declined and
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

Proof evidence is tied to exact source hashes and export hash/size. Earlier
reports do not certify changes to the status graph, composite fold or proof
library. Run the complete command on the reviewed source and retain the generated
report and raw artifacts under ignored `tmp/verification/`. An independent human
review remains a separate milestone; see [Human review](human_review.md).

The permitted foundational axioms are `propext`, `Quot.sound` and
`Classical.choice`. No admissions or custom axioms are permitted.

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
All cataloged groups, including B5 and C3, are included in the supported selection.

For multiple groups, the runner submits one dependency-ordered cold request:
shared theory is checked once within that request, followed by every selected
law. It exports one combined `suite.ndjson`, which the six checker configurations
check in full. Single-group commands retain their own group export. Lean default
and paranoid are configurations of Lean; the other checkers add implementation
diversity.

The runner removes prior exports, rejects missing or skipped theorem results,
checks qualified native theorem names with Lean, rejects orphan theory modules,
and requires the expected nonempty export and all checker acknowledgments.
Missing tools, timeouts, extra axioms and partial success fail acceptance. The
report separately records required, registered, supported, accepted and missing
groups. `release_complete` requires full cold checker acceptance of the entire
inventory; subset runs cannot establish it. A preflight failure replaces a
requested prior report with an explicit incomplete result. Reports,
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

| Group | Purpose | Proof implementation |
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
| PO-B1/void_confirmed | confirmation preserves validity and releases only voiding capacity | supported |
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
| PO-ATTEMPT/poison | poisoned attempt state rejects new starts | supported |
| PO-ATTEMPT/retired | absent attempt IDs reject late result/DOWN/deadline/shutdown/commit | supported |
| PO-ATTEMPT/slot | occupied operation/key slot rejects a second start | supported |
| PO-ATTEMPT/history | typed finite lifecycle histories preserve unique IDs/slots and at-most-once retirement; committing ignores duplicate outcomes | supported |
| PO-ENV/fence | a terminal fence rejects delayed authorization | supported |
| PO-EXPOSURE/retain | an issued hold retains capacity without its own terminal release evidence | supported |
| PO-EXPOSURE/history | lift retention across a proper finite history of actual ledger transitions | supported |
| PO-EXPOSURE/bounds | derive remote live amount/count bounds under causal intent, truthful terminal evidence and identity deduplication | supported |
| PO-COMP/recovery | accepted live composite transitions replay to identical full durable state | supported |
| PO-C3 | finite histories retain terminal/identity and require independent approval evidence | supported |
| PO-COMP/init | initialized ledger and obligation list satisfy the full independent composite invariant | supported |
| PO-COMP/preservation | arbitrary events preserve exact physical voiding/obligation coupling, uniqueness and valid metadata | supported |
| PO-COMP/oracle | single-step agreement with the independent composite oracle | supported |
| PO-COMP/history | finite histories preserve coupling and agree with the independent composite oracle | supported |
| PO-COMP/confirmation | one confirmation atomically releases capacity/removes its obligation; duplicates are stale | supported |
| PO-COMP/open | an authorized void opens exactly one fresh obligation | supported |
| PO-COMP/recovery-valid | accepted composite histories retain full invariant validity | supported |
| PO-EXPOSURE/model | model initialization, arbitrary-event preservation and finite-history pair validity | supported |
| PO-EXPOSURE/model-bounds | pair validity implies remote live amount/count bounds | supported |
| PO-ATTEMPT/persist | at most one persist intent per attempt; retirement requires prior persistence | supported |

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

## Cost and interpretation

Full proof/export/checker runs are expensive. Use targeted groups during proof
development and ordinary executable properties for cheap mutation screening.
A proof-script failure or timeout on a mutant is inconclusive without a concrete
contract-violating trace. A full-suite survivor claim requires the complete
supported set, not only the mapped targeted law. Record unresolved budget-limited
cases separately. Measure the current model rather than reusing old run durations.

## CI acceptance gate

The workflow always runs change detection and a final formal gate on push/PR. Proof-relevant changes require a cold full catalog run, fresh exports, all six checker configurations and allowed-axiom audit. Failed detection or a required skipped/cancelled/failed formal job fails the gate. Missing diff-base data conservatively requires verification. Documentation-only changes may pass without a new proof claim. Native mutation experiments remain dispatchable separately. Hosting branch protection must require the stable `formal-gate` check; workflow code does not configure that setting. Reports and exports are retained as CI artifacts, including failure diagnostics.

## Added model boundaries

The catalog includes explicit attempt-poison, retired-ID, occupied-slot and
environment-fence obligations. These cover their declared operations. Runtime
scheduling, process monitoring and physical persistence remain separately tested.

`PO-EXPOSURE/retain` establishes one-step retention of an issued identity without
its own decline or void-confirmation event. `PO-EXPOSURE/history` composes this
across finite histories using the actual translated `Ledger.run/2`.
`PO-EXPOSURE/bounds` derives both remote live amount and count bounds. Its
`CausalLive` hypothesis requires an issued-intent witness with the same identity
and amount, followed by the actual ledger history with no truthful terminal
release evidence. Remote identity deduplication is a separate hypothesis.
Truthful declines and permanent terminal fencing justify that exclusion for a
still-live processor authorization. These are external requirements, not facts
that a capability declaration can verify. The conclusion does not assume that
the final ledger already holds the remote authorization.

The coupled `Exposure` model separates local operations, authorization delivery,
observation, remote void and confirmation. `PO-EXPOSURE/model` establishes its
independent pair invariant at initialization, after arbitrary event terms, and
through proper finite histories. `PO-EXPOSURE/model-bounds` derives live remote
amount/count limits directly from that invariant. The invariant includes full
composite coupling, unique issued/remote identities, exact amounts and compatible
local/remote states. Its per-key characterization is proved equivalent in both
directions to the independent Spec predicate.

Truthful observations, identity deduplication and permanent terminal fencing are
built into this processor environment. The theorem does not establish that a
real adapter implements those assumptions. The separate causal-history theorem
supports its own explicitly conditional claim. Neither model establishes
settlement correctness, account balances, eventual completion or storage durability.
For acceptance of a particular checkout, retain the complete fresh report rather
than treating catalog membership or a development proof pilot as acceptance.

## Composite recovery theorem

The native Lean group `PO-COMP/recovery` refers directly to the actual translated
`Composite.step/2` and `Composite.run/2`. Its `Committed` relation records a finite
sequence of successful individual live transitions. `committed_replay` proves by
induction that replay of those events yields the same complete composite state,
including obligations and durable attempt counts. This abstract equality does
not cover frame decoding, capacity configuration, orphan-record checks or the
Server’s appended restart event. It does not assume replay
equality as a hypothesis and does not assert storage durability or progress.

Native groups are explicit catalog entries with named theorem sources and
modules. Their entire modules must typecheck and be included in the fresh export;
the runner rejects missing, skipped, cached or mismatched module results. The
source scan and six-checker/axiom acceptance requirements also apply. This is
separate from proving composite invariant preservation or independent-oracle
correspondence, which require their own obligations.

## Lifecycle history theorem

`PO-ATTEMPT/history` gives a typed finite-history model of the runtime's logical
attempt events. Its `step_bridge` establishes that every encoded transition
executes the actual translated `Attempts.step/2`; the safety proof is not about
an unconnected handwritten replacement. `translated_history_safety` preserves
unique operation/key slots, distinct positive IDs below the monotonically
increasing next ID, and a duplicate-free history of retirement intents.
A retired ID remains absent. `committing_quiet` establishes that result, DOWN,
deadline and shutdown-result events cannot emit another persistence intent while
an outcome is committing.

The history theorem starts at `Attempts.init/0`'s encoded state and concerns
well-typed logical runtime events. The separate poison, absent-ID and occupied-slot
laws retain their broader declared term domains. Actual process references,
message authentication, scheduling and journal writes remain runtime obligations;
one logical retirement does not itself prove a disk flush happened.

`PO-ATTEMPT/persist` additionally establishes at-most-once persistence intents and
that every retirement has a prior persistence intent in the typed history. Server
handlers execute exactly correlated persist, shutdown and retire instructions;
fault tests cover that integration. The theorem counts logical instructions,
not successful physical writes.
