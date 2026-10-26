# Formal Verification Crash Course: From Tests to Proofs

Changing `>` to `>=` can reject a request that exactly fits the available capacity. A test with spare capacity still passes. A generated test catches the bug only if it exercises equality. A proof of “every fitting request is admitted” must cover equality too.

This guide assumes you know Elixir and property tests. You will run a complete Lynx proof, read its generated Lean, then apply it to Hold Ledger. Complete the [toolchain setup](getting-started.md) first. Save the examples under ignored `tmp/`.

## Terms You Will Need

| Term | Meaning here |
|---|---|
| Law / obligation | A law is an executable claim declared with `law`; an obligation is a claim the project requires checked, including Lean-only theorems. `PO-*` labels identify obligations. |
| Group / catalog entry | A group is a unit selected for verification and may contain multiple theorems. `verification/laws.json` registers each group; `verification/obligations.json` records the required inventory. |
| Precondition / hypothesis | An assumption under which the claim must hold; Lynx writes the precondition as `requires:`. |
| Contract | The precondition and postcondition together: `requires:` and `expects:`. |
| Conclusion / postcondition | What must follow from those assumptions; Lynx writes it as `expects:`. |
| Witness / counterexample | A witness satisfies the precondition; a counterexample also makes the conclusion false. |
| Invariant / preservation | An invariant describes valid state; preservation means an operation keeps valid input state valid. |
| Goal / tactic | A goal is a claim still to prove; a tactic is a Lean instruction that builds part of a proof. |
| Kernel | Lean's small proof checker, which checks the proof term produced by tactics. |
| Oracle | An independently written reference for expected behavior; here, `HoldLedger.Spec`. |
| Hold | Reserved payment capacity while a processor outcome is pending or an authorization remains active. |
| Mutant | A disposable copy of code with a deliberate change, used to test whether checks detect a fault. |

## Run One Complete Lynx Proof

The toy function checks capacity using two integers, including negative values. Its claim is: for every integer pair where `amount <= remaining`, `admit/2` returns `:ok`.

Create `tmp/` if necessary. Save this entire file as `tmp/cap_test.exs`:

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

Run the ordinary checks, then the proof:

```sh
uv run --locked python scripts/local_run.py mix test tmp/cap_test.exs --exclude laws
LYNX_CACHE=0 LYNX_DEBUG=lean uv run --locked python scripts/local_run.py mix test tmp/cap_test.exs --only laws
```

The first command passes one test and one property; the second passes one law. Lynx makes `fits/2` callable in Elixir: it checks `requires`, then `expects`, raising if either fails.

The property generates fitting pairs by subtracting a nonnegative gap from `remaining`; gap zero exercises exact fit. These are bounded executions. The proof covers every integer pair satisfying the precondition.

Lynx translates compiled Elixir through Core Erlang, the compiler's intermediate program representation, into Lean. `LYNX_DEBUG=lean` writes the generated sources under `tmp/CrashCourseTest/laws-capacity/`. This is the complete generated `admit/2` definition from `Elixir/CrashCourseTest.lean`, verbatim for the pinned Lynx version:

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

- `«admit/2»` quotes a name containing punctuation. `_0` and `_1` are the original arguments. `Lynx.Term` represents Elixir values, including integers and atoms.
- `Except Lynx.Exception Lynx.Term` means the computation returns either a value or an exception. `do` sequences those computations.
- `let ... ←` evaluates Erlang's `>` comparison and passes on any exception.
- `match` selects the translated `if` branch. Elixir atoms become `Lynx.Term.atom`; `pure` returns a successful result.
- The final branch models a `case_clause` exception. `#[...]` is a Lean array holding the tuple's elements.

The proof entries `bind` and `Except.bind` unfold the `do` block's result handling. The law's `<=` becomes Erlang's `«=</2»`. Lynx generates `fits:requires/2` and `fits:ensures/2` for the two predicates. Read those definitions in the same generated file; the theorem and its complete proof are in `Elixir/CrashCourseTest/laws.lean`.

## Read the Goal Before Choosing a Tactic

At the start of the proof, Lynx supplies this context:

```text
amount remaining : Lynx.Term
requires : «fits:requires/2» amount remaining = Except.ok Lynx.Term.true
⊢ «fits:ensures/2» amount remaining = Except.ok Lynx.Term.true
```

Above `⊢` are available facts; after it is the claim still to prove. `Except.ok Lynx.Term.true` means the predicate returned Elixir `true` successfully. Try replacing the proof with `trace_state` followed by `rfl`: checking fails because the two sides do not compute to the same expression without using the hypothesis.

Restore the complete proof. Its first two commands use `cases` to split each argument by term constructor: an integer, atom, list cell, or other kind of value. `<;>` applies the following tactic to every resulting goal. `simp_all` rewrites the goals and hypotheses using the listed definitions and Lean's standard simplification rules. The integer preconditions eliminate the noninteger branches. `rename_i a b` gives the remaining integer variables readable names. The context is then:

```text
case integer.integer
a b : Int
requires : a ≤ b
⊢ «fits:ensures/2» (Lynx.Term.integer a) (Lynx.Term.integer b) = Except.ok (Lynx.Term.atom "true")
```

Now the problem is recognizable: `a` fits within `b`. `have not_over` names the fact that `b < a` is false; `omega` proves it from `a ≤ b`. The final `simp` unfolds the expected result and function, rewrites integer comparison using `Int.compare_eq_gt`, and selects the `:ok` branch using `not_over`.

The working loop is: read the hypotheses, read the goal, choose one transformation, then inspect what remains.

| Tool | When to use it |
|---|---|
| `trace_state` | Print the current hypotheses and goal inside a proof. |
| `simp only [definitions] at requires` | Unfold selected definitions in the hypothesis without the full simplification rule set. |
| `simp?` / `exact?` | Ask for a simplification or proof suggestion; inspect and replace it with the suggested explicit tactic. |
| `cases value` / `intro name` | Split a value by constructor / introduce a variable or hypothesis when the goal asks for one. Lynx already supplies `requires`. |
| `omega` | Solve linear integer constraints. Products of two unknowns need other reasoning. |
| `LYNX_DEBUG=lean` | Keep generated sources and print translation/proof diagnostics; `LYNX_CACHE=0` forces a fresh attempt. |

For example, `omega` alone fails on `(x : Int)`, goal `x * x ≥ 0`. Its diagnostic treats `x * x` as an independent quantity that might be negative. That is a limitation of the tactic's arithmetic model, not an integer counterexample.

A `simp_all made no progress` diagnostic means its rules did not rewrite the current problem. If simplification instead expands too much code or takes too long, return to the last readable goal. Use `simp only` with selected definitions, or prove a helper fact (a **lemma**) first.

## Stuck or False?

When a proof fails:

1. Run the ordinary witness and property for the **same precondition and conclusion**. The toy file already calls `fits/2` from both, so both checks execute the declared contract.
2. If a property finds a failure, replay the printed values. Check that `requires` is true and `expects` is false. A failure in the generator, translation or tool setup is a different problem.
3. Resolve the counterexample against the intended contract. Fix an implementation error, or correct a mistaken proposed claim. Keep a regression example. Do not restrict a maintained law's inputs just to obtain a pass.
4. If no counterexample appears, the claim remains unresolved. Check generator coverage and continue from the proof state. A passing sample does not establish that only the proof script is wrong.

A timeout needs the same care: inspect the last goal and reduce the proof workload before drawing conclusions about behavior.

## Plant a Bug and Watch the Checks

Copy `tmp/cap_test.exs` to `tmp/cap_mutant_test.exs`. Rename its module to `CrashCourseMutantTest` and change the proof reference `Elixir.CrashCourseTest.«admit/2»` to `Elixir.CrashCourseMutantTest.«admit/2»`. This keeps its generated sources under a separate `tmp/CrashCourseMutantTest/laws-capacity/` directory. Then change the implementation's `amount > remaining` to `amount >= remaining`. This is a **mutation**; the changed copy is the **mutant**. Run:

```sh
uv run --locked python scripts/local_run.py mix test tmp/cap_mutant_test.exs --exclude laws --seed 12345
```

`fits(1, 1)` fails. The property shrinks its failure to `remaining = 0`, `gap = 0`: equality is rejected. The precondition holds while `admit(0, 0)` returns `:full`.

Run the proof command with `tmp/cap_mutant_test.exs` as its path. The original proof no longer closes; the executable equality case already explains why the claim is false. Restore `>` and rerun both checks. This is mutation testing: checking whether deliberately planted faults are detected. An undetected change needs investigation; it may preserve behavior, expose missing coverage, or reflect an incomplete run.

Hold Ledger has ten mutation patches under `mutants/`. Two show why the statement matters:

| Case | Concrete input | Correct behavior | Mutated behavior |
|---|---|---|---|
| M4: exact fit | `{100, 1, 0, 0, []}`, request key `11`, amount `100` | Admit; reserve `100` and one slot | Reject as `:insufficient_amount`; state stays unchanged |
| M2: timeout release | `{1000, 3, 300, 1, [{11, 300, :sent}]}`, timeout key `11` | Change `:sent` to `:unknown`; retain `300` and one slot | Keep the unknown entry but reduce counters to zero |

M4 still preserves the state invariant: a valid unchanged state remains valid. The positive-admission claim PO-A2 is needed to require acceptance. M2 breaks validity because `:unknown` still consumes capacity; PO-B1/timeout requires preservation.

The concrete tests live in `test/mutations/preflight_test.exs`; run their unchanged baseline with:

```sh
uv run --locked python scripts/local_run.py mix test test/mutations/preflight_test.exs --exclude laws
```

The [Testing guide](testing.md#deliberate-mutations) describes the optional expensive experiment that applies the patches in isolated copies. Its formal results require a checked baseline; a tactic failure alone does not attribute detection to a law.

## Apply the Workflow to the Ledger

The ledger is a **reducer**: given state and an event, it returns the next state, a result, and effect descriptions. `Ledger` updates running counters; `Spec` recomputes totals from entries and describes expected behavior independently. Neither calls the other. This can catch accounting drift, though both could still encode the same mistaken policy.

PO-A4/duplicate says that reusing a recorded key at its original positive amount returns the same state, `:duplicate`, and no effects. Read `test/laws/po_a4_duplicate_test.exs` before its proof. Its precondition requires a valid state, integer key, positive integer amount, and a matching entry found by `Spec.lookup/2`. A concrete witness is:

```elixir
alias HoldLedger.{Ledger, Spec}
s = {1000, 3, 300, 1, [{11, 300, :reserved}]}
true = Spec.valid?(s)
{:ok, {11, 300, :reserved}} = Spec.lookup(elem(s, 4), 11)
{^s, :duplicate, []} = Ledger.request(s, 11, 300)
```

An impossible precondition makes a claim **vacuously true**: it has no cases to satisfy. This complete Lean example proves an arbitrary conclusion from contradictory assumptions:

```lean
import Lean
example (amount : Int) (positive : amount > 0) (nonpositive : amount ≤ 0) : amount = 42 := by
  omega
```

No integer satisfies both hypotheses. The proof establishes nothing about any actual admission. One witness rules out an entirely impossible precondition; it does not establish that every intended case is included.

The [shared proof theory reference](verification.md#shared-proof-theory) maps the duplicate law to its lookup lemmas and generated contracts.

## Exercises and Solutions

1. **Boundary witness.** Add an exact-fit test for an integer larger than `2 ** 64`. Does the toy claim allow negative integers too?
2. **Mutation.** Make the comparison change above. Run both ordinary checks and the proof. Explain the smallest executable failure, then restore the function.
3. **Another law.** Keep `fits/2` unchanged. Add `over_capacity/2` requiring integer inputs and `remaining < amount`, concluding `admit(amount, remaining) == :full`. Add a witness and generated property, then prove it.

<details>
<summary>Solutions — open after completing the exercises</summary>

For exercise 1, `assert fits(10 ** 30, 10 ** 30)` and `assert fits(-1, -1)` both pass. Elixir integers are arbitrary precision. Real hold amounts must be positive; the toy function has no such rule.

For exercise 2, `fits(0, 0)` has a true precondition and a false conclusion under `>=`. Restoring `>` repairs that violation.

For exercise 3, add this complete declaration inside the existing `laws "capacity"` block:

```elixir
law(over_capacity(amount, remaining),
  requires: is_integer(amount) and is_integer(remaining) and remaining < amount,
  expects: admit(amount, remaining) == :full,
  proof: ~LEAN"""
  cases amount <;>
    simp_all [«over_capacity:requires/2», Erlang.erlang.«is_integer/1», bind, Except.bind]
  cases remaining <;>
    simp_all [«over_capacity:requires/2», Erlang.erlang.«is_integer/1», bind, Except.bind]
  rename_i a b
  have over : b < a := by omega
  simp [«over_capacity:ensures/2», Elixir.CrashCourseTest.«admit/2»,
    Erlang.erlang.«=</2», Erlang.erlang.«>/2», Erlang.erlang.«==/2»,
    bind, Except.bind, Lynx.Term.true, Lynx.Term.false, Int.compare_eq_gt, over]
  """
)
```

Use `assert over_capacity(2, 1)` as the witness. For the property, generate `remaining <- integer()` and `gap <- positive_integer()`, then assert `over_capacity(remaining + gap, remaining)`. Run the ordinary and proof commands again; there are now two laws.

</details>

## Review the Statement, Then Its Evidence

Before reading a proof body, review these four things in order:

1. **Statement:** do `requires` and `expects` express the intended behavior, including boundaries and rejected cases?
2. **Witness:** can the assumptions hold, and do they include the intended operating cases?
3. **Independence:** does `Spec` make its own decisions, or merely repeat or call the implementation?
4. **Translation boundary:** are the proof's definitions generated from the code being reviewed, and what compiler/translator behavior is being trusted?

Read the helper lemmas and proof body when you need to trace the argument. Next, use [Verify the behavior you meant](agentic_verification.md) to challenge agent-drafted contracts.

> **Limits.** A checked proof establishes its statement about the translated functions under its hypotheses.
>
> The compiler and translator remain trusted. Runtime, storage and processor behavior need separate evidence. Tutorial proof attempts do not run the full acceptance pipeline; see [Verification](verification.md) for those checks and assumptions.
