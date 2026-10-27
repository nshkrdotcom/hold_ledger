# Formal verification crash course: from tests to proofs

You know how to test Elixir. What changes when you want to show that a behavior holds for **every** input in a stated domain, rather than the examples a test runner happens to try?

Start with a capacity check in Elixir. You'll prove a claim about one fixed call, extend it to every integer pair that fits, and see what breaks when you change `>` to `>=`. Then you'll write a law for requests over capacity and follow a maintained ledger proof. You need Elixir and testing experience, but no Lean.

You'll write proof tactics, not only read them. When a proof fails, don't weaken the law just to make Lean accept it.

The explanation can be read on any machine. To run the commands, use the [toolchain setup](getting-started.md) and save tutorial files under a `tmp/` directory at the repository root (create it if needed). Git ignores `tmp/`. All example commands assume you're in the repository root.

You can stop after the first law, after the capacity exercise or after the maintained ledger proof.

## From a test to a claim about every input

We’ll use a function that decides whether a requested amount fits within the remaining capacity:

```elixir
def admit(amount, remaining) do
  if amount > remaining, do: :full, else: :ok
end
```

An ordinary test might assert `admit(3, 10) == :ok`. That checks one request with room to spare. Another test, `admit(10, 10) == :ok`, checks an exact fit. If we accidentally change `>` to `>=`, the first test still passes and the second catches the bug.

A property test lets us describe a whole family of fitting requests. Generate an integer `remaining` and a nonnegative `gap`, then request `remaining - gap`. Every generated request should return `:ok`. When the generator chooses a gap of zero, the request is an exact fit; positive gaps leave room to spare. A separate exact-fit test ensures that boundary is checked on every run.

The property describes what we want generally, but a test run only tries the values it generates. A proof addresses the general statement:

> For every pair of integers `amount` and `remaining`, if `amount <= remaining`, then `admit(amount, remaining)` returns `:ok`.

The “if” part is the **precondition**: the inputs under which the promise applies. The promised result is the **postcondition**. Together they form a **contract**. Lynx calls an executable claim like this a **law**, written with `requires:` and `expects:`.

The capacity test, property and proof will use this general law. It covers exact fits and integers too large for a machine word. It also permits negative values, because we have not required positive amounts. Before proving it, we’ll look at how Lean checks a proof and try a Lynx law for one fixed call.

## What Lean checks

Lean is a programming language and a theorem prover. A theorem declaration names a claim and supplies its proof. Here is a complete example:

```lean
import Lean

theorem add_zero (x : Int) : x + 0 = x := by
  omega
```

`(x : Int)` introduces an arbitrary integer. The statement after the next colon is `x + 0 = x`; it must hold for every `x`. After `:= by` comes the proof. Here, `omega` constructs the proof using integer arithmetic. It does not try a collection of values for `x`.

An ordinary typechecker checks that an expression has the type you declared. Lean can also treat a proposition as a type and a proof as a value of that type. Its small **kernel** checks that the proof has the claimed type. A **tactic**, such as `omega`, helps construct that proof; the kernel checks the result.

The commands below use `local_run.py` to select the repository-local Lean toolchain and cache locations. Elixir and OTP must already match the pinned versions. If you have set the toolchain environment as shown in [Getting started](getting-started.md#environment), you can run `lean` or `mix` directly.

To try it, save the complete block as `tmp/first_proof.lean` and run:

```sh
uv run --locked python scripts/local_run.py lean tmp/first_proof.lean
```

Success produces no output and exits with status zero. Changing the statement to `x + 1 = x` makes the proof fail. Restore it before continuing.

## Learn to read the claim before its proof

Read the theorem statement before the tactics. The proof can be valid even if the statement leaves out the case you meant to cover or assumes the result you wanted.

Lean often writes a universal claim by binding a variable: `theorem add_zero (x : Int) ...` means the theorem holds for **every** integer `x`. These notations will turn up again when you open the ledger's shared proofs:

| Lean notation | How to read it | The question to ask |
|---|---|---|
| `∀ x : Int, P x` | For every integer `x`, `P x` holds | Which inputs does the claim cover? |
| `P → Q` | If `P` holds, `Q` follows | Is `P` an allowed assumption or the outcome we needed to prove? |
| `P ∧ Q` | Both `P` and `Q` | Did we forget a required part of the outcome? |
| `∃ x, P x` | There is at least one `x` satisfying `P` | Does the witness represent an intended case? |
| `x = y` | These expressions are equal | What definitions are those expressions using? |

For example, the following theorem says that **every** nonnegative integer has a positive successor:

```lean
import Lean

example : ∀ n : Int, 0 ≤ n → n + 1 > 0 := by
  intro n nonnegative
  omega
```

`intro` brings the integer and assumption into scope; `omega` handles the arithmetic. There is nothing special about `nonnegative`: it is just a name for the hypothesis. If we changed `0 ≤ n` to `n > 10`, the proof would still be easy, but the theorem would say less.

A successful command alone does not tell you which assumptions a theorem uses. The [declaration-reading exercise](reading_deeper_proofs.md#inspect-declarations-and-assumptions) shows `def`, `theorem`, admissions and `#print axioms` before you classify a proof diff.

## How Lynx connects Elixir to Lean

Hold Ledger translates a pure core: tuples, lists, integers, atoms, guards and recursive functions. The GenServer, journal writes and processor calls sit outside that core. Their behavior needs runtime checks and explicit external assumptions; see the [architecture](architecture.md).

With Lynx, the function stays in Elixir. You write its law in Elixir too, and supply a Lean proof. Lynx translates the compiled function and the law into definitions Lean can reason about:

```text
Elixir function and law
        |
        v
Core Erlang (the compiler’s intermediate representation)
        |
        | Lynx translates
        v
Lean definitions and a theorem statement
        |
        | the supplied proof must establish that statement
        v
Lean checks the proof
```

Lynx supplies the Lean version of `admit/2`; you write the claim and proof. In a law declaration, `requires:` sets the input domain and `expects:` states the required result. Read those lines before the `~LEAN` proof body.

## A first Lynx law

Start with one exact-fit request to `admit/2`. Save this file as `tmp/first_law_test.exs`:

```elixir
defmodule FirstLynxLawTest do
  use ExUnit.Case
  use Lynx.Case

  def admit(amount, remaining) do
    if amount > remaining, do: :full, else: :ok
  end

  test "exact fit" do
    assert admit(1, 1) == :ok
  end

  laws "first law" do
    law exact_fit,
      expects: admit(1, 1) == :ok,
      proof: ~LEAN"""
      simp [«exact_fit:ensures/0», «admit/2»,
        Erlang.erlang.«>/2», Erlang.erlang.«==/2»]
      """
  end
end
```

Run the test, then check the law:

```sh
uv run --locked python scripts/local_run.py mix test tmp/first_law_test.exs --exclude laws
LYNX_CACHE=0 LYNX_DEBUG=lean uv run --locked python scripts/local_run.py mix test tmp/first_law_test.exs --only laws
```

Both checks cover the single call `admit(1, 1)`. The law has no variables and needs no `requires:` clause. The `simp` tactic unfolds the generated `exact_fit:ensures/0` predicate, `admit/2`, and the comparison and equality operators. With both inputs fixed at `1`, Lean can simplify the result.

Replace the whole `simp [...]` tactic with `trace_state` and rerun the proof. Lean prints the open goal and reports that it hasn't been proved:

```text
⊢ «exact_fit:ensures/0» = Except.ok Lynx.Term.true
```

The symbol `⊢` marks what remains to be proved. `exact_fit:ensures/0` is the translated check `admit(1, 1) == :ok`. `Except.ok Lynx.Term.true` means the check returned `true` without an exception. `trace_state` only displays the goal; it doesn't prove it. Restore `simp [...]` and rerun to finish the proof.

## Prove the capacity contract

Now replace the fixed inputs with variables. The law must cover exact fits as well as amounts below capacity; `amount < remaining` would miss equality. This proof has variables and a precondition, so it takes more than unfolding one call.

The test and property call `fits/2`, which Lynx creates from the law declaration. `requires:` and `expects:` state the contract; `proof: ~LEAN` contains the Lean proof. A `laws` block runs as one ExUnit test. The repository registers its maintained law groups separately for the proof runner.

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

A successful ordinary run reports two passes: one exact-fit test and one generated property. A successful proof run reports one passing law. Check the exit status as well as the summary. Lynx makes `fits/2` callable in Elixir: it checks `requires`, then `expects`, raising if either fails. `non_negative_integer()` can generate zero, so the property can exercise exact fits. The explicit `(1, 1)` test checks that boundary on every run. That pair is also a **witness**: a concrete input satisfying the precondition.

## Read the translated function

The proof uses the translated function, so let’s look at what Lynx produced. `LYNX_DEBUG=lean` writes the generated sources under `tmp/CrashCourseTest/laws-capacity/`. This is the complete generated `admit/2` definition from `Elixir/CrashCourseTest.lean`, verbatim for the pinned Lynx version:

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

The names `bind` and `Except.bind` in the proof let the simplifier unfold the `do` block’s result handling. The law's `<=` becomes Erlang's `«=</2»`. Lynx generates `fits:requires/2` and `fits:ensures/2` for the two predicates. Read those definitions in the same generated file; the theorem and its complete proof are in `Elixir/CrashCourseTest/laws.lean`.

### A small Elixir-to-Lean reading aid

Use this table to recognize forms in the generated example. Check the generated definitions for the pinned Lynx version when details matter.

| You wrote or expect in Elixir | You may see in Lean | What it means |
|---|---|---|
| `:ok` | `Lynx.Term.atom "ok"` | An Elixir atom represented as a term |
| Integer `42` | `Lynx.Term.integer 42` | An integer embedded in a dynamically typed term |
| `{a, b}` | `Lynx.Term.tuple #[a, b]` | A two-element Elixir tuple; `#[...]` is a Lean array |
| `amount > remaining` | `Erlang.erlang.«>/2» amount remaining` | A call to the translated Erlang operator |
| A value returned successfully | `Except.ok value` or `pure value` | Normal evaluation of translated code |
| An exception | `Except.error ...` | The modeled exceptional path, not a proof failure |

The same source can involve native Lean values such as `Int` and `List`, plus `Lynx.Term` values and `Except` results. Keep track of which layer a goal is talking about. In particular, a failed `Except` computation is not the same thing as Lean failing to prove a theorem.

## Read the goal before choosing a tactic

With `LYNX_DEBUG=lean`, the generated theorem is in `tmp/CrashCourseTest/laws-capacity/Elixir/CrashCourseTest/laws.lean`. Its starting goal looks like this:

```text
amount remaining : Lynx.Term
requires : «fits:requires/2» amount remaining = Except.ok Lynx.Term.true
⊢ «fits:ensures/2» amount remaining = Except.ok Lynx.Term.true
```

A **goal** is the statement Lean still needs a proof of. Above `⊢` are available facts, also called **hypotheses**; after it is the goal. `Except.ok Lynx.Term.true` means the predicate returned Elixir `true` successfully. To see this state, replace the proof with `trace_state` followed by `rfl` and rerun the proof command. `trace_state` prints the goal; `rfl` tries to close an equality by reducing both sides to the same expression. It fails here because the proof needs the integer and ordering assumptions.

Try replacing the entire proof body with `omega` and run the same proof command. It fails with:

```text
omega could not prove the goal:
No usable constraints found.
```

The rest of the diagnostic suggests unfolding definitions. The inputs are still `Lynx.Term` values, and the precondition is a translated computation. `omega` needs the integer inequality hidden inside it. This is a failed tactic on a true claim; the unchanged example and property still pass.

Restore the complete proof. It first establishes that both arguments are integers:

1. `cases amount` splits the value into possibilities such as an integer, atom or list cell. This resembles pattern matching. `<;>` runs the following tactic in every resulting branch.
2. `simp_all` rewrites the facts and goal using the listed definitions and Lean’s simplification rules. The precondition says `amount` is an integer, so the other branches are impossible and close.
3. The next `cases` and `simp_all` do the same for `remaining`. `rename_i a b` names the two integer values.

The context is now:

```text
case integer.integer
a b : Int
requires : a ≤ b
⊢ «fits:ensures/2» (Lynx.Term.integer a) (Lynx.Term.integer b) = Except.ok (Lynx.Term.atom "true")
```

Now the problem is recognizable: `a` fits within `b`. `have not_over` names the fact that `b < a` is false; `omega` proves it from `a ≤ b`. The final `simp` unfolds the expected result and function, rewrites integer comparison using `Int.compare_eq_gt`, and selects the `:ok` branch using `not_over`.

At each step, read the available facts and the goal, choose a tactic, then inspect what remains. These tools help:

| Tool | When to use it |
|---|---|
| `trace_state` | Print the current hypotheses and goal inside a proof. |
| `simp only [definitions] at requires` | Unfold selected definitions in the hypothesis without the full simplification rule set. |
| `simp?` / `exact?` | Ask for a simplification or proof suggestion; inspect and replace it with the suggested explicit tactic. |
| `cases value` / `intro name` | Split a value by constructor / introduce a variable or hypothesis when the goal asks for one. Lynx already supplies `requires`. |
| `omega` | Solve linear integer constraints. Products of two unknowns need other reasoning. |
| `LYNX_DEBUG=lean` | Keep generated sources and print translation/proof diagnostics; `LYNX_CACHE=0` forces a fresh attempt. |

For example, `omega` alone fails on `(x : Int)`, goal `x * x ≥ 0`. Its diagnostic treats `x * x` as an independent quantity that might be negative. That is a limitation of the tactic's arithmetic model, not an integer counterexample.

If `simp_all` says it made no progress, none of its rules rewrote the current problem. If simplification instead expands too much code or takes too long, return to the last readable goal. Use `simp only` with selected definitions, or prove a helper fact (a **lemma**) first.

When editing the proof, compare `tmp/cap_test.exs` with the generated `.lean` file and terminal output. Change one tactic, rerun with `LYNX_CACHE=0 LYNX_DEBUG=lean`, and check the new goal. A translation error stops before proof checking; an unsolved goal means the tactics didn't finish. Neither proves the claim false.

## Stuck or false?

A proof attempt can fail because the claim is false or because the tactics have not established it. Use the tests to investigate:

1. Run the ordinary witness and property for the **same precondition and conclusion**. The toy file already calls `fits/2` from both, so both checks execute the declared contract.
2. If a property finds a failure, replay the printed values. This is a **counterexample** if `requires` is true and `expects` is false. A failure in the generator, translation or tool setup is a different problem.
3. Resolve the counterexample against the intended contract. Fix an implementation error, or correct a mistaken proposed claim. Keep a regression example. Do not restrict a maintained law's inputs just to obtain a pass.
4. If no counterexample appears, the claim remains unresolved. Check generator coverage and continue from the proof state. A passing sample does not establish that only the proof script is wrong.

A timeout needs the same care: inspect the last goal and reduce the proof workload before drawing conclusions about behavior.

## Plant a bug and watch the checks

Now change the function while keeping its law fixed. The deliberate bug is a **mutation**; the copy containing it is the **mutant**.

Copy `tmp/cap_test.exs` to `tmp/cap_mutant_test.exs`. Rename its module to `CrashCourseMutantTest` and the proof reference to `Elixir.CrashCourseMutantTest.«admit/2»`, so its generated sources have their own directory. Change `amount > remaining` to `amount >= remaining`.

Before running the checks, consider `fits(1, 1)`: its precondition still holds, but what will `admit/2` return? Run:

```sh
uv run --locked python scripts/local_run.py mix test tmp/cap_mutant_test.exs --exclude laws --seed 12345
```

`fits(1, 1)` fails. The property can shrink to `remaining = 0`, `gap = 0`: equality is rejected. The precondition holds while `admit(0, 0)` returns `:full`.

Run the proof command with `tmp/cap_mutant_test.exs` as its path. It reports `proof for law fits(amount, remaining) failed`. The unsolved goal begins:

```text
unsolved goals
case integer.integer
a b : Int
requires : a ≤ b
not_over : ¬b < a
⊢ (match
      match if b ≤ a then Lynx.Term.atom "true" else Lynx.Term.atom "false" with
      | Lynx.Term.atom "false" => Except.ok (Lynx.Term.atom "ok")
      | Lynx.Term.atom "true" => Except.ok (Lynx.Term.atom "full")
```

This is the start of the diagnostic; the remaining lines handle exceptions and compare the result with `:ok`. Read the facts before the nested matches. `requires` still permits `a = b`, but the changed branch tests `b ≤ a` and returns `:full` at equality. The concrete failure `fits(0, 0)` confirms that the claim is false for the mutant. A different unsolved goal without such a witness would leave the claim unresolved.

This is mutation testing: checking whether deliberately planted faults are detected. If a mutation survives, inspect whether it preserves behavior, exposes missing coverage, or reflects an incomplete run.

The mutation is confined to `tmp/cap_mutant_test.exs`. Continue in `tmp/cap_test.exs`, which still has the original `>` comparison.

## Write a law yourself

Write a law for this requirement:

> For any two integers, if the requested amount exceeds the remaining capacity, `admit/2` returns `:full`.

Name it `over_capacity(amount, remaining)` and draft its `requires:` and `expects:` clauses inside the existing `laws "capacity"` block in `tmp/cap_test.exs`. Allow negative integers too, as the earlier law does. The pair `(2, 1)` should satisfy your precondition. The exact fit `(1, 1)` should fall outside it.

Write your clauses before reading on, then compare them with this declaration:

```elixir
law over_capacity(amount, remaining),
  requires: is_integer(amount) and is_integer(remaining) and remaining < amount,
  expects: admit(amount, remaining) == :full,
  proof: ~LEAN"""
  trace_state
  rfl
  """
```

After comparing the claims, start the proof with `trace_state` followed by `rfl`. This prints the goal and then fails, leaving you to fill in the proof. Keep `requires:` and `expects:` fixed as you work. The `fits/2` proof can guide you: after splitting the inputs into integer cases, you'll have a hypothesis `b < a` instead of `a ≤ b`.

Add a witness and a property to the same test module, outside `laws "capacity"`:

```elixir
test "over capacity" do
  assert over_capacity(2, 1)
end

property "generated over-capacity pairs" do
  check all(remaining <- integer(), gap <- positive_integer()) do
    assert over_capacity(remaining + gap, remaining)
  end
end
```

Run the earlier test and proof commands for `tmp/cap_test.exs`. If you get stuck, print the next goal before looking at the [exercise 3 solution](#exercises-and-solutions). Finish this law before moving to the ledger.

## Apply the workflow to the ledger

A payment **hold** reserves capacity while the processor outcome is pending or an authorization remains active. A timeout does not establish that the processor rejected it, so the ledger must keep that capacity reserved.

The ledger is a **reducer**: given state and an event, it returns the next state, a result and effect descriptions. Its state is `{amount_limit, hold_limit, used_amount, used_holds, entries}`. Each entry records a key, amount and status.

### Why there are two implementations

`Ledger` updates running counters as events arrive. `Spec` recomputes totals from the entries. Neither calls the other. This gives us two different calculations to compare.

Save this example as `tmp/accounting_check.exs`:

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

Run it with `uv run --locked python scripts/local_run.py mix run tmp/accounting_check.exs`. All assertions pass: the real transition retains capacity, and Spec rejects the deliberately broken state.

The correct transition keeps the cached amount at `300`. The broken state claims zero is used, but `Spec` sums the entries and finds `300` still held. The assertion catches the disagreement.

`Spec.valid?/1` also checks limits, entry shapes, statuses and unique keys. It is an **invariant**: a condition that should hold before and after each operation. A **preservation** law says that starting in a valid state and applying an event produces another valid state. This catches accounting errors, but it does not require every eligible request to succeed. A function that refuses all requests could preserve validity by doing nothing.

`Spec` acts as an **oracle**, a reference for expected behavior. Recomputing totals helps catch implementation mistakes; it cannot correct a policy that both implementations misunderstand.

### Which law catches which mistake?

The repository gives required claims **obligation** labels such as PO-A4. A **group** is the unit selected by the verification runner and may contain several theorems. `verification/laws.json` gives each group a command-line slug, such as `po_a4_duplicate`. A report filename such as `po_a4-learning.json` is simply where the command saves its results.

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

The [Testing guide](testing.md#deliberate-mutations) describes the optional expensive experiment that applies the patches in isolated copies. [Human review](human_review.md#use-mutations-to-challenge-claims) explains how to interpret the results.

### Read a ledger law

The duplicate-request law, PO-A4/duplicate, says that reusing a recorded key at its original positive amount returns the same state, `:duplicate` and no effects. It assumes a valid state, an integer key, a positive integer amount and a matching entry found by `Spec.lookup/2`. Here is a witness you can run in `iex -S mix`:

```elixir
alias HoldLedger.{Ledger, Spec}
s = {1000, 3, 300, 1, [{11, 300, :reserved}]}
true = Spec.valid?(s)
{:ok, {11, 300, :reserved}} = Spec.lookup(elem(s, 4), 11)
{^s, :duplicate, []} = Ledger.request(s, 11, 300)
```

The declaration inside `test/laws/po_a4_duplicate_test.exs` uses the same structure as our toy law:

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

`exact` supplies an existing proof of the current goal. Here it applies a shared theorem rather than repeating the argument in every law file. The theorem in `test/support/lean/Lookup.lean` uses three steps:

1. A valid state contains a well-formed entry list.
2. On that list, `Ledger.find/2` and `Spec.lookup/2` agree. The precondition therefore tells us what the implementation’s lookup will find.
3. The matching key and amount select the duplicate branch of `Ledger.request/3`, which returns the original state, `:duplicate` and no effects.

The lookup lemma is proved once and reused. The kernel checks that the shared theorem establishes this law’s conclusion under its assumptions. The [shared proof theory reference](verification.md#shared-proof-theory) maps these dependencies.

### Follow this law into a real Lean proof

Run just the duplicate-request group from the repository root:

```sh
uv run --locked python scripts/run_laws.py --slug po_a4_duplicate --stage proofs \
  --report tmp/verification/po_a4-learning.json
```

This is a **focused proof attempt**, not the full acceptance stage. Open `test/laws/po_a4_duplicate_test.exs` and read `requires:` and `expects:`; then search for `theorem «po_a4_duplicate/4»` in `test/support/lean/Lookup.lean`. The law calls that theorem with `exact`, passing the law's variables and its `requires` hypothesis. Its body relies on a lookup-compatibility result proved elsewhere, so the large argument is not repeated at each use.

For the shape lemma and the recursive lookup argument, continue with [Reading deeper proofs](reading_deeper_proofs.md#follow-lookup-through-a-list).

**Checkpoint:** name the input domain, the exact result promised, and the lookup fact needed by `po_a4_duplicate`. You can answer these from the law and the three proof steps above before reading the helper's tactics.

### Make sure the assumptions describe a possible case

The witness above matters because a proof can succeed when no input satisfies its precondition. Such a claim is **vacuously true**: it has no cases to satisfy. This complete Lean example proves an arbitrary conclusion from contradictory assumptions:

```lean
import Lean
example (amount : Int) (positive : amount > 0) (nonpositive : amount ≤ 0) : amount = 42 := by
  omega
```

No integer satisfies both hypotheses. The proof establishes nothing about any actual admission. One witness rules out an entirely impossible precondition; it does not establish that every intended case is included.

## Exercises and solutions

1. **Boundary witness.** Add an exact-fit test for an integer larger than `2 ** 64`. Does the toy claim allow negative integers too?
2. **Mutation.** Make the comparison change in `tmp/cap_mutant_test.exs`. Run both ordinary checks and the proof, then explain the smallest executable failure. Continue the other exercises in the unchanged `tmp/cap_test.exs`.
3. **Write the second law.** Complete the [over-capacity law](#write-a-law-yourself). Keep the statement unchanged, add the witness and property, and finish the Lean proof.
4. **Read before changing.** Open `test/laws/po_a4_duplicate_test.exs`. Which assumptions describe the input, and which exact outputs does the conclusion require? Would requiring only a valid resulting state preserve the duplicate guarantee?

### Solutions

Try the exercises before reading these answers.

For exercise 1, `assert fits(10 ** 30, 10 ** 30)` and `assert fits(-1, -1)` both pass. Elixir integers are arbitrary precision. Real hold amounts must be positive; the toy function has no such rule.

For exercise 2, `fits(0, 0)` has a true precondition and a false conclusion under the mutant’s `>=` comparison. The original `cap_test.exs` admits this request.

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

Use `assert over_capacity(2, 1)` as the witness. For the property, generate `remaining <- integer()` and `gap <- positive_integer()`, then assert `over_capacity(remaining + gap, remaining)`. `positive_integer()` excludes zero, ensuring `remaining < remaining + gap`; zero would be an exact fit and belongs in `fits/2`. Run the ordinary and proof commands again; there are now two laws.

For exercise 4, the assumptions require a valid state, an integer key, a positive integer amount and a matching entry. The conclusion requires the original state, `:duplicate` and no effects. Validity alone could allow a different result or new effects; it would lose the duplicate guarantee.

## Review the statement, then its evidence

Before reading a proof body, review these four things in order:

1. **Statement:** do `requires` and `expects` express the intended behavior, including boundaries and rejected cases?
2. **Witness:** can the assumptions hold, and do they include the intended operating cases?
3. **Independence:** does `Spec` make its own decisions, or merely repeat or call the implementation?
4. **Translation boundary:** are the proof’s definitions generated from the code being reviewed? [Verification](verification.md#domains-and-limits) explains the compiler/translator assumptions and the pinned Lynx implementation’s review history.

Continue with [Reading deeper proofs](reading_deeper_proofs.md) for shared lemmas, induction and history models. [Agentic verification](agentic_verification.md) moves to contract review and agent-written changes.

> **Limits.** A checked proof establishes its statement about the translated functions under its hypotheses.
>
> The compiler and translator remain trusted. Runtime, storage and processor behavior need separate evidence. Tutorial proof attempts do not run the full acceptance pipeline; see [Verification](verification.md) for those checks and assumptions.

## Glossary

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
