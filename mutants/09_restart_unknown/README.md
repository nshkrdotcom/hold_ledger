# M9 restart leaves sent entries unchanged

Concrete witness: `{1000, 3, 300, 1, [{11, 300, :sent}]}`, event `:restart`. The isolated runner checks the correct source before applying the patch. The unchanged target law is `po_b7`. No Spec or law modification is permitted. A proof failure alone is not a counterexample.
