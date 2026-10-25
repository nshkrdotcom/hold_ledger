# M8 decline increases used amount

Concrete witness: `{1000, 3, 300, 1, [{11, 300, :sent}]}`, event `{:processor_result, 11, :declined}`. The isolated runner checks the correct source before applying the patch. The unchanged target law is `po_b1_processor_result`. No Spec or law modification is permitted. A proof failure alone is not a counterexample.
