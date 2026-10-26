# Human review of a Lynx project

Use this guide to review what a Lynx proof lets you claim about a program.
The checker establishes a theorem about translated definitions. You still need
to decide whether the definitions, assumptions and theorem describe the system
you intend to use.

The checklist applies to any Lynx project. Hold Ledger's policy sheet and source
review follow it. Proof evidence is identified by source/export hashes and tool pins. This coding-agent review still
needs independent human review; runtime claims require their own test evidence.

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
| Capacity | Reserved, sent, unknown, authorized and voiding entries consume money and one slot. Declined and voided entries consume neither. | Approve both limits and the treatment of authorized funds. |
| Admission | Fresh positive integer amounts are admitted when both limits permit, including an exact fit. Slot exhaustion wins when both limits fail. | Approve the precedence and integer units. |
| Identity | Integer keys and original amounts remain remembered, including after termination. Matching requests duplicate; different positive amounts conflict. | Accept permanent identity retention and unbounded entry growth. |
| Approval | Only an approved processor-result event can newly authorize an existing eligible entry. Transport acknowledgments cannot. | Identify who may report an approval and how its authenticity is established. |
| Uncertainty | Timeout and restart retain capacity. Retry reuses key and amount. Unknown entries cannot be voided through the reducer. | Accept that a hold can remain unresolved indefinitely. |
| Conflicting outcomes | The first eligible approved/declined result changes the entry. Later results are stale in authorized, voiding, declined or voided states. | Require trustworthy, consistent processor reports; there is no dispute-resolution policy. |
| Voids | Voiding reserved entries has no remote effect. Voiding authorized entries retains capacity in voiding and emits a remote intent. One trusted confirmation releases capacity and retires the obligation. | Accept indefinite capacity retention if confirmation never arrives; require terminal non-resurrection. |
| Recovery | Replay never resends authorization; durable restart converts sent to unknown and pending void obligations redrive. | Accept explicit authorization reconciliation and repeat-safe void execution. |
| External execution | No remote exactly-once guarantee is provided. Deduplication, reliable lookup and durable storage are assumptions. | Obtain evidence for those assumptions before using a real processor or storage deployment. |

### Event authority

The runtime trusts its callers. `Server.submit/2` accepts supported public event shapes and records bounded markers for malformed or reserved internal submissions.
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
| Void completions and lookup observations | Correlated runtime tasks | Reserved internal tags rejected publicly; durable void success retires an outbox obligation |

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

### Ledger, composite state and independent oracle

`Ledger` maintains cached counters with deltas. `Spec` recalculates totals from
entries, models transitions independently and never calls Ledger. Review the
actual `requires:` and `expects:` in every cataloged law; an accepted proof is
about those statements, not an unstated financial requirement.

Reserved, sent, unknown, authorized and voiding entries consume amount and one
slot. Only reserved voids release immediately. Authorized voids enter voiding;
`{:void_confirmed, key}` alone releases their contribution. Terminal entries
remain remembered. No timeout, exhausted attempt budget or manual write-off can
release an unresolved hold.

`Composite` folds ledger and tuple/list obligations together. Its invariant is
exact physical voiding/obligation key equality, obligation uniqueness,
nonnegative attempt counts and permitted outcome metadata. Opening a void
and creating its obligation is one pure transition. One synced confirmation
record releases capacity and removes the obligation together. Live application,
replay and restart use that fold. Spec implements a separate composite oracle;
property tests compare full states, results and effects, including every prefix.
The composite obligations cover initialization, arbitrary-event invariant
preservation, independent step/history agreement, opening, confirmation and
abstract recovery validity. Acceptance still requires a matching fresh report.
Coupling prevents orphan obligations but does not prove eventual execution.

Keys in valid entries are integers. Low-level `find/2` and Spec lookup use loose
numeric equality, while public events guard integer keys. Existing terminal-law
domains include integer-valued floats in queries; do not narrow those hypotheses
to simplify a proof. Compare the actual declarations and generated definitions.

### Environment and adapter authority

`Environment` is a pure tuple/list processor model. Issued identities retain
amounts; a terminal void fences a key even before authorization is delivered.
Delayed authorizations cannot resurrect it. The coupled `Exposure` model's
obligations establish its full independent pair invariant at initialization and
through arbitrary events and finite histories, then derive remote live amount
and count bounds. Truthful observations and permanent fencing are built into
this environment. This describes external hypotheses, not a verified payment
service; matching fresh acceptance remains necessary.

`Processor.capabilities/1` supplies an integrator-attested declaration of positive
terminal confirmation and permanent non-resurrection. Startup checks the
presence and shape of the declaration. It cannot check whether the declaration
is true. A processor that drops its terminal fence when retention expires does
not satisfy this contract. Generic not-found is unresolved. The in-memory Sim's
fences disappear with its process; it does not prove persistent remote behavior.

Public approved/declined callbacks remain trusted integration inputs. Internal
confirmation and lookup observations are reserved and require correlated worker
results. No theorem authenticates a caller or turns a forged approval into real
processor evidence. A VM-controlling attacker is outside this boundary.

### Proof integration and acceptance

The independent required-obligations inventory, law catalog and executable
declarations define the required set. Every registered obligation must remain selected; support is not a filter
for dropping unfinished work. Shared Lean modules prove lookup, shape, accounting,
operation, terminal, oracle and history facts. Inspect changed statements and
hypotheses before sampling tactic bodies.

`test/support/proof_case.ex` generates requires/ensures functions from law ASTs,
translates the actual compiled definitions and orders shared theory after those
definitions. Final wrappers must discharge their own original predicates. The
adapter checks exact theorem identities, including fully qualified native names
through Lean anchors, and rejects missing, failed and skipped results. Acceptance disables the development cache and rejects cached results.

`scripts/run_laws.py` validates the catalog, scans shared sources, checks fresh
proofs, removes stale exports and requires a nonempty export. Full acceptance
requires Lean default, Lean paranoid, lean4lean, nanoda, con-leche and con-ron,
plus the permitted-axiom audit. Default and paranoid are two configurations of
one implementation. Allowed foundational axioms are `propext`, `Quot.sound`
and `Classical.choice`; admissions and custom axioms are forbidden.

A prior successful export does not certify a changed reducer, Spec or proof
library. Obtain a complete current-source report, its source hashes, export
hash/size and raw logs. Compare the source manifest to the reviewed checkout.
Generated evidence is ignored and is not shipped in the package. Launching a run,
a partial report, stale cached artifacts or an empty selection is not acceptance.
See [Verification](verification.md) for the current commands and scope.

### Translation correspondence

The pinned Lynx source extracts BEAM debug information through the backend's
`:core_v1` interface. Its existing translation fixtures and Lean semantic tests
are evidence, but do not prove BEAM-to-Lean equivalence for this program.

`scripts/differential.exs` evaluates actual translated definitions with Lean's
normal frontend and compares outcomes to BEAM on deterministic samples. A small
subset uses kernel-checked equalities; compiled evaluation and kernel reduction
are distinct. Golden literal vectors and encoder unit tests exercise exact term
types, float bits and atom handling. Review this encoding as part of the trusted
harness. Agreement on samples does not eliminate compiler, translator or encoder
trust, and proof-tool errors are not semantic counterexamples.

### Runtime, journal and attempts

Server syncs admitted records before state changes and effects. Internal/malformed
submissions produce bounded audit markers. Append/sync failures poison writes.
Replay checks each composite prefix; invalid history or monitored live-state
failure causes shutdown/quarantine rather than silently discarding an event.

Journal frames use sequence/predecessor integrity, a header hash and a hash of
exact stored payload bytes. Verify before decoding. Explicit incomplete-tail
recovery creates a separate file exclusively and syncs it and its directory;
the original remains untouched. Complete corruption is rejected. A valid shorter
prefix is undetectable without an external freshness anchor. Durable storage,
file integrity and single ownership remain deployment assumptions.

Attempts tracks logical IDs, phases and operation-kind/key slots. Server maps
these to task refs/PIDs/timers. Monitored nolink workers have deadlines and an
independent lifetime timer. A local kill does not cancel remote work. Normal
results demonitor with flush; stale results cannot complete retired attempts.
A persistence acknowledgment permits retirement; failed persistence poisons.
At-most-once persistence and retirement intents are logical safety claims. They
do not prove physical writes or eventual completion.

An old Server's worker can overlap a replacement lifetime. Authorization effects
are never replayed; sent becomes unknown. Voiding entries and obligations remain
coupled and unresolved voids redrive with the same remote identity. Automatic
budgets/backoff bound retries; explicit redrive can reset the budget. Lookups are
asynchronous, and unavailable/raising adapters cannot justify release. Not-found
cannot exclude an older request still in transit. OTP integration and physical
storage are separate from pure-model proof claims.

### Tests, mutation evidence and automatic gates

Plain `mix test` runs ordinary examples, properties, fault tests and tooling
integration checks, excluding expensive proof tests by default. `--only laws`
selects proof attempts, not cheap randomized law evaluation. Executable property
counterparts are available separately for mutation screening.

A mutation campaign must distinguish concrete counterexamples, ordinary test
failures, formal acceptance, proof-script brittleness, translation failure,
timeout, equivalence and unresolved candidates. A tactic failure is not proof
that a law excludes a mutant. Mutation scores describe a defined experiment;
they do not quantify specification completeness.

The always-running CI gate requires full fresh acceptance for proof-relevant
changes, failing closed on missing detection or required skipped/cancelled/failed
formal work. Hosting branch protection must actually require that check; workflow
source does not configure repository settings. Review current artifacts rather
than inferring formal acceptance from an ordinary green test job.

## Human decision for this repository

Independent human review remains required. An agent source assessment does not
satisfy it. A Lean/specification reviewer should assess theorem meanings and
hypotheses; a translator/integration reviewer should assess compilation, term
encoding, acceptance and runtime refinement. Record reviewed source/export
identities, evidence examined, expertise, open findings and actual decisions.

Using this verification example does not establish readiness to operate a payment
service. The integrator must accept event authority, permanent identity/fence
retention, storage durability, single ownership and potentially indefinite held
capacity. Repeat the affected review after relevant changes.
