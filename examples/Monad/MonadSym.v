Require Import ExtLib.Structures.Functor.
Require Import ExtLib.Structures.Monad.
Require Import ExtLib.Tactics.
Require Import MirrorCore.SymI.
Require Import MirrorCore.TypesI.
Require Import MirrorCore.Lambda.ExprCore.
Require Import MirrorCore.Lambda.ExprDI.
Require Import McExamples.Monad.MonadTypes.

Set Implicit Arguments.
Set Strict Implicit.

Section monad_funcs.
  Variable m : Type -> Type.
  Context {Monad_m : Monad m}.
  Variable ts : types. (** Opaque types **)

  Inductive mfunc : Type :=
  | mBind : typ -> typ -> mfunc
  | mReturn : typ -> mfunc.

  Definition typeof_mfunc (m : mfunc) : option typ :=
    Some match m with
           | mBind a b => tyArr (tyM a) (tyArr (tyArr a (tyM b)) (tyM b))
           | mReturn a => tyArr a (tyM a)
         end.

  Definition mfuncD (f : mfunc) : match typeof_mfunc f with
                                    | None => unit:Type
                                    | Some t => typD m ts t
                                  end :=
    match f as f
          return typD m ts
                      match f with
                        | mBind a b =>
                          tyArr (tyM a) (tyArr (tyArr a (tyM b)) (tyM b))
                        | mReturn a => tyArr a (tyM a)
                      end
    with
      | mBind a b => bind
      | mReturn a => ret
    end.

  Definition mfunc_eq (a b : mfunc) : option bool :=
    match a , b with
      | mBind a1 a2 , mBind b1 b2 =>
        Some (if type_cast a1 b1 then if type_cast a2 b2 then true else false else false)
      | mReturn a , mReturn b =>
        Some (if type_cast a b then true else false)
      | _ , _ => Some false
    end.

  Instance RSym_mfunc : @RSym typ (RType_typ m ts) mfunc :=
  { typeof_sym := typeof_mfunc
  ; symD := mfuncD
  ; sym_eqb := mfunc_eq
  }.
End monad_funcs.
