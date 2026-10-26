# M10 premature release before void confirmation

Concrete witness: limit 100, one authorized hold for key 1 and amount 100. Voiding
that hold must leave its capacity held and reject a second request for 100.
The patch instead releases capacity before terminal confirmation. The witness
checks this behavior against the correct source before mutation. The target law
is `po_exposure_retain`. A tactic failure by itself is not a counterexample.
