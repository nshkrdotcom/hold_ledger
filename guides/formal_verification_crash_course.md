# Formal Verification Crash Course: From Tests to Proofs

Imagine a small Elixir function that decides whether a request fits within a ledger's remaining capacity:

```elixir
def admit(amount, remaining) do
  if amount > remaining, do: :full, else: :ok
end
```

Someone changes `>` to `>=`. A test asking for 80 of 100 available units still passes, but a request for exactly 100 now fails. Unless the tests include that boundary, the change may look harmless.

Other ledger mistakes are harder to stumble across. A failure might depend on a limit of `18_446_744_073_709_551_615` (`2^64 - 1`), nearly all capacity reserved, and eight entries in one particular order. Ten thousand generated tests might never visit that state. A checked proof offers different evidence: it covers **every modeled input satisfying the stated assumptions**, rather than just a selection of examples.

That assurance is only as useful as the claim being proved. A valid proof can establish a rule that's too narrow, assumes away the bug, or describes a model that differs from the running system. This course is about spotting those mistakes when you review a proof written by a person or an agent.

You'll read one complete Lean proof, run a Lynx contract against Elixir, break it on purpose, and follow a real Hold Ledger theorem through its acceptance checks. You need Elixir and testing experience, but no Lean background. You won't be asked to write proof tactics.

To run the examples, complete [Getting started](getting-started.md), including its pinned Elixir/OTP setup. Run commands from the repository root and save tutorial files under `tmp/` (create it if needed; Git ignores it). `scripts/local_run.py` selects the repository-local toolchain and cache locations. You can also read the course without running it.

## What tests and proofs establish

| Evidence | What you learn | What you still have to check |
|---|---|---|
| Unit test | One chosen execution had the expected result | Did the test include the awkward boundary? |
| Property test | Generated executions satisfied the property | Did the generator reach the important cases? |
| Formal proof | Every modeled input satisfying the hypotheses obeys the claim | Are the hypotheses and claim the ones you meant? |

The three belong together. A theorem about the pure reducer doesn't tell us whether a journal write reached disk or a processor kept a promise. Here's our capacity claim:

> For every two integers, `amount` and `remaining`, if `amount <= remaining`, then `admit(amount, remaining)` returns `:ok`.

The "if" part is the [precondition](#precondition-and-hypothesis): it tells us which inputs the claim covers. The promised result is the [postcondition](#postcondition-and-conclusion). Together they form a contract. Equality is included, as are negative integers; this is a toy rule, not the ledger's business policy.

## Read your first Lean proof

Lean 4 is both a programming language and a theorem prover. In ordinary code, `42` is a value of type `Int`. In Lean, a proposition is also a type, and a proof is a value of that type. This is *propositions as types*, or Curry–Howard.

| In ordinary programming | In a Lean proof |
|---|---|
| A type describes acceptable values | A proposition describes what must be shown |
| An expression has a type | A proof term has the proposition's type |
| A typechecker checks the expression | Lean's [kernel](#kernel-and-proof-term) checks the proof term |

Here is a complete proof, small enough to read without knowing any tactics. Save it as `tmp/first_proof.lean`:

```lean
import Lean

def reserve (used amount : Int) : Int := used + amount

theorem reserve_within_limit :
    ∀ (used amount limit : Int),
      amount ≤ limit - used → reserve used amount ≤ limit := by
  intro used amount limit fits
  unfold reserve
  omega
```

Run it:

```sh
uv run --locked python scripts/local_run.py lean tmp/first_proof.lean
```

A successful check exits with status zero. `reserve` adds to the used capacity. The theorem says that if the amount fits, the new total stays within the limit. Before `:= by` is the **statement**; after it comes the proof. `∀` means "for every." `intro` names the integers and the assumption `fits`, leaving this goal:

```text
used amount limit : Int
fits : amount ≤ limit - used
⊢ reserve used amount ≤ limit
```

Read `⊢` as "now prove this." The facts are above it; the [goal](#goal-and-tactic) is to its right. `unfold reserve` expands the function, and `omega` handles the arithmetic. These tactics build a proof term for the kernel to check. You need to recognize what they do when reading a proof diff, not learn to write them.

### What a Lean statement means

| Lean | English | Reviewer question |
|---|---|---|
| `∀ x : Int, P x` | Every integer `x` has property `P` | What domain does "every" cover? |
| `P → Q` | If `P`, then `Q` | Is the assumption hiding the failure? |
| `P ∧ Q` | `P` and `Q` | Did the conclusion leave something out? |
| `∃ x, P x` | Some `x` has property `P` | Can we name a real example? |
| `x = y` | These expressions are equal | What do their definitions do? |
| `⊢ Q` | `Q` still needs proof | What facts are available? |

Now consider this perfectly valid theorem:

```lean
import Lean

theorem impossible_admission :
    ∀ (amount : Int), amount > 0 ∧ amount ≤ 0 → amount = 42 := by
  intro amount requirements
  rcases requirements with ⟨positive, nonpositive⟩
  omega
```

No integer can satisfy both `amount > 0` and `amount <= 0`. The theorem is **vacuously true**: its precondition describes no real case. Ask for a [witness](#witness-and-counterexample), a concrete input satisfying the assumptions. One witness rules out total vacuity, not an incomplete domain. A law requiring `amount < remaining` could pass while excluding exact fits.

## From Elixir to Lean with Lynx

We aren't rewriting Hold Ledger in Lean. Lynx translates the compiled Elixir through Core Erlang into definitions that Lean can reason about:

```text
Elixir implementation + law
           |
           v
    compiled Core Erlang
           |
           | Lynx translates
           v
 Lean definitions + theorem
           |
           v
      Lean kernel
```

The generated definitions model pure functions, their branches, and exceptions—not the GenServer, journal, or processor. The compiler and translator remain a [trust boundary](#translation-boundary): a proof about translated code doesn't establish that every BEAM execution matches its model.

Here's a complete Lynx example. Save it as `tmp/cap_test.exs`:

```elixir
defmodule CrashCourseTest do
  use ExUnit.Case
  use Lynx.Case
  use ExUnitProperties

  def admit(amount, remaining) do
    if amount > remaining, do: :full, else: :ok
  end

  test "exact fit" do
    assert fits(1, 1)
  end

  property "every generated fitting pair is admitted" do
    check all(remaining <- integer(), gap <- non_negative_integer()) do
      assert fits(remaining - gap, remaining)
    end
  end

  laws "capacity" do
    law(fits(amount, remaining),
      requires: is_integer(amount) and is_integer(remaining) and amount <= remaining,
      expects: admit(amount, remaining) == :ok,
      proof: ~LEAN"""
      cases amount <;>
        simp_all [«fits:requires/2», Erlang.erlang.«is_integer/1», bind, Except.bind]
      cases remaining <;>
        simp_all [«fits:requires/2», Erlang.erlang.«is_integer/1», bind, Except.bind]
      rename_i a b
      have not_over : ¬ b < a := by omega
      simp [«fits:ensures/2», Elixir.CrashCourseTest.«admit/2»,
        Erlang.erlang.«=</2», Erlang.erlang.«>/2», Erlang.erlang.«==/2»,
        bind, Except.bind, Lynx.Term.true, Lynx.Term.false, Int.compare_eq_gt, not_over]
      """
    )
  end
end
```

Begin with the law's `requires:` and `expects:`, not its tactic script. They declare two integers with `amount <= remaining`, promising `admit(amount, remaining) == :ok`. Lynx makes this [law](#law-and-proof-obligation), `fits/2`, callable as an executable contract. The test checks exact fit on every run; the generated property can exercise equality when its gap is zero.

Run the ordinary checks, then the law:

```sh
uv run --locked python scripts/local_run.py mix test tmp/cap_test.exs --exclude laws
LYNX_CACHE=0 LYNX_DEBUG=lean uv run --locked python scripts/local_run.py mix test tmp/cap_test.exs --only laws
```

With the pinned toolchain, the first command should pass one test and one property; the second should check one law. Check the exit status as well as the summary. `LYNX_CACHE=0` forces a fresh proof attempt; `LYNX_DEBUG=lean` saves generated sources under `tmp/CrashCourseTest/laws-capacity/`. The pinned Lynx version translates `admit/2` as follows:

```lean
def «admit/2» (_0 : Lynx.Term) (_1 : Lynx.Term) : Except Lynx.Exception Lynx.Term := do
  let lynxGenerated0 ← Erlang.erlang.«>/2» _0 _1
  (match lynxGenerated0 with
    | Lynx.Term.atom "false" => pure (Lynx.Term.atom "ok")
    | Lynx.Term.atom "true" => pure (Lynx.Term.atom "full")
    | lynxUnmatched0 =>
      Except.error
        (Lynx.Exception.error (Lynx.Term.tuple #[Lynx.Term.atom "case_clause", lynxUnmatched0])))
```

Read it from top to bottom:

- `«admit/2»` quotes a name containing punctuation; `_0` and `_1` are its arguments.
- `Lynx.Term` represents Elixir values. `Lynx.Term.atom "ok"` is `:ok`; `#[...]` is an array representing tuple elements.
- `Except Lynx.Exception Lynx.Term` represents a return value **or a modeled exception**. An `Except.error` is not a proof-checking failure.
- `let ... ←` evaluates the translated `>` operation. `match` selects the `:ok` or `:full` branch; the last branch models an exceptional `case_clause`.

Lynx also generates `fits:requires/2` and `fits:ensures/2`. At the beginning of the proof, the goal looks like this:

```text
amount remaining : Lynx.Term
requires : «fits:requires/2» amount remaining = Except.ok Lynx.Term.true
⊢ «fits:ensures/2» amount remaining = Except.ok Lynx.Term.true
```

The arguments are still general Elixir terms. The proof separates the integer cases, uses the `amount <= remaining` hypothesis, and shows the `>` branch is false. You don't need to reconstruct those tactics to understand why the claim covers exact fits.

### Tactics you'll recognize in a proof diff

| Tactic | What it does here |
|---|---|
| `intro` | Names the variables and assumptions in the first Lean theorem |
| `unfold` | Replaces a function call with its definition |
| `cases` / `rcases` | Splits possible inputs or unpacks a hypothesis |
| `<;>` | Applies the next tactic to every case produced by the preceding one |
| `rename_i` | Gives readable names to values introduced by case splitting |
| `simp` / `simp_all` | Simplifies expressions using definitions and known facts |
| `have` | Establishes an intermediate fact, such as `not_over` |
| `omega` | Proves suitable linear integer arithmetic |
| `exact` | Uses an existing proof or theorem to establish the goal |

## Break the code, keep the law

Copy the working example with `cp tmp/cap_test.exs tmp/cap_mutant_test.exs`. In the copy, rename the module to `CrashCourseMutantTest` and the proof reference to `Elixir.CrashCourseMutantTest.«admit/2»`. Change `amount > remaining` to `amount >= remaining`, **without** changing `requires:` or `expects:`.

Before running it, predict what `fits(1, 1)` will return. Its precondition still holds, but the new branch rejects equality.

```sh
uv run --locked python scripts/local_run.py mix test tmp/cap_mutant_test.exs --exclude laws --seed 12345
LYNX_CACHE=0 LYNX_DEBUG=lean uv run --locked python scripts/local_run.py mix test tmp/cap_mutant_test.exs --only laws
```

The exact-fit test fails. The property can shrink to `remaining = 0`, `gap = 0`: `fits(0, 0)` satisfies the precondition, while the changed function returns `:full`. That's a counterexample. The proof attempt also fails, leaving a goal whose beginning looks like this (the rest of the diagnostic is omitted):

```text
unsolved goals
case integer.integer
a b : Int
requires : a ≤ b
not_over : ¬ b < a
⊢ (match
      match if b ≤ a then Lynx.Term.atom "true" else Lynx.Term.atom "false" with
      | Lynx.Term.atom "false" => Except.ok (Lynx.Term.atom "ok")
      | Lynx.Term.atom "true" => Except.ok (Lynx.Term.atom "full")
```

The facts still permit `a = b`, but `b ≤ a` is true at equality and the changed function returns `:full`. The concrete failure confirms that this claim is false for the changed code. An unsolved goal alone would not.

This deliberately broken copy is a [mutant](#mutant-and-mutation-testing). It tests whether the existing checks notice a fault. Keep `tmp/cap_test.exs` unchanged for the rest of the course.

### Stuck or false?

When an agent reports a failed proof or timeout, use this procedure:

1. Replay a witness or the property's shrunk failure for the **same precondition and conclusion**.
2. Check that `requires` is true and `expects` is false. Only then do you have a behavioral counterexample.
3. Fix faulty implementation behavior, or a genuinely mistaken requirement; keep a regression test. Don't narrow a valid law just to get green.
4. If no counterexample appears, call the claim **unresolved**. Inspect the last goal, generated code and generator coverage. Passing tests don't show the tactic is the only problem.

## Why Hold Ledger has two ways to count

A payment [hold](#hold) consumes capacity while an outcome is pending or an authorization is active. A processor timeout isn't a rejection; freeing that capacity could overbook the ledger. The reducer takes a state and an event, then returns a new state, a result, and effect descriptions:

```text
{amount_limit, hold_limit, used_amount, used_holds, entries}
```

The project keeps two implementations deliberately separate:

```text
HoldLedger.Ledger             HoldLedger.Spec
----------------             ---------------
Applies real transitions     Describes expected behavior
Updates running counters     Recounts entries from scratch
Uses arithmetic deltas       Checks the state independently
Never calls Spec             Never calls Ledger
```

On admission, `Ledger` adds to its running counters; `Spec` independently recomputes totals from the entries. For example, the two calculations must agree on `used_amount == Spec.hold_amount(entries)`. An incorrect timeout delta would make them diverge, even if the entry list looks sensible. `Spec` is an independent [oracle](#oracle), though both sides could still share a mistaken policy.

If a timeout changes `:sent` to `:unknown`, it must retain that capacity. Save this as `tmp/accounting_check.exs`:

```elixir
alias HoldLedger.{Ledger, Spec}
import ExUnit.Assertions

sent = {1000, 3, 300, 1, [{11, 300, :sent}]}
{unknown, :marked_unknown, []} = Ledger.step(sent, {:timeout, 11})

assert unknown == {1000, 3, 300, 1, [{11, 300, :unknown}]}
assert Spec.hold_amount(elem(unknown, 4)) == 300
assert Spec.valid?(unknown)

# Simulate a bug that releases the counters but retains the unknown entry.
broken = {1000, 3, 0, 0, [{11, 300, :unknown}]}
assert Spec.hold_amount(elem(broken, 4)) == 300
refute Spec.valid?(broken)
```

Then run:

```sh
uv run --locked python scripts/local_run.py mix run tmp/accounting_check.exs
```

The real transition reserves 300. The broken state claims zero is used, though its entry accounts for 300, so `Spec.valid?/1` rejects it. That predicate is an [invariant](#invariant-and-preservation): it defines valid state. A preservation law says valid state stays valid after an event. But a reducer that refuses every request could preserve validity by doing nothing. Positive admission needs a separate claim.

The repository has ten deliberate mutants. Two show why the **proof obligation**—the particular claim the project requires—matters:

| Mutant | Concrete input | Correct behavior | Mutated behavior |
|---|---|---|---|
| **M4: exact fit** | `{100, 1, 0, 0, []}`; request key `11`, amount `100` | Admit; reserve `100` and one slot | Reject as `:insufficient_amount`; unchanged state |
| **M2: timeout release** | `{1000, 3, 300, 1, [{11, 300, :sent}]}`; timeout key `11` | Mark `:unknown`; retain `300` and one slot | Keep the entry but reduce counters to zero |

M4 can preserve validity while violating **PO-A2 positive admission**. M2 breaks validity, which **PO-B1/timeout preservation** should detect. Run the unchanged preflight baseline with:

```sh
uv run --locked python scripts/local_run.py mix test test/mutations/preflight_test.exs --exclude laws
```

This command checks the unchanged baseline; it does **not** apply the patches. [Testing](testing.md#deliberate-mutations) explains how to run the mutants themselves.

### Read the duplicate-request law

Open `test/laws/po_a4_duplicate_test.exs`. The PO-A4 duplicate law says: on a valid ledger, if a key is already recorded at the same positive amount, retrying that request returns the original state, `:duplicate`, and no effects.

```elixir
law(po_a4_duplicate(s, key, amount, status),
  requires:
    Spec.valid?(s) and is_integer(key) and is_integer(amount) and amount > 0 and
      Spec.lookup(elem(s, 4), key) == {:ok, {key, amount, status}},
  expects: Ledger.request(s, key, amount) == {s, :duplicate, []},
  proof: ~LEAN"""
  exact Elixir.HoldLedger.ProofContracts.«po_a4_duplicate/4» s key amount status requires
  """
)
```

Its `requires:` demands a valid state, integer key, positive integer amount, and a `Spec.lookup` result with the matching key, amount, **and status**. `expects:` demands `{s, :duplicate, []}`. Nothing restricts the entry to `:reserved`: valid terminal statuses are covered too. Here's a witness for `iex -S mix`:

```elixir
alias HoldLedger.{Ledger, Spec}
s = {1000, 3, 300, 1, [{11, 300, :reserved}]}
true = Spec.valid?(s)
{:ok, {11, 300, :reserved}} = Spec.lookup(elem(s, 4), 11)
{^s, :duplicate, []} = Ledger.request(s, 11, 300)
```

The `exact` line applies a shared theorem in `test/support/lean/Lookup.lean`. Its argument needs two facts. The following are **statement excerpts**, not executable Lean files; the proof bodies are omitted.

```lean
have shaped : ∀ s, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
    ∃ al hl ua uh es, s = Lynx.Term.tuple #[al, hl, ua, uh, es] ∧
      Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true := by
  ...
```

Read it as: every valid state has five tuple fields and a well-formed entry list. Then the lookup-compatibility statement, supported by the argument in `CoreLookup.lean`:

```lean
have compatible : ∀ es k, Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    ∃ v, Elixir.HoldLedger.Ledger.«find/2» es k = Except.ok v ∧
      Elixir.HoldLedger.Spec.«lookup/2» es k = Except.ok v ∧
      (v = Lynx.Term.atom "not_found" ∨ ∃ (ek : Lynx.Term) (n : Int) (st : Lynx.Term),
        v = Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[ek, Lynx.Term.integer n, st]]) := by
  ...
```

`∀ es k` says *for every list and key* satisfying the hypothesis; `∃ v` says *there is a result*; `∧` requires **both** lookups to return that result. The final `∨` covers not found or an entry. Because the law's precondition mentions `Spec.lookup` and the reducer uses `Ledger.find`, this compatibility is essential. The matching amount selects the reducer's duplicate branch, returning `{s, :duplicate, []}`. The [deeper proof guide](reading_deeper_proofs.md#follow-lookup-through-a-list) explains the recursive argument.

You can check this group without running full acceptance:

```sh
uv run --locked python scripts/run_laws.py --slug po_a4_duplicate --stage proofs \
  --report tmp/verification/po_a4-learning.json
```

Here `--slug po_a4_duplicate` selects the duplicate-request [group](#group-and-slug) registered in `verification/laws.json`. This is a focused proof attempt, not full acceptance. As a checkpoint, explain PO-A4's precondition, conclusion and lookup dependency without looking at the tactic bodies.

## Why should you believe a passing proof?

Lean's kernel checks a proof term against its statement and dependencies; it cannot decide whether the statement captures the requirement. Full acceptance adds four safeguards, each answering a different question:

1. **Source scan:** Did someone leave an unchecked shortcut in the proof? `scripts/run_laws.py` rejects `sorry`, `admit`, `axiom`, `unsafe`, and `native_decide` in scanned law and shared Lean sources. An admission or arbitrary custom axiom can make an unproved assertion appear established.
2. **[Axiom audit](#axiom-audit-and-acceptance):** What assumptions does the *exported proof* actually depend on? Source scanning alone may miss assumptions brought in through dependencies. Full acceptance permits only `propext`, `Quot.sound`, and `Classical.choice`; the placeholder dependency `sorryAx` is forbidden.
3. **Six checker configurations:** Would another checker accept the proof object? Lean default, Lean paranoid, lean4lean, nanoda, con-leche, and con-ron check it, reducing reliance on one kernel implementation. Default and paranoid are two modes of Lean, **not** two independent kernels; the other checkers add implementation diversity.
4. **Mutants:** Can the evidence detect a known bad change? Ten deliberate patches exercise ordinary assertions and targeted formal attempts. They help test whether the checks can fail as intended, though a failed tactic alone doesn't establish that a mutant was caught.

A registered group's **full** acceptance command is:

```sh
uv run --locked python scripts/run_laws.py --slug po_a4_duplicate --stage full \
  --report tmp/verification/duplicate.json
```

Direct `mix test` or `--stage proofs` runs do **not** provide the full exported-checker and axiom-audit evidence. Review the report, source revision and proof export; a green summary alone isn't provenance. Even full acceptance leaves questions about shared policy mistakes, translation, journal durability and processor behavior.

Pending voids show the limit. If local capacity were released **before** remote void confirmation, a second hold could be admitted while the first authorization remained live. The ledger retains capacity in `:voiding` until a trusted confirmation releases it and retires the matching obligation. Bounding remote exposure still assumes truthful processor outcomes, stable identities and amounts, deduplication, and no delayed authorization after confirmation. Lean cannot make a processor honor those assumptions; see [Verification](verification.md#added-model-boundaries) and the [audit](audit.md).

## Your first proof review

When an agent says "proof passed," ask for the law and the acceptance report. Read in this order:

1. **The promise:** Can you say what `requires:` and `expects:` mean without Lean? Does the law include exact fits, retries, terminal states, and other relevant boundaries?
2. **A witness:** Can the precondition actually hold? Is the troublesome input still in its domain?
3. **The oracle:** Does `Spec` independently decide the expected result, or does it merely echo the reducer?
4. **The evidence:** Was this a local proof attempt or full acceptance? Which source, proof export, axiom audit, checker results, and relevant mutants back it?
5. **The boundary:** What does this theorem leave to the compiler, translator, runtime, disk, or processor?

### Reading exercises

**1. A too-easy law.** An agent proposes this contract:

```elixir
requires: is_integer(amount) and is_integer(remaining) and amount < remaining,
expects: admit(amount, remaining) == :ok,
```

What case did it remove? Could the new law still have a valid proof?

**2. An impressive but empty theorem.** An agent proves that `amount > 0 and amount <= 0` implies admission. What witness would show the law applies to a real request?

**3. An unsolved goal.** A proof times out and all the ordinary tests pass. What have you learned about the claim, and what would you inspect next?

**4. The duplicate guarantee.** An agent changes PO-A4's `expects:` to require only that the resulting state is valid. Would that preserve the promise to return `:duplicate`, unchanged state and no effects?

<details>
<summary>Solutions — open after trying the questions</summary>

1. Equality disappeared; a narrower law could still be proved.
2. None exists; its precondition is contradictory.
3. The claim remains unresolved. Inspect the goal and try to replay a counterexample satisfying `requires` and falsifying `expects`.
4. No. A different result, changed state or extra effects might still leave a valid state.

</details>

For the next step, [Human review](human_review.md#use-mutations-to-challenge-claims) shows how to challenge agent claims with mutants, and [Agentic verification](agentic_verification.md) covers contract review. [Verification](verification.md) and [Architecture](architecture.md) cover acceptance evidence and runtime boundaries.

## Reference: glossary

The terms below are also explained where you first need them. Each heading is a normal Markdown link target, so you can follow an inline link here and return to your place in the course.

### Law and proof obligation

A **law** is a Lynx contract declared with `law`. A **proof obligation** is a required claim, including Lean-only theorems. `PO-A2` and `PO-A4` name obligations, not individual test runs.

### Group and slug

A **group** is a selectable verification unit that can contain several theorems. Its **slug** (such as `po_a4_duplicate`) is passed to `--slug`. `verification/laws.json` registers groups, while `verification/obligations.json` inventories the required claims.

### Precondition and hypothesis

A **precondition** says when a contract applies (`requires:`). A **hypothesis** is a fact available inside a Lean proof. Narrowing them can silently exclude the inputs you needed to cover.

### Postcondition and conclusion

A **postcondition** is what the contract promises (`expects:`). A theorem's **conclusion** is the claim it must establish; that conclusion can omit behavior the system actually needs.

### Contract

A **contract** joins a precondition and a postcondition: whenever the former holds, the latter must follow. Read it before judging the proof script.

### Witness and counterexample

A **witness** is an input satisfying a precondition. A **counterexample** also makes the conclusion false. A single witness shows a precondition isn't completely empty, but doesn't establish that every intended case is covered.

### Goal and tactic

A **goal** is what Lean still needs to establish, shown after `⊢`. A **tactic** builds part of a proof. An unsolved goal does not, by itself, mean the claim is false.

### Kernel and proof term

A **proof term** is a value of a proposition's type. Lean's **kernel** checks that it has the claimed type under the definitions and axioms it depends on.

### Invariant and preservation

An **invariant** describes a valid state. **Preservation** means that applying an event to valid state produces another valid state; it does not promise that an eligible request was admitted.

### Oracle

An **oracle** is an independently written description of expected behavior. `Spec` recomputes totals without calling `Ledger`; independence still cannot correct a policy both implementations misunderstand.

### Hold

A **hold** is reserved capacity while a processor result is pending or an authorization remains active. Entries in `:unknown` or `:voiding` may still consume capacity.

### Mutant and mutation testing

A **mutant** is a disposable copy of a program containing a deliberate change. **Mutation testing** checks whether existing tests or proof attempts notice the fault.

### Axiom audit and acceptance

An **axiom** is an assumption permitted by a proof's foundations. The **axiom audit** restricts exported dependencies; **full acceptance** additionally checks the exported proof objects with multiple checker configurations.

### Translation boundary

The **translation boundary** is the assumed correspondence between compiled Core Erlang and the Lean definitions Lynx generates. A proof about the generated definitions does not, by itself, establish correctness of runtime IO.

A checked Lean proof tells you that the claim follows from its definitions and permitted assumptions. **Deciding whether that is the claim your system needs is the reviewer's job.**
