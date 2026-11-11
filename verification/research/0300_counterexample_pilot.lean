module

-- Research-only, derived from target Lynx `Lean/LynxTest/Counterexample.lean`.
-- Run locally with the pinned Lynx toolchain; never treat
-- `#guard_msgs` as a production proof obligation.
import Lynx
import Lynx.Runner.Elab
import Lynx.Modules.Erlang.erlang
meta import Lynx.Modules.Erlang.erlang

namespace HoldLedger0300.CounterexamplePilot
open Lynx Erlang.erlang

private def poll : Result :=
  .receive .immediate (fun _ message => some message) fun
    | some message => .ok message
    | none => .ok (.atom "timeout")

private def functions : Term.FunTable := [
  { module := "0300", name := "greet", arity := 0, entry := .effectful fun dispatcher captures _ =>
      match captures.toList with
      | [parent] => «send/2» dispatcher parent (.atom "hello")
      | _ => .error .exhausted }]

private def dispatcher : Dispatcher := Dispatcher.ofTable functions 1

private def race : Result := do
  let self ← «self/0» dispatcher
  let _ ← «spawn/1» dispatcher (.function "0300" "greet" 0 #[self])
  poll

private def hello : Outcome Term → Bool
  | .ok (.atom "hello") => true
  | _ => false

private def answered : Outcome Term → Bool
  | .ok (.atom "hello") | .ok (.atom "timeout") => true
  | _ => false

/--
error: Found a schedule where the program returns timeout:
  1. <0> spawns <0.1>
  2. <0> times out waiting for a message
  3. <0> exits with normal
  4. <0.1> sends hello to <0>
  5. <0.1> exits with normal
-/
#guard_msgs in
example : Concurrent.check hello 32 (.start {} race) = true := by
  lynx_counterexample
  cbv

-- No counterexample: tactic does not close the goal. Kernel tactic does.
example : Concurrent.check answered 32 (.start {} race) = true := by
  lynx_counterexample
  cbv

/--
error: Found a schedule that takes more than 4 steps; increase the depth:
  1. <0> spawns <0.1>
  2. <0> times out waiting for a message
-/
#guard_msgs in
example : Concurrent.check answered 4 (.start {} race) = true := by
  lynx_counterexample
  cbv

/-- error: lynx_counterexample runs closed programs, but this one depends on [program] -/
#guard_msgs in
example (program : Result) : Concurrent.check answered 32 (.start {} program) = true := by
  lynx_counterexample

/-- error: lynx_counterexample expects a program returning a term, not Nat -/
#guard_msgs in
example : Concurrent.check (fun (_ : Outcome Nat) => true) 1
    (.start {} (.ok 0)) = true := by
  lynx_counterexample

-- A successful diagnostic leaves the proof obligation open.
/--
error: unsolved goals
⊢ Concurrent.check answered 32 (Concurrent.Config.start { } race) = true
-/
#guard_msgs in
example : Concurrent.check answered 32 (.start {} race) = true := by
  lynx_counterexample

end HoldLedger0300.CounterexamplePilot
