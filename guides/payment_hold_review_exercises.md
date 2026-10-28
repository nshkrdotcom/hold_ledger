# Eight payment-hold review exercises

When a claim says a ledger stays valid, which mistakes does it rule out?
Try these eight cases before reading their answers. Each asks you to judge
a proposed outcome against the payment policy. You need no tools.

The P01–P08 labels identify the same cases in the optional
[Phoenix workbench](../apps/review_web/README.md). Start with the local
cancellation below; it gives you a correct outcome to compare with the mistakes.

Use [the specification](specification.md) to judge the outcomes. Amounts below are **integer cents**. A hold
uses both amount capacity and one hold slot. A returned effect describes
outside work to request; it does not establish that the work happened.

The proposed outcomes are invented for these exercises. The current
implementation does not produce the mistakes shown here.

## 1. Cancel before sending anything (P08)

An account has a 100-cent limit and room for two holds. Hold 1 reserves all
100 cents locally. No authorization has been dispatched.

**Event:** cancel hold 1.

**Proposed outcome:** mark it `voided`, release 100 cents and one slot, and
request no outside work. Keep the key and original amount in the entry list.

Is immediate release correct? Would you require a remote confirmation?

<details>
<summary>Answer: local cancellation may release immediately</summary>

<p>
The hold was <code>reserved</code>, not <code>sent</code> or <code>authorized</code>. This model has not issued
an authorization for it, so there is no remote authorization to cancel.
<code>void</code> releases a reserved hold locally and returns no effects.
</p>

<p>
The key remains remembered. Cancelling the hold does not permit reusing its
identity as a new request.
</p>

<p>
A fresh 100-cent request under another key can now fit. This is the control
case: rejecting every proposed alternative would also reject correct behavior.
</p>

</details>

## 2. A request fits exactly (P04)

The account has a 100-cent limit, one free slot and no entries.

**Event:** request 100 cents under a fresh key, 11.

**Proposed outcome:** return `insufficient_amount`; leave the account empty.

The limits are still respected. Does that make this an acceptable result?

<details>
<summary>Answer: preserving limits is not enough</summary>

<p>
The policy requires admission when a fresh positive request fits both limits,
including equality. The correct result reserves 100 cents and one slot,
records key 11 as <code>reserved</code>, returns <code>admitted</code>, and emits no outside work.
</p>

<p>
A program that refuses every request can preserve an upper bound. It still
fails to provide the promised service. Positive admission is a separate
requirement from validity preservation.
</p>

<p>
Read <a href="https://github.com/nshkrdotcom/hold_ledger/blob/main/test/laws/po_a2_test.exs">the admission law</a> and compare its exact
starting conditions and promised result. Try reasoning about 99, 100 and
101 cents with the same 100-cent limit. The first two requests fit; the third
does not, assuming the same fresh key and free slot.
</p>

</details>

## 3. A missing reply (P03)

Hold 1 was sent to the processor for 100 cents. It uses all the amount
capacity, and the ledger has not received a trusted outcome.

**Event:** the authorization times out.

**Proposed outcome:** mark the hold `declined` and release its capacity.

What does the timeout establish? What could happen if a second request uses
the supposedly available 100 cents?

<details>
<summary>Answer: silence is not a decline</summary>

<p>
The processor could have approved before its reply was lost. The policy
changes <code>sent</code> to <code>unknown</code> and retains the amount and slot. It does not
manufacture a terminal processor result.
</p>

<p>
With the correct next state, a fresh request for another 100 cents is refused.
Starting from the invented released state, that request could be admitted
while the old authorization remained live remotely.
</p>

<p>
A released <code>declined</code> entry can look internally consistent. Therefore checking
that counters add up is not enough to justify the transition.
</p>

</details>

## 4. The label says unknown; the counters say free (P06)

Start with the same sent 100-cent hold.

**Event:** timeout.

**Proposed outcome:** keep the entry as `unknown`, but set both used counters
to zero. Return `marked_unknown` and no effects.

Has retaining the entry fixed the problem from the previous exercise?

<details>
<summary>Answer: the entry and the counters now disagree</summary>

<p>
An <code>unknown</code> entry still consumes its amount and one slot. A state containing
that 100-cent entry cannot truthfully report zero used amount and zero holds.
The alternative violates the state invariant as well as the retention policy.
</p>

<p>
Contrast P03: changing the entry to a terminal status can make the released
counters internally consistent, while still violating the timeout policy.
Different bad outcomes need different checks.
</p>

<p>
See <a href="https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/specification.md#state-and-validity">state validity</a> and
<a href="https://github.com/nshkrdotcom/hold_ledger/blob/main/test/laws/po_b1_timeout_test.exs">the timeout preservation law</a>.
</p>

</details>

## 5. Cancel an approved hold (P01)

Hold 1 is `authorized` for 100 cents, using all the amount capacity. There is
room for two holds by count.

**Event:** request cancellation.

**Proposed outcome:** mark it `voided`, free both counters and emit no void
request to the processor.

Identify two independent problems.

<details>
<summary>Answer: premature release and missing outside work</summary>

<p>
An authorized hold becomes <code>voiding</code>, retains its amount and slot, and returns
a void effect for that key. Trusted terminal confirmation is still needed
before release.
</p>

<p>
The alternative frees capacity that may still be held remotely and omits the
cancellation request. A second 100-cent hold could fit the invented released
state; the required transition keeps that capacity occupied.
</p>

<h3>Follow this case through the checks</h3>

<p>
Before reading the table, predict whether each check accepts P01's proposed
output: a <code>voided</code> entry, zero used counters, result <code>voided</code> and no effects.
The starting state is valid, the entry is authorized, and the local void
request supplies no release evidence, so the retention law applies.
</p>

<table>
<thead>
<tr><th>Check from the existing laws</th><th>Accepts P01's output?</th><th>Why</th></tr>
</thead>
<tbody>
<tr><td><code>Spec.valid?/1</code> (<code>po_b1_void</code>)</td><td>Yes</td><td>A voided entry uses no capacity, so its zero counters add up.</td></tr>
<tr><td><code>Spec.effects_valid?/5</code> (<code>po_b3</code>)</td><td>Yes</td><td>For the supplied <code>voided</code> result, this predicate accepts an empty effects list. It does not require the authorized-to-voiding transition.</td></tr>
<tr><td><code>Spec.exposed_entry?/3</code> (<code>po_exposure_retain</code>)</td><td>No</td><td>The previously authorized entry must remain in a held status. <code>voided</code> releases it.</td></tr>
</tbody>
</table>

<p>
If you expected the effects check to catch the missing cancellation request,
read its <a href="https://github.com/nshkrdotcom/hold_ledger/blob/main/lib/hold_ledger/spec.ex">definition</a>. It branches on the supplied
result. A name such as “effects valid” does not tell you the whole promise.
</p>

<p>
Now repair the state and result: make the status and result <code>voiding</code> and restore the
100 cents and one slot, but leave the effects empty. That is P02 below.
Validity and retention now accept the output; the effects check rejects it
because a <code>voiding</code> result requires the void request. Restoring that effect
makes all three checks accept the required transition.
</p>

<p>
A review note could read:
</p>

<blockquote>
<p>
For an authorized 100-cent hold, a local void must retain capacity and
request remote cancellation. P01's invented output passes validity and
effects consistency but fails retention. Repairing retention alone still
leaves the missing effect caught by PO-B3. These checks distinguish the
alternatives on this input; they do not establish remote cancellation or
cover every law.
</p>

</blockquote>

<p>
For executable assertions covering these alternatives, use the existing
<a href="https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/agentic_verification.md#3-try-to-break-the-contract">contract challenge</a>.
</p>

</details>

## 6. Keep the money, omit the cancellation request (P02)

Use the same authorized 100-cent hold and cancellation event.

**Proposed outcome:** mark the entry `voiding` and retain both counters,
but return an empty list of effects.

Is reserving the money enough to satisfy the whole transition requirement?

<details>
<summary>Answer: the requested outside work is part of the result</summary>

<p>
Retaining capacity addresses the immediate exposure concern. The transition
must also request the remote void. An empty effects list omits that work.
</p>

<p>
A result has three parts: next state, result value and effects. Checking only
one part can miss a defect in another. Compare the original
<a href="https://github.com/nshkrdotcom/hold_ledger/blob/main/test/laws/po_b3_test.exs">effects law</a> with the retention and validity
requirements instead of treating any one as a complete policy description.
</p>

<p>
Emitting the required effect would still not prove delivery or eventual
cancellation. Those require separate runtime and processor evidence.
</p>

</details>

## 7. Send the cancellation, release too early (P05)

Again start with an authorized 100-cent hold.

**Proposed outcome:** return the correct void effect, but mark the hold
`voided` and immediately free its capacity.

Does the effect fix P01?

<details>
<summary>Answer: requesting cancellation does not establish completion</summary>

<p>
Adding the effect repairs the missing cancellation request. The processor
still needs to receive and apply it, then confirm that the key can no
longer authorize a hold, even if an old request arrives late.
</p>

<p>
Until that trusted confirmation, the entry remains <code>voiding</code> and counted.
Compare P01, P02 and P05: which outcomes retain capacity, and which request
the required cancellation?
</p>

<p>
The real processor's truthfulness and permanent fencing remain assumptions
that a proof of the pure model cannot establish.
</p>

</details>

## 8. A timeout touches an unrelated hold (P07)

The account limit is 250 cents with three slots:

| Key | Amount | Status |
|---|---:|---|
| 1 | 50 | authorized |
| 2 | 100 | sent |

Used totals are 150 cents and two slots.

**Event:** timeout for key 2.

**Proposed outcome:** mark key 2 `unknown`, but also mark key 1 `voided`.
Reduce the totals to 100 cents and one slot.

The new totals match the proposed entries. What is still wrong?

<details>
<summary>Answer: the event does not justify releasing another identity</summary>

<p>
Only the sent hold's status should change. Key 1 stays authorized for 50 cents;
key 2 becomes unknown for 100 cents. Both entries remain counted, giving
150 cents and two slots.
</p>

<p>
The alternative is internally consistent but changes an unrelated hold.
Key 1 still exists with its original amount, so identity preservation alone
does not catch its changed status. Retention must protect that entry too.
</p>

<p>
When inspecting a rule's concrete bindings, remember that the protected entry
may have a different key from the event key. Testing only key 2 could miss
what happened to key 1. See the
<a href="https://github.com/nshkrdotcom/hold_ledger/blob/main/test/laws/po_exposure_retain_test.exs">retention law</a> and
<a href="https://github.com/nshkrdotcom/hold_ledger/blob/main/test/laws/po_b6_test.exs">identity law</a>.
</p>

</details>

## Try a case without an answer key

A proposed rule says: “Every cancellation must emit a remote void request and
keep capacity until remote confirmation.” Apply it to P08: a reserved
100-cent hold that has never been dispatched.

1. Write the outcome required by [the event policy](specification.md#events).
2. Does the proposed rule accept that outcome? If you think the outcome is
   acceptable but the rule rejects it, which requirement would you cite?
3. Change the rule's condition so it distinguishes this case from P01.
   Check that your revision still rejects premature release of an authorized hold.
4. Write two sentences recording your judgment and what you have not checked.

This proposal is a teaching example, not a maintained law. You can check your
reasoning against the specification and the earlier cases without changing code.

For another kind of review, try [a changed guarantee](reviewing_changed_guarantees.md).
If you are deciding what a report establishes, use
[Reading review evidence](reading_review_evidence.md).
