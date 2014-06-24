(** This is a very simple arithmetic and boolean language that
 ** can be useful for testing.
 **)
Require Import ExtLib.Core.RelDec.
Require Import ExtLib.Data.Fun.
Require Import ExtLib.Data.Nat.
Require Import MirrorCore.ExprI.
Require Import MirrorCore.TypesI.
Require Import MirrorCore.SymI.
Require Import MirrorCore.Lambda.Expr.

Set Implicit Arguments.
Set Strict Implicit.

Inductive typ :=
| tyArr : typ -> typ -> typ
| tyNat | tyBool.

Fixpoint typD (ts : list Type) (t : typ) : Type :=
  match t with
    | tyNat => nat
    | tyBool => bool
    | tyArr a b => typD ts a -> typD ts b
  end.

Definition typ_eq_dec : forall a b : typ, {a = b} + {a <> b}.
  decide equality.
Defined.

Instance RType_typ : RType typ :=
{ typD := typD
; tyAcc := fun _ _ => False
; type_cast := fun _ a b => match typ_eq_dec a b with
                              | left pf => Some pf
                              | _ => None
                            end
}.

Instance Typ2_tyArr : Typ2 _ Fun :=
{ typ2 := tyArr
; typ2_cast := fun _ _ _ => eq_refl
; typ2_match :=
    fun T ts t tr =>
      match t as t return T (TypesI.typD ts t) -> T (TypesI.typD ts t) with
        | tyArr a b => fun _ => tr a b
        | _ => fun fa => fa
      end
}.

Inductive func :=
| Lt | Plus | N : nat -> func.

Definition typeof_func (f : func) : option typ :=
  Some match f with
         | Lt => tyArr tyNat (tyArr tyNat tyBool)
         | Plus => tyArr tyNat (tyArr tyNat tyNat)
         | N _ => tyNat
       end.

Definition funcD (ts : list Type) (f : func)
: match typeof_func f with
    | None => unit
    | Some t => typD ts t
  end :=
  match f as f return match typeof_func f with
                        | None => unit
                        | Some t => typD ts t
                      end
  with
    | Lt => NPeano.ltb
    | Plus => plus
    | N n => n
  end.

Instance RelDec_func_eq : RelDec (@eq func) :=
{ rel_dec := fun (a b : func) =>
               match a , b with
                 | Plus , Plus => true
                 | Lt , Lt => true
                 | N a , N b => a ?[ eq ] b
                 | _ , _ => false
               end
}.

Instance RSym_func : RSym func :=
{ typeof_sym := typeof_func
; symD := funcD
; sym_eqb := fun a b => Some (a ?[ eq ] b) }.