module
public import Lynx.Term

public section
namespace HoldLedgerDifferentialCodec

inductive Wire where
  | integer : String → Wire
  | float : String → Wire
  | atom : String → Wire
  | tuple : List Wire → Wire
  | list : List Wire → Wire
  deriving Repr

def encode : Nat → Lynx.Term → Option Wire
  | 0, _ => none
  | _ + 1, .integer value => some (.integer (toString value))
  | _ + 1, .float value => some (.float (toString
      ((if value.negative then 2^63 else 0) + value.exponent.val * 2^52 + value.fraction.val)))
  | _ + 1, .atom name => some (.atom name)
  | n + 1, .tuple values => (values.toList.mapM (encode n)).map .tuple
  | _ + 1, .nil => some (.list [])
  | n + 1, .cons head tail => do
      let first ← encode n head
      let .list rest ← encode n tail | none
      pure (.list (first :: rest))
  | _, _ => none

def decode : Nat → Wire → Option Lynx.Term
  | 0, _ => none
  | _ + 1, .integer value => value.toInt?.map .integer
  | _ + 1, .float value => do
      let bits ← value.toNat?
      if bits >= 2^64 then none else
        let exponent := bits / 2^52 % 2048
        if h : exponent < 2047 then
          some (.float ⟨bits / 2^63 != 0, ⟨exponent, h⟩,
            ⟨bits % 2^52, Nat.mod_lt _ (by decide)⟩⟩)
        else none
  | _ + 1, .atom name => some (.atom name)
  | n + 1, .tuple values => (values.mapM (decode n)).map (fun xs => .tuple xs.toArray)
  | n + 1, .list values => (values.mapM (decode n)).map Lynx.Term.list

end HoldLedgerDifferentialCodec
