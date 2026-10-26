# Assurance audit of Hold Ledger

Use this guide for an initial or periodic audit of Hold Ledger's policies, proof models
and runtime boundaries. For a single agent change, use [Human review](human_review.md).

**Source baseline:** links below are pinned to `618ee1e7f17e490f643bed898f00b9f67c1cd2b4`.
Compare subsequent changes before relying on this audit route. [Verification](verification.md)
defines the required proof evidence.

In a full checkout, start the comparison with:

```sh
git diff 618ee1e7f17e490f643bed898f00b9f67c1cd2b4 HEAD -- lib test verification scripts guides/specification.md AGENTS.md mix.exs mix.lock lean-toolchain .tool-versions .github
```

This covers the policy, implementation, laws, runtime tests and checking setup discussed below. Follow any changed dependencies beyond those paths.

## Hold Ledger: the top-level view

Hold Ledger concerns authorization holds for one account. It does not implement
settlement, expiration, pruning or distributed ownership. Its
[specification](specification.md) is the starting point for policy review.

| Claim | Scope |
|---|---|
| Local accounting | Holding entries consume amount and slot capacity; the counters agree with the entries. |
| Remote exposure | Live authorizations stay within those limits in the coupled model, under its processor assumptions. |
| Composite histories | The ledger and obligations remain consistent; folding accepted events reconstructs the recorded abstract state. |
| Attempt histories | Typed logical events preserve attempt safety within a Server lifetime. Persistence intents and acknowledgments carry no physical durability guarantee. |
| OTP execution and storage | Server, task and journal behavior must implement those models. This correspondence and physical durability are outside the pure proofs. |

The decisive policy is that an authorized hold enters `:voiding` and retains
capacity until trusted terminal confirmation. A reserved hold can be voided
immediately because it has issued no authorization. A sent or unknown hold
cannot be cancelled through `void`; it remains held until reliable evidence
resolves it. There is no timeout release or operator write-off. Identities stay
remembered permanently, so entries can grow without bound. These are policy
choices to approve before relying on the proofs.

Permanent retention has a cost even when every invariant holds. Lookup and
status changes can take linear time; Spec's uniqueness check is quadratic in
retained entries. Capacity limits bound holding entries while terminal entries
accumulate. Judge the expected account lifetime and request volume against
measured latency and memory budgets, including the cost of invariant monitoring.

Consider an amount limit of 100 and two slots. Authorize 100 for one key,
request its void, and delay the confirmation. A new request for 100 must be
refused. Local release at the void request would allow remote exposure of 200
while the local counters remained within 100. That is the distinction the
exposure model must capture.

A second trace tests the service assumption: deliver a void before the processor
has seen the authorization, then deliver the delayed authorization. Positive
void confirmation must already have fenced the identity. The guarantee must
survive ordinary record expiry. An adapter's capability declaration cannot
establish that the service honors the contract.

## Hold Ledger under the microscope

### Exposure: read the environment as part of the specification

The environment determines which remote executions the theorem covers. Start in
[`exposure.ex`][exposure] and [`environment.ex`][environment], then follow
`Spec.exposure_valid?/1` into its supporting predicates in [`spec.ex`][spec].
Issuing an authorization, remote delivery, observing a result, remote void and
local confirmation are separate operations. Follow the delayed-confirmation
trace through them. Identify where truthful observations, identity/payload
binding and terminal non-resurrection enter the model.

[`ExposureModel.lean`][exposure-proof] states `model_preserves`, `model_history`
and `model_bounds`. Preservation ranges over any pair satisfying
`Spec.exposure_valid?/1` and any event term; histories range over proper finite
lists. In [`ExposureValidity.lean`][exposure-view], `view` supplies the
correspondence between a per-key relation and the independent Spec predicate.
Examine both directions: the relation must neither omit a state the predicate
admits nor admit an orphaned remote authorization. The numerical bound must
follow from that relation and capacity accounting, rather than arrive as an
extra hypothesis. Follow the encoding lemmas far enough to establish that every
Spec-valid pair has the representation the proof uses.

The unseen-key trace belongs to the environment contract. `void_before_issue`
establishes that case separately; the coupled model requires an existing void
obligation, so it does not exercise an unseen-key void along that path.

The separate causal-history bound in `ExposureBound.lean` has different
hypotheses. Its `CausalLive` witness is not interchangeable with a proof that
arbitrary coupled executions preserve the pair invariant. Decide which theorem
supports the claim being reviewed.

The adapter contract in [Processors](processors.md) is the deployment
obligation. `Processor.validate/1` checks an integrator's declaration. It cannot
detect a false declaration, and the in-memory simulator's tombstones do not
survive its process. Even a truthful processor can remain unavailable
indefinitely; the model provides no eventual-release guarantee.

### Laws and oracle: separate shared policy from independent arithmetic

Read `test/laws/*.exs` against the requirements, following each called predicate
into `Spec`. `valid?/1` constrains shape, uniqueness and accounting;
`request_eligible?/3` expresses positive admission; `effects_valid?/5` and
`authorized_only_on_result?/3` constrain effects and authorization evidence.
Preservation alone would not require admitting an eligible request or emitting
its required effect.

Ledger and Spec do not call one another. Spec recomputes counters from entries,
but its transition oracle follows many of the same policy branches as Ledger.
Both versions can encode the same mistaken requirement. Judge the precedence of
duplicate/conflict checks and slot/amount rejection against the examples you
chose independently. Agreement between the implementations cannot decide whether
that precedence is right.

Also inspect the equality boundary. `Ledger.find/2` and `Spec.lookup/2` use
loose numeric equality; public key events require integers. A lookup can match
`1` and `1.0`, while a public key event containing `1.0` is malformed. Some law
queries therefore have a wider domain than public events. Judge that choice
against the intended API semantics.

### Composite state: look for lost obligations

An accounting proof can miss a lost obligation. Compare
[`Composite.step/2`][composite] with `Spec.expected_composite_step/2` and
`Spec.composite_valid?/1`. The invariant requires exactly the same physical keys
in voiding entries and obligations, with no duplicate obligations and valid
attempt metadata. Merely checking that a lookup finds each key could miss a
duplicate or shadowed entry.

Opening a void and creating its obligation is one transition. The single
`{:void_confirmed, key}` event releases capacity and removes the obligation in
one transition. In [`CompositeSafety.lean`][composite-proof], examine
`composite_preserves`, `composite_oracle_history`, `open_obligation` and
`confirmation_once` against those requirements. A ledger-valid voiding entry can
still have no obligation and nothing to redrive. Removing an obligation without
trustworthy completion can conceal live exposure. Neither coupling nor
uniqueness establishes that retries will eventually succeed.

### Lean execution relations: examine what a history means

In [`Recovery.lean`][recovery-proof], `Committed` records translated
`Composite.step/2` evaluations that return `Except.ok`, including rejected
ledger operations. `committed_replay` proves equality with replay of those
events. Read the relation before accepting a claim of crash recovery: its
constructors contain no file writes, durable flushes or Server startup.
`CompositeSafety.recovery_valid` adds invariant validity for that abstract
history; it does not add storage semantics.

In [`AttemptSafety.lean`][attempt-proof], read `Valid`, `Retired`, `Persisted`
and `TranslatedRun` before the history theorems. `step_bridge` connects the
typed model to the translated `Attempts.step/2`. The histories range over typed
logical events and attempt IDs. The mapping from PIDs, monitor references and
mailbox messages remains a runtime obligation. At-most-once persistence and
retirement count logical intents; a recorded persistence intent does not mean a
physical write succeeded.

### Server and journal: follow one confirmation through failure

The runtime has to turn a worker result into a durable state change. Follow that
path in [`server.ex`][server], `effect_executor.ex`, `event.ex` and
[`journal.ex`][journal]: correlation, append/sync, the composite fold and task
retirement. Place a crash before and after sync, then compare the live and
recovered states. The confirmation crash test in
`test/hold_ledger_terminal_contract_test.exs` is a concrete point of comparison.

Then consider a deadline, a killed worker and a Server crash with surviving
nolink workers. Late task replies must not complete a replacement attempt;
evidence can still arrive through a trusted callback or a fresh lookup. Local
cancellation does not cancel remote work. A replacement Server may redrive the
same identity while an earlier remote call still exists.

Trace who can supply each result. Public internal completion tags are rejected
and worker outcomes are correlated. Public approved/declined reports through
`submit/2`, `processor_callback/3` and the callback mailbox route still trust
the integrating application. An approved event can satisfy PO-B4 without being a
truthful processor approval. The first eligible processor result wins; conflict
recording does not reverse that policy.

The embedding application must authenticate and authorize callers before they
reach these APIs. Bounded rejection markers constrain stored payloads; they
provide no authentication.

For the journal, concentrate on the durability assumptions and recovery
decision. Frame hashes and sequence checks detect damaged or reordered records.
They cannot detect replacement by a valid shorter prefix without an external
freshness anchor. Incomplete-tail recovery depends on an intact durable prefix
and honest sync semantics; it does not justify discarding acknowledged history
damaged later.

### Translation and acceptance: follow one claim end to end

[`test/support/proof_case.ex`][adapter] generates `ProofContracts` from law
syntax, translates the compiled functions and attaches the shared Lean theory.
Follow one authored `requires:`/`expects:` pair into its generated definition
and final theorem. For native groups, follow the qualified names from
[`obligations.json`][required] and [`laws.json`][catalog] to their Lean
statements. Review the expected set itself; two edited inventories can agree
while omitting a requirement.

[`scripts/run_laws.py`][acceptance], `verify_laws.exs`, `obligations.py` and
`formal_gate.py` control acceptance, together with the workflow and checker
invocation. Examine anything that could change the checked program, skip kernel
checking, narrow selection or turn partial results into success. The source
manifest and export identity must belong to the claim under review. Distinguish
a supported catalog entry, a development proof attempt and full export
acceptance. The six checker configurations include two configurations of Lean.
All share the translated definitions and theorem statements.

After a reported Nanoda stack overflow, the runner can retry with one thread
and a 256 MiB process stack. Verify that it uses the same pinned checker and
export, retains sandbox isolation and
records actual acceptance under the axiom policy. A stack overflow supplies no
evidence against the theorem. Read [`scripts/check_nanoda_serial.py`][nanoda-retry]
with its caller in `run_laws.py`; the
[verification guide](verification.md) and [troubleshooting guide](troubleshooting.md)
describe the checking policy and retry.

The permitted axioms here are `propext`, `Quot.sound` and `Classical.choice`.
Review changes to that policy as changes to the proof's foundations.

Read the differential encoder in `test/support/differential.ex` and
`verification/DifferentialCodec.lean` with exact term identity in mind.
Integer/float distinctions, atom handling and exception outcomes can hide a
translation discrepancy if the encoding collapses them. Compiled comparisons and
the small kernel-checked subset supply different evidence; neither proves
universal translation equivalence. The kernel subset checks selected function
results and literal/atom codec cases. Numeric-parser comparisons use compiled
Lean execution.

[exposure]: https://github.com/nshkrdotcom/hold_ledger/blob/618ee1e7f17e490f643bed898f00b9f67c1cd2b4/lib/hold_ledger/exposure.ex
[environment]: https://github.com/nshkrdotcom/hold_ledger/blob/618ee1e7f17e490f643bed898f00b9f67c1cd2b4/lib/hold_ledger/environment.ex
[spec]: https://github.com/nshkrdotcom/hold_ledger/blob/618ee1e7f17e490f643bed898f00b9f67c1cd2b4/lib/hold_ledger/spec.ex
[exposure-proof]: https://github.com/nshkrdotcom/hold_ledger/blob/618ee1e7f17e490f643bed898f00b9f67c1cd2b4/test/support/lean/ExposureModel.lean
[exposure-view]: https://github.com/nshkrdotcom/hold_ledger/blob/618ee1e7f17e490f643bed898f00b9f67c1cd2b4/test/support/lean/ExposureValidity.lean
[composite]: https://github.com/nshkrdotcom/hold_ledger/blob/618ee1e7f17e490f643bed898f00b9f67c1cd2b4/lib/hold_ledger/composite.ex
[composite-proof]: https://github.com/nshkrdotcom/hold_ledger/blob/618ee1e7f17e490f643bed898f00b9f67c1cd2b4/test/support/lean/CompositeSafety.lean
[recovery-proof]: https://github.com/nshkrdotcom/hold_ledger/blob/618ee1e7f17e490f643bed898f00b9f67c1cd2b4/test/support/lean/Recovery.lean
[attempt-proof]: https://github.com/nshkrdotcom/hold_ledger/blob/618ee1e7f17e490f643bed898f00b9f67c1cd2b4/test/support/lean/AttemptSafety.lean
[server]: https://github.com/nshkrdotcom/hold_ledger/blob/618ee1e7f17e490f643bed898f00b9f67c1cd2b4/lib/hold_ledger/server.ex
[journal]: https://github.com/nshkrdotcom/hold_ledger/blob/618ee1e7f17e490f643bed898f00b9f67c1cd2b4/lib/hold_ledger/journal.ex
[adapter]: https://github.com/nshkrdotcom/hold_ledger/blob/618ee1e7f17e490f643bed898f00b9f67c1cd2b4/test/support/proof_case.ex
[required]: https://github.com/nshkrdotcom/hold_ledger/blob/618ee1e7f17e490f643bed898f00b9f67c1cd2b4/verification/obligations.json
[catalog]: https://github.com/nshkrdotcom/hold_ledger/blob/618ee1e7f17e490f643bed898f00b9f67c1cd2b4/verification/laws.json
[acceptance]: https://github.com/nshkrdotcom/hold_ledger/blob/618ee1e7f17e490f643bed898f00b9f67c1cd2b4/scripts/run_laws.py
[nanoda-retry]: https://github.com/nshkrdotcom/hold_ledger/blob/618ee1e7f17e490f643bed898f00b9f67c1cd2b4/scripts/check_nanoda_serial.py
