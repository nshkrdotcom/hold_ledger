# Human review of a Lynx project

Use this guide to review what a Lynx proof lets you claim about a program.
The checker establishes a theorem about translated definitions. You still need
to decide whether the definitions, assumptions and theorem describe the system
you intend to use.

The checklist applies to any Lynx project. Hold Ledger's policy sheet and source
review follow it. That review covers the source snapshot originally recorded as
`08c25a4`, before repository history was consolidated into one initial commit,
and was prepared by a coding agent. It still needs independent human review.
Compare later changes with the recorded snapshot before carrying its findings
forward.

## What needs a full review

Review every item below and record a decision before relying on the claim it
supports. A domain owner should approve the requirements; an engineer familiar
with Lynx and Lean should review the proof integration. Runtime claims also
need someone who understands OTP, storage and the external service.

| Review in full | What the reviewer must decide |
|---|---|
| Requirements, state model and all law statements | The laws express the intended behavior, admit meaningful inputs and cover the claims being made. |
| Input authority and external assumptions | Each trusted input has a justified source; processor, storage and runtime assumptions are acceptable. |
| Translation and verification integration | The checked definitions come from the intended source, and the final obligations retain their original preconditions and conclusions. |
| Acceptance scripts and run evidence | Missing laws, failed checks, stale exports and unauthorized axioms cannot produce acceptance. |
| Public theorem interfaces and trace composition | Shared lemmas state useful facts; their hypotheses hold at each use; history proofs preserve every advertised property. |
| Runtime paths used by an operational claim | Persistence, recovery and effects implement that claim. Pure proofs do not cover these paths. |
| Documentation claims | Readers can distinguish formal guarantees, tests and assumptions. |

### What can be sampled

After reviewing statements, imports and kernel results, sample the detailed
tactic bodies and routine examples. Automated comparison can cover repeated
wrappers. Read every changed law statement and anything that adds an assumption,
changes the checked program or affects acceptance.

## Checklist for any Lynx project

### 1. Agree on the requirements

- [ ] Write the intended behavior independently of the implementation. Name the
  state, operations, failure outcomes and rules that must always hold.
- [ ] Read every law's `requires:` and `expects:`. An implication can be true
  because its precondition is impossible. A weak conclusion can also miss the
  behavior you meant to require.
- [ ] Check concrete witnesses for important preconditions. Include a successful
  operation: an implementation that rejects everything may preserve an invariant.
- [ ] Map each advertised guarantee to a law or to another source of evidence.
  Record requirements that have no proof. A fixed law count does not establish
  that the requirements are complete.
- [ ] Inspect equality, numeric domains, malformed inputs and list shapes. Decide
  whether laws concern all valid states, only reachable states, finite traces or
  some narrower domain. Keep those distinctions in the claims.

### 2. Establish who controls the inputs

- [ ] List callers and event producers, including callbacks, recovery code,
  administrators and internal workers. State what each is allowed to submit.
- [ ] Locate authentication and authorization checks. If they belong to a
  consuming application, say so and identify the evidence it must provide.
- [ ] Separate an event's syntactic validity from the truth of what it reports.
  A well-formed approval event is not proof that a remote service approved it.
- [ ] Review duplicates, conflicting reports and delayed messages. Establish
  whether the model assumes consistent reports or resolves disagreement itself.

### 3. Inspect the checked program

- [ ] Trace source compilation, Core Erlang translation, Lean definitions and the
  final theorem. Confirm the module, function, arity and dependencies at each step.
- [ ] Review supported language constructs and the pinned translator's behavior
  for the operations this project uses. Locate abstractions, cutoffs, custom
  preludes and translation overrides; explain each one.
- [ ] Keep the compiler and translator in the trusted boundary unless their
  correctness is separately established. Export checkers validate the translated
  proof, not its correspondence with the original source or running BEAM program.
- [ ] Inspect any repository adapter completely. Contract generation, name
  resolution, imports and caching can change which obligation reaches Lean.
- [ ] If there is an independent oracle, inspect its independence and meaning.
  Separate implementations can still share the same mistaken requirement.

### 4. Review the proof interfaces

- [ ] Read the statements of shared lemmas and final theorems, including every
  hypothesis. Confirm that final law wrappers actually use these theorems to
  discharge the authored law.
- [ ] Examine induction bases and steps for history properties. Successor
  validity, identity preservation and event evidence need their own arguments;
  none follows merely from replay terminating.
- [ ] Inspect recursive definitions and any termination accommodations. Confirm
  that the theorem's domain matches the program's advertised domain.
- [ ] Reject admissions and unexplained axioms. Check the complete exported
  dependency set against the project's explicit axiom policy.

Tactic repetition, long proofs and large resource limits are maintenance concerns.
They warrant sampling for fragile dependencies, but do not invalidate an accepted
derivation by themselves. A timeout is not a counterexample.

### 5. Review acceptance and provenance

- [ ] Confirm that the selected obligations equal the promised set. Excluded,
  skipped and unfinished obligations must remain visible.
- [ ] Check that acceptance requires actual theorem results. A successful shell
  command, an empty test selection or a status label is insufficient.
- [ ] Inspect cache handling, export cleanup and checker invocation. All checkers
  must receive the intended artifact. Resource retries must preserve that artifact
  and the original checking requirements.
- [ ] Record source revision and hashes, dependency/toolchain pins, commands,
  stage, exit status, actual checker results and axiom dependencies. Preserve the
  export and raw logs for the result being claimed.
- [ ] Verify what CI runs on a normal push. A green ordinary-test job may never
  invoke Lean. Establish a release gate for formal checks when proof-relevant
  source or tooling changes.

Multiple checkers reduce reliance on a single implementation. They do not remove
shared assumptions about the specification, translation, export format or host.
Two configurations of one checker are not two independent implementations.

### 6. Review runtime and external effects

- [ ] Identify what happens between an accepted input, local state change and
  external effect. Review crashes at each boundary and which actions can repeat.
- [ ] Examine ownership, concurrency, persistence, recovery and corruption
  handling for any operational guarantees the project advertises.
- [ ] Document required service guarantees: identity retention, deduplication,
  payload consistency, outcome lookup and the meaning of an acknowledgment.
- [ ] State what happens if uncertainty never resolves. Safety, eventual
  completion and bounded resource use are different requirements.
- [ ] Review tests of these paths separately from the pure-function proofs.
  Injection tests do not establish hardware durability or arbitrary fault coverage.

### 7. Record the decision

Record the revision, intended use, requirements reviewed, assumptions accepted,
evidence locations and open findings. Name an owner for each open decision.
Approval to use a verification example does not authorize operating a service.
Repeat the affected review when laws, source, translation, dependencies,
acceptance tooling or deployment assumptions change.

## Hold Ledger: the policies to approve

Hold Ledger models one account owned by one server and includes a deterministic
processor simulator. It does not connect to a payment service or implement
settlement, expiration, key pruning, multiple accounts or distributed ownership.

This is the policy sheet a human should review before reading proof tactics.
The [specification](specification.md) gives the complete event table.

| Policy | What the code does | Decision required |
|---|---|---|
| Capacity | Reserved, sent, unknown and authorized entries consume money and one slot. Declined and voided entries consume neither. | Approve both limits and the treatment of authorized funds. |
| Admission | Fresh positive integer amounts are admitted when both limits permit, including an exact fit. Slot exhaustion wins when both limits fail. | Approve the precedence and integer units. |
| Identity | Integer keys and original amounts remain remembered, including after termination. Matching requests duplicate; different positive amounts conflict. | Accept permanent identity retention and unbounded entry growth. |
| Approval | Only an approved processor-result event can newly authorize an existing eligible entry. Transport acknowledgments cannot. | Identify who may report an approval and how its authenticity is established. |
| Uncertainty | Timeout and restart retain capacity. Retry reuses key and amount. Unknown entries cannot be voided through the reducer. | Accept that a hold can remain unresolved indefinitely. |
| Conflicting outcomes | The first eligible approved/declined result changes the entry. Later results are stale in authorized, declined or voided states. | Require trustworthy, consistent processor reports; there is no dispute-resolution policy. |
| Voids | Voiding reserved entries has no remote effect. Voiding authorized entries immediately releases local capacity and emits a remote void intent. | Accept that local release precedes remote confirmation and a failed remote void does not restore the hold. |
| Recovery | Replay reconstructs state without executing old effects; a fresh durable restart converts sent entries to unknown. | Accept explicit reconciliation instead of automatic resending. |
| External execution | No remote exactly-once guarantee is provided. Deduplication, reliable lookup and durable storage are assumptions. | Obtain evidence for those assumptions before using a real processor or storage deployment. |

### Event authority

The runtime trusts its callers. `Server.submit/2` accepts any event term.
`processor_callback/3` uses the same input path, as does a matching mailbox
message. These APIs do not check caller identity, permissions or callback
authenticity. The GenServer serializes events but does not establish who may
submit them.

| Event or API | Intended source in an integration | Enforcement in this repository |
|---|---|---|
| Request, dispatch and void | An authorized application operation | Shape and state eligibility only |
| Timeout | A trusted transport/executor reporting uncertainty | No source check; callers can submit it directly |
| Restart | Recovery owner | Startup emits it, but direct submission is also allowed |
| Retry | A recovery policy acting on an unknown hold | Direct retry bypasses the lookup-first convenience API |
| Processor approved/declined result | An authenticated processor adapter or trusted reconciliation result | Outcome/key shape and eligible status only |
| Reconcile / retry after lookup | An authorized recovery operator | Unknown-state check and processor lookup; no operator authentication |
| Void receipts and audit events | Runtime/executor | Journaled metadata; they do not confirm or reverse a pure ledger transition |

The test fault API is enabled only with `allow_faults: true`. That option is a
test convenience, not an access-control mechanism for the event APIs above.

The simulator demo assumes trusted callers. A payment integration must enforce
access before these entry points and authenticate processor evidence. PO-B4
requires the appropriate event; it cannot establish the event's truth or origin.

### Required processor and storage guarantees

A real adapter must bind an identity to one payload, deduplicate retries for the
required lifetime and authenticate outcomes. Lookup must describe the same
operation. A `:not_found` result may precede the arrival of an older in-flight
request, so it does not by itself make a retry safe. The processor must provide
the necessary deduplication and lookup semantics. Unavailable lookup cannot
justify release. See [Processors](processors.md).

The deployment must provide one authoritative owner, protect the journal from
replacement or rollback and justify its durable-flush assumptions. A GenServer
and a hash chain do not establish distributed ownership or storage authenticity.

## Review of the Hold Ledger source

Source links below point to `main`. The full-run evidence below identifies the
reviewed snapshot independently of rewritten Git history. Each section explains
the code behind a claim and the decisions left to a human reviewer.

### Reducer and independent specification

Sources: [Ledger](https://github.com/nshkrdotcom/hold_ledger/blob/main/lib/hold_ledger/ledger.ex)
and [Spec](https://github.com/nshkrdotcom/hold_ledger/blob/main/lib/hold_ledger/spec.ex).

`Ledger` updates cached amount/slot counters using local deltas. `Spec` computes
totals from entries and implements its own transition oracle; neither module
calls the other. `Spec.valid?/1` checks the five-tuple, integer domains, positive
amounts, known statuses, unique keys, exact totals and both limits. This gives
the accounting proofs an invariant that can detect disagreement between cached
and recomputed totals. Compare both implementations with the policies as well:
they can agree with each other and still implement the wrong policy.

`step/2` dispatches eight event forms and rejects other terms as malformed.
Event helpers guard keys and amounts before lookup. Existing valid state is a
precondition; the reducer does not validate every input state. `run/2` recurses
over a proper list and discards results and effects. Improper lists, arbitrary
invalid starting states, process scheduling and elapsed time are outside these
preservation claims.

Requests check remembered identity before capacity. Dispatch and retry preserve
accounting while emitting an intent with the stored amount. Declines and voids
subtract one entry's contribution. Restart changes sent to unknown without
reducing totals.
Terminal keys remain recorded and ineligible for reuse. These branches match
the written policy. Approving that policy still requires decisions about local
void release and conflicting reports. Permanent entry retention also means the
capacity limits do not bound history size, memory use or lookup time.

Equality needs care. State entries use integers, but `find/2` and `Spec.lookup/2`
compare queried keys with `==`. The B5 laws also use loose equality, so an
integer-valued float can satisfy a queried key/amount hypothesis. The terminal
proof retains that domain. L3 uses `===` for its stored-amount hypothesis. A
reviewer should examine those actual expressions rather than infer domains from
variable names or type annotations.

### All 29 law groups

Sources: [catalog](https://github.com/nshkrdotcom/hold_ledger/blob/main/verification/laws.json)
and [law declarations](https://github.com/nshkrdotcom/hold_ledger/tree/main/test/laws).
Read every declaration. This table groups related obligations without adding
claims to them.

| Groups | What their conclusions establish | Important limit |
|---|---|---|
| L1 | Reducer/spec lookup agreement on proper unique entries | No claim about arbitrary malformed entry lists |
| L2, L4 | Status replacement retains identities, shape and uniqueness | Known replacement status and an existing key are hypotheses |
| L3 | Exact accounting change for a selected status replacement | Requires exact lookup of the stored key, amount and old status |
| L5 | A fresh positive entry preserves shape/uniqueness and adds its contribution | Fresh integer key and positive integer amount are required |
| L6 | Marking sent entries unknown preserves both totals | Proper unique entries are required |
| PO-I | Nonnegative integer limits initialize a valid state | Other initialization arguments are outside the theorem |
| PO-A1 | Request preserves validity for arbitrary key/amount terms | Starts from a valid state |
| PO-A2 | Every eligible request is admitted with the specified state, result and effects | Eligibility includes validity, freshness and both capacities |
| PO-A3 | A result classified as not applied preserves the entire state and emits nothing | Does not itself prove that every rejection was justified |
| PO-A4 duplicate; PO-A4 conflict | Remembered keys duplicate or conflict across all statuses | Positive integer request arguments and the corresponding lookup are required |
| Six PO-B1 groups | Dispatch, timeout, restart, retry, processor-result and void preserve validity | Validity alone does not specify each operation's exact result |
| PO-B2 | An unknown entry retains its identity and stays unknown or sent until its own approved/declined result | Unrelated entries may change totals; this is not eventual resolution |
| PO-B3 | Results and effects satisfy the independent effect predicate | Intent data is checked; external execution is not |
| PO-B4 | A newly authorized existing entry needs its eligible approved event | No authentication theorem |
| Two PO-B5 groups | Declined and voided entries retain their status and identity after any event | Valid state and matching terminal lookup are required |
| PO-B6 | Existing keys and amounts remain recorded after one event | Does not bound accumulated history |
| PO-B7 | Restart leaves no sent entries and preserves cached totals | No theorem about an OTP process restart |
| PO-S | An arbitrary event preserves validity | Valid starting state required |
| PO-C1 | A proper finite event list preserves validity | The declared conclusion is validity, not oracle agreement |
| PO-C2 | Replay from valid integer limits ends valid for every proper finite list | Each prefix is another such list; disk replay itself is not modeled |
| PO-C3 | Final-state oracle agreement, retained initial identities/terminals and approval evidence throughout the history | The declared replay equality discards results/effects; no liveness or authenticated evidence claim |

For C3, the executable approval predicate walks the independent oracle's
intermediate states. The shared step-agreement proof connects those states to
the reducer's execution. Review that connection as well as the final equality.

The two A4 groups, six B1 groups and two B5 groups account for the separate
catalog entries. All 29 are required by supported selection. Concrete witnesses
exercise nonempty, reachable cases and positive admission, but finite witnesses
do not prove the specification complete.

### Shared theory and history composition

Sources: [shared Lean modules](https://github.com/nshkrdotcom/hold_ledger/tree/main/test/support/lean)
and [module map](https://github.com/nshkrdotcom/hold_ledger/blob/main/test/support/lean/library.json).

`CoreShape`, `CoreLookup`, `CoreAccounting`, `CoreStructure` and
`CorePreservation` establish common state/list facts. `Induction` supplies shared
functional-induction support. Operation modules use these facts; `Step` proves
validity across the event dispatch, and `Replay` extends it to proper event
lists. Lean checks these shared declarations along with the final law proofs.

`Terminal.lean` proves pointwise terminal lookup preservation for an arbitrary
next event. Its comparison lemma lets exact stored tuples establish the original
B5 statements with loose equality. Terminal preservation depends on the reducer's
eligibility rules: arbitrary status replacement can change a terminal entry.
Check where those eligibility rules enter the proof.

`Oracle.lean` compares `Spec.expected_step` with the reducer result after
recomputing counters. Successor validity establishes that the normalized state
equals the reducer state. The resulting step-agreement theorem includes state,
result and effects. `HistoryRelations.lean` supplies identity composition and
turns pointwise terminal facts into the executable Spec predicate.

`History.lean` inducts on proper events. Its empty case proves the identity
predicate as well as replay equality. Its step uses oracle agreement and
successor validity, PO-B6 identity, PO-B4 approval evidence, and pointwise terminal
preservation. The tail induction hypothesis applies to the valid successor.
The final wrapper proves all four parts of the original C3 contract. Review this
composition in full; individual simplifier and arithmetic steps can be sampled
after checking their dependencies and kernel results.

### Contract generation and Lynx integration

Sources: [adapter](https://github.com/nshkrdotcom/hold_ledger/blob/main/test/support/proof_case.ex),
[test helper](https://github.com/nshkrdotcom/hold_ledger/blob/main/test/test_helper.exs),
and [adapter tests](https://github.com/nshkrdotcom/hold_ledger/blob/main/test/hold_ledger_proof_case_test.exs).

`compile_contracts/0` reads the law ASTs and builds requires/ensures functions
from the original expressions. Unused arguments become `_`; expressions and
argument positions remain intact. The generated module supplies the Ledger/Spec
aliases used by these laws. Extraction relies on their current syntax and
environment. New macros, aliases or attributes need a fresh review of extraction.

The adapter translates these contracts and the actual law modules through the
pinned Lynx APIs, then inserts shared Lean modules after translated definitions
in dependency order. An ordinary Lynx prelude runs before those definitions and
cannot supply these concrete lemmas. Sharing uses repository code without a
Lynx patch. The adapter reads imports from support files, rejects cycles and uses
the module map to choose each law's theory.

Each law proof invokes a shared theorem and must typecheck against its own
translated requires/ensures. `validate_reports!/3` checks module status
and the exact requested theorem names; it rejects absent, skipped and failed
law results. Tests exercise these failures, dependency ordering, loose B5 domains
and development-cache invalidation. They support review of the adapter; they do
not independently prove its translation correctness.

The developer cache hashes source and dependency keys. Acceptance removes the
cache environment variable, and batch validation rejects cached module results.
Review both mechanisms and their callers. A cached developer retry cannot supply
fresh acceptance evidence.

### Trusted tools and dependency pins

Sources: [Mix dependencies](https://github.com/nshkrdotcom/hold_ledger/blob/main/mix.exs),
[pin checks](https://github.com/nshkrdotcom/hold_ledger/blob/main/scripts/verify_pins.py),
[provisioning](https://github.com/nshkrdotcom/hold_ledger/blob/main/scripts/provision.py),
and [toolchain records](https://github.com/nshkrdotcom/hold_ledger/blob/main/scripts/toolchains.json).

Lynx is pinned to `3b44de83fb63503e12b84233de70cf0647e7e63e` and Lean to
4.35.0. Pin checks compare the resolved Lynx commit and runtime/tool versions.
Provisioning verifies downloaded archive checksums before extraction and uses
repository-local tools. On reuse, its marker records the expected archive hash;
it does not rehash every installed executable. Protect or rebuild local tool
directories when the host or their contents are untrusted.

Pins make the intended tools identifiable. They do not prove the Elixir/OTP
compiler, Lynx translation or checker implementations correct. This review
accepts those upstream components as dependencies; it does not audit their full
implementations. A human must accept that trust boundary, review the translator
semantics used here and revisit it on dependency changes.

### Acceptance, checkers and recorded evidence

Sources: [batch driver](https://github.com/nshkrdotcom/hold_ledger/blob/main/scripts/verify_laws.exs),
[acceptance runner](https://github.com/nshkrdotcom/hold_ledger/blob/main/scripts/run_laws.py),
[Nanoda retry](https://github.com/nshkrdotcom/hold_ledger/blob/main/scripts/check_nanoda_serial.py),
and [CI workflow](https://github.com/nshkrdotcom/hold_ledger/blob/main/.github/workflows/ci.yml).

The runner validates the catalog and scans law files and all shared Lean sources
for prohibited proof escapes. Supported selection requires all 29 groups. The
batch driver rejects per-group translation overrides and submits shared theory
and final laws together. Acceptance checks exact law identities and native
results, removes old exports and requires the expected nonempty export. A text
scan can catch obvious escapes but cannot establish proof integrity. The export's
axiom dependencies must also pass the audit.

The full stage checks the export with Lean default, Lean paranoid, lean4lean,
nanoda, con-leche and con-ron. These are six configurations, with shared tooling
and foundations. The permitted axiom dependencies are `propext`, `Quot.sound`
and `Classical.choice`; no custom axioms or admissions are allowed.

If bundled Nanoda overflows its stack while the other configurations accept,
the runner requires a successful serial Nanoda check of the same export before
accepting. The retry uses the pinned binary, a 256 MiB process stack and a
sandbox. Review the original failure, retry command, export hash and axiom audit
together. The serial configuration alone cannot replace the axiom audit.

A full-stage result needs `complete: true`, exactly the expected 29 law records
with `passed: true`, checker acceptance and an allowed axiom list. Read these
fields together with stage, command, revision and hashes. A field describing the
requested checker stage is not itself evidence that checking succeeded.

Ordinary push CI runs tests, static analysis, catalog inspection and static
mutation checks. The expensive formal and native mutation jobs require explicit
workflow dispatch. A normal green push therefore does not certify all 29 proofs
or mutation detection. Require the corresponding full-run artifacts for either
claim. Commands and provenance details are in [Verification](verification.md).

The [detached launcher](https://github.com/nshkrdotcom/hold_ledger/blob/main/scripts/background_laws.py)
checks a committed source snapshot and records status, logs and final artifacts.
It shares local tool/dependency directories with the checkout, so keep those
directories unchanged during the run. The source snapshot does not protect the
shared tools or host from modification. Preserve the result artifacts outside
disposable local storage when using them for approval.

### Full-run evidence inspected

The cold full run completed on 2026-10-25 against the snapshot originally
recorded as `08c25a4`. That revision predates the consolidation of repository
history into one initial commit. Every source hash recorded in the report
matches the current checkout, including the reducer, independent specification,
laws, proof library, adapter and dependency lockfile. All 29 law records passed.
All six configurations accepted the combined export, and the axiom list was
exactly `propext`, `Quot.sound`, `Classical.choice`. This run needed no serial
Nanoda retry. Its combined export was 100,962,008 bytes, with SHA-256:

```text
54b6389b5bd5aac60edf1f78dace8ba005d89abe46294d09d87f71c5092e63df
```

The local evidence is in
`tmp/verification/background-20261025T082451459426Z/`: `report.json`,
`batch/native.json`, `logs/` and `exports/full-suite/suite.ndjson`. These are
ignored artifacts, not files shipped with the guide. A reviewer using another
checkout must obtain that evidence or run the full command again. The result
supports the laws at the recorded revision; it does not supply human policy
approval or evidence for later proof-relevant edits.

### Journal and server

Sources: [Journal](https://github.com/nshkrdotcom/hold_ledger/blob/main/lib/hold_ledger/journal.ex),
[Server](https://github.com/nshkrdotcom/hold_ledger/blob/main/lib/hold_ledger/server.ex),
and [Application](https://github.com/nshkrdotcom/hold_ledger/blob/main/lib/hold_ledger/application.ex).
These paths need full review for runtime claims; they are outside the pure proofs.

`Journal` opens `:disk_log` in halt/internal mode with repair disabled. Replay
reads every chunk, checks sequence and predecessor digest, recomputes SHA-256,
and rejects malformed frames, corrupt bytes and read errors. A partial verified
prefix is not installed after an observed read failure. Appends advance the
in-memory cursor only after sync succeeds.

The chain has no trusted external head, authentication key or expected final
sequence. Removing complete final records may leave a valid shorter chain.
Replacing the log with another valid history is also outside its protection.
The hash chain therefore cannot establish freshness or authenticated storage.

`Server.boot` checks the persisted capacity header, replays with `Ledger.run`,
syncs a new restart and applies it before serving calls. It verifies recovered
states with Spec. There is no replay of historical effects. `journal_and_apply`
syncs every submitted event before stepping, updating memory and scheduling
effects. Append/sync failure preserves the current memory state and poisons
further writes. An ambiguous sync may have persisted an unacknowledged event;
recovery uses the disk history rather than promising that the event was absent.

The application starts an effect supervisor and opens a ledger only when server
options are configured. One server serializes its calls. Deployment must ensure
one authoritative owner for each account/journal; there is no distributed fencing
protocol. The default runtime invariant check can be disabled with
`monitor: false`. It is an executable guard, not a proof of the server.

### Effects, reconciliation and simulator

Sources: [EffectExecutor](https://github.com/nshkrdotcom/hold_ledger/blob/main/lib/hold_ledger/effect_executor.ex),
[Processor](https://github.com/nshkrdotcom/hold_ledger/blob/main/lib/hold_ledger/processor.ex),
and [Sim](https://github.com/nshkrdotcom/hold_ledger/blob/main/lib/hold_ledger/processor/sim.ex).

The executor starts tasks for new intents and reports outcomes as events. It
does not write the journal or update the ledger. Lost/unexpected authorization
responses and caught execution errors become timeouts; void errors become
receipts. The server journals returned events through its normal input path.
Task-start failures also produce timeout or receipt events after the committed
intent. Pending references associate replies with outstanding tasks. They do
not authenticate the sender against a hostile process in the VM.

The executor does not monitor every task to completion or impose an overall
deadline. A task that never returns or is killed before sending its reply can
leave a pending reference and idle waiters unresolved. Server restart still
converts sent to unknown; there is no proved or implemented guarantee that every
live task eventually produces a result. A service needing bounded completion
must address this separately.

Reconciliation operates only on unknown entries. The server journals lookup
intent before calling the processor, then journals the outcome. Reliable
not-found permits explicit lookup-first retry; unavailable lookup leaves the
hold unresolved. Direct submit/retry remains possible. Lookup runs synchronously
inside the GenServer without a server-imposed overall deadline; a slow adapter
can delay other calls. Neither path promises eventual resolution.

Voiding an authorized entry commits a local release before executing a remote
void. Receipts are retained separately and do not restore capacity on failure.
Recovery does not reissue a void lost after the durable intent. A service that
promises to complete or compensate remote voids needs to implement that policy.

The simulator demonstrates lost requests/replies, delayed/duplicate callbacks,
lookup failures and the effect of disabling deduplication. Its records are
in-memory. Successful void removes its remembered outcome, so it is not evidence
of permanent processor tombstones or payload-conflict rejection. Local terminal
identity retention prevents normal ledger reuse; a real processor must supply
its own identity guarantees. See [Runtime and recovery](runtime.md).

### Tests and negative evidence

Sources: [tests](https://github.com/nshkrdotcom/hold_ledger/tree/main/test),
[tooling tests](https://github.com/nshkrdotcom/hold_ledger/tree/main/tooling_tests),
and [mutations](https://github.com/nshkrdotcom/hold_ledger/tree/main/mutants).

Transition/spec tests cover limits, malformed terms, lookup and accounting.
Witness tests exercise each policy family, including exact-fit admission,
terminal entries and approval-versus-acknowledgment. Property tests sample states
and histories. Journal/runtime tests cover injected append/sync/disk-full errors,
truncated tails, crash after sync, abrupt owner death, replay without resending,
concurrent callers, reconciliation and receiver deduplication failure.

Read those failure-path tests alongside the code they support. They do not test
every OS/storage failure or establish security and liveness properties. Tooling
tests exercise missing theorem/checker results, empty exports, axiom rejection
and source scanning. Static mutation checks establish that patches still target
the intended source; only an executed mutation experiment supplies detection
evidence. A failed proof alone supplies no concrete behavioral counterexample.

## Human decision for this repository

Approval as a verification example requires decisions about the stated policies
and trust boundary, backed by review of the laws, proof integration and run
evidence. Approval for a deployment also needs evidence that callers are trusted,
processor/storage assumptions hold and a single owner is enforced. The deployment
owner must decide how to handle indefinite uncertainty, failed remote voids and
tasks or lookups that never complete. Those decisions are not supplied by the
pure proofs.

A reviewer should record a decision in the project's review or release record:

| Record | Required content |
|---|---|
| Scope | Revision and intended use: verification example or a named deployment |
| Policy approval | Financial rules, event authority and handling of uncertainty/void failures |
| Trust accepted | Compiler/translator, checker foundations, processor, storage and owner assumptions |
| Evidence examined | Exact law set, run stage, source/export hashes, checker and axiom results; separate runtime/test results |
| Open findings | Accepted limits, required changes, owner and approval conditions |
| Reviewers | Names, relevant expertise, date and decision for each reviewed area |

Record approval against a specific revision and intended use. Any unresolved
condition should name the person responsible for resolving it.
