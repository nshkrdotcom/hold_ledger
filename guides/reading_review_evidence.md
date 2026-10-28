# Reading review evidence

You have read the claim and challenged an unwanted output. Now someone says
the checks passed. What can you record in your review?

Try these report-reading exercises before opening the answers. They apply
the acceptance rules in [Verification](verification.md); use that guide when
you need to run or validate the checks. For practice with the behavior itself,
start with the [payment cases](payment_hold_review_exercises.md).

## 1. An available proof implementation is not a proof run

A catalog lists all required groups as `supported`. No proof report accompanies
the change.

**Question:** may you record full formal acceptance?

<details>
<summary>Answer: support and execution are different evidence</summary>

<p>
<code>Supported</code> means a proof implementation is registered. It does not mean the
current source has completed a proof run.
</p>

<p>
Read the reported scope:
</p>

<ul>
<li>
Not supplied: no matching report was provided.
</li>
<li>
Development only: a proof attempt lacks full export/checker acceptance.
</li>
<li>
Selected checked: matching evidence covers a selected subset.
</li>
<li>
Full catalog checked: the repository's validator accepts matching evidence
for every required obligation.
</li>
<li>
Incomplete, failed or stale: the required acceptance evidence is not present
in an acceptable form for the claimed scope/source.
</li>

</ul>

</details>

## 2. The report is green, but the source changed

A previously accepted report names source hashes and generated export hashes.
A helper changes afterward. The report file itself is untouched.

**Question:** does the unchanged report still certify the changed helper?

<details>
<summary>Answer: match the evidence to the source it actually checked</summary>

<p>
No. The report belongs to its recorded source and export identity. Keeping
the report bytes does not extend its scope to a different program or claim.
</p>

<p>
You can cite the old result as historical evidence for the old source. To
claim fresh acceptance for the changed source, run the required proofs and
export checks. Revalidating an old report does not run them again.
</p>

</details>

## 3. “All six checkers passed”

A report records Lean default, Lean paranoid, lean4lean, nanoda, con-leche and
con-ron. All six records acknowledge the export. Its axiom list contains only
`propext`, `Quot.sound` and `Classical.choice`.

**Question:** what remains to be checked before relying on this report?

<details>
<summary>Answer: scope, provenance, permitted axioms and meaning still matter</summary>

<p>
Check that the report covers every required obligation, identifies the reviewed
source, lockfile and toolchain, and matches the exported proof hashes. Then
apply the repository's acceptance rules. Six success fields alone do not
establish acceptance.
</p>

<p>
These are six checker configurations. Default and paranoid are configurations
of Lean, not two independent kernel implementations. The other checkers add
implementation diversity.
</p>

<p>
The repository permits the three listed axioms. Check for missing dependencies
and unapproved axioms too. Searching for
<code>sorry</code> or <code>unsafe</code> cannot establish that the exported dependencies passed
the required checks.
</p>

<p>
Finally, a sound proof of the wrong statement still leaves the requirement
unprotected. Read what the theorem and its dependencies actually mean.
</p>

</details>

## 4. One export appears under every law

A full-suite report reuses the same export and axiom list in many law rows.
Someone describes that list as the exact axiom footprint of each theorem.

**Question:** is that scope justified?

<details>
<summary>Answer: a shared suite list is not a theorem-specific audit</summary>

<p>
The artifact may establish facts about the combined suite. Displaying it under
a law does not make its dependency list specific to that theorem.
</p>

<p>
Even an export shown in just one row needs metadata identifying which
theorems it covers. If the report omits a theorem's statement or dependencies,
record the omission. A similar historical report cannot supply those facts
for the current source.
</p>

</details>

## 5. The outside-world promise

A model assumes the processor deduplicates authorization requests and
permanently fences a cancelled identity against delayed authorization.
A reviewer checks a box saying the integration supports this.

**Question:** did the click prove the processor's behavior? Is a deployment
assumption the same thing as an arbitrary Lean axiom?

<details>
<summary>Answer: record evidence for each assumption at its actual boundary</summary>

<p>
The click is an attestation, not a remote-service proof. Relevant evidence
could include the processor contract, retention/fencing guarantees, adapter
behavior and failure tests. Merely declaring a capability does not establish
that the service honors it across delayed delivery or restart.
</p>

<p>
A documented assumption about a processor still needs evidence from the
integration. It does not authorize adding an axiom to make a proof pass.
The repository forbids custom axioms and proof admissions.
</p>

<p>
The same applies to durability: a pure transition does not establish a disk
flush. Follow the runtime's journal ordering and storage assumptions separately.
If the evidence is absent, record what is missing rather than choosing an
unsupported yes/no verdict about the real service.
</p>

</details>

## 6. The proof timed out

A required proof attempt times out. Its ordinary witness test passes, and
no counterexample has been found. A reviewer writes, “The law is false;
we should narrow its precondition.”

What evidence supports that conclusion?

<details>
<summary>Compare your answer</summary>

<p>
None of these results establishes that the law is false. The test covers its
executed case; the proof attempt did not finish. Keep the claim unresolved
and investigate the goal and relevant property. A counterexample would need
to satisfy the current precondition and violate its conclusion.
</p>

<p>
Narrowing the precondition could discard required cases. Review any such
proposal against policy separately from the failed proof attempt.
</p>

</details>

## Write the conclusion

Choose one exercise and write a review note naming the source and claim,
what evidence is available, what it establishes, and what remains missing.
For unresolved work, name who should do what next. If a matching report is
absent, say so; an explanation of the intended proof cannot replace it.

[Human review](human_review.md#what-to-inspect-in-the-agent-report) provides
the report fields used for repository changes.
