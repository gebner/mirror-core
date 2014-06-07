(** This file defines a Symbol instantiation that
 ** supports a polymorphic function environment
 ** but references must be fully instantiated.
 **)
Require Import Coq.PArith.BinPos Coq.Lists.List.
Require Import Coq.FSets.FMapPositive.
Require Import ExtLib.Core.RelDec.
Require Import ExtLib.Data.Positive.
Require Import ExtLib.Data.List.
Require Import ExtLib.Tactics.Consider.
Require Import MirrorCore.SymI.
Require Import MirrorCore.TypesI.

Set Implicit Arguments.
Set Strict Implicit.

Section parametric.
  Fixpoint quant (n : nat) : Type :=
    match n with
      | 0 => Type
      | S n => Type -> quant n
    end.

  Fixpoint qapply (n : nat) (ls : list Type) : quant n -> Type :=
    match n as n , ls return quant n -> Type with
      | 0 , nil => fun t => t
      | S n , l :: ls => fun f => @qapply n ls (f l)
      | _ , _ => fun _ => Empty_set
    end.

  Fixpoint parametric (n : nat) (acc : list Type) (k : list Type -> Type) : Type :=
    match n with
      | 0 => k acc
      | S n => forall T : Type, parametric n (T :: acc) k
    end.
End parametric.

Section typed.
  Variable typ : Type.
  Variable typD : list Type -> typ -> Type.
  Variable RType_typD : RType typD.
  Variable RTypeOk_typD : RTypeOk RType_typD.

  Inductive func : Type :=
  | FRef (fi : positive) (ts : list typ).

  Global Instance RelDec_eq_func : RelDec (@eq func) :=
  { rel_dec := fun l r =>
                 match l , r with
                   | FRef l ls , FRef r rs =>
                     if l ?[ eq ] r then ls ?[ eq ] rs else false
                 end
  }.

  Local Instance RelDec_typ : RelDec (@eq typ) := _.

  Global Instance RelDec_Correct_eq_func : RelDec_Correct RelDec_eq_func.
  Proof.
    constructor.
    destruct x; destruct y; simpl; try rewrite rel_dec_correct.
    split; intros.
    { consider (fi ?[ eq ] fi0); intros.
      rewrite rel_dec_correct in H0.
      f_equal; assumption. }
    { inversion H; clear H; subst.
      rewrite rel_dec_eq_true; eauto with typeclass_instances.
      apply rel_dec_eq_true; eauto with typeclass_instances. }
  Qed.

  Record function := F
  { fenv : nat
  ; ftype : typ
  ; fdenote : parametric fenv nil (fun env => typD env ftype)
  }.

  Definition functions := PositiveMap.t function.
  Variable fs : functions.

  Variable instantiate_typ : list typ -> typ -> typ.

  Variable type_apply
  : forall n ls acc t,
      parametric n acc (fun env => typD env t) ->
      option (typD acc (instantiate_typ ls t)).

  Hypothesis type_apply_length_equal : forall ft ts' n z fd,
    length ts' = n ->
    exists r, type_apply n ts' z ft fd = Some r.

  Definition func_typeof_sym (f : func) : option typ :=
    match f with
      | FRef i ts =>
        match PositiveMap.find i fs with
          | None => None
          | Some ft =>
            if ft.(fenv) ?[ eq ] length ts then
              Some (instantiate_typ ts ft.(ftype))
            else
              None
        end
    end.

  (** TODO: This is pretty ugly, it is because it doesn't
   ** match up well with [func_typeof_func].
   **)
  Global Instance RSym_func : RSym typD func :=
  { sym_eqb := fun l r => Some (l ?[ eq ] r)
  ; typeof_sym := func_typeof_sym
  ; symD := fun f =>
               match f as f
                     return match func_typeof_sym f with
                              | None => unit
                              | Some t => typD nil t
                            end
               with
                 | FRef i ts' =>
                   match PositiveMap.find i fs as x
                     return match
                       match x with
                         | Some ft =>
                           if fenv ft ?[ eq ] length ts'
                           then Some (instantiate_typ ts' (ftype ft))
                           else None
                         | None => None
                       end
                     with
                       | Some t => typD nil t
                       | None => unit
                     end
                   with
                     | Some {| fenv := fenv ; ftype := ftype ; fdenote := fd |} =>
                       match fenv ?[ eq ] length ts' as zz
                             return fenv ?[ eq ] length ts' = zz ->
                                    match
                                      (if zz
                                       then
                                         Some
                                           (instantiate_typ ts'
                                                            ftype)
                                       else None)
                                    with
                                      | Some t => typD nil t
                                      | None => unit
                                    end
                       with
                         | true => fun pf =>
                           match type_apply _ ts' nil _ fd as xx
                                 return type_apply _ ts' nil _ fd = xx -> _
                           with
                             | None => fun pf' => match _ : False with end
                             | Some z => fun _ => z
                           end eq_refl
                         | false => fun pf => tt
                       end eq_refl
                     | None => tt
                   end
               end
  }.
  abstract (rewrite rel_dec_correct in pf;
            destruct (type_apply_length_equal ftype0 _ nil fd (eq_sym pf));
            match type of H with
              | ?X = _ =>
                match type of pf' with
                  | ?Y = _ =>
                    change Y with X in pf' ; congruence
                end
            end).
  Defined.

  Definition from_list {T} (ls : list T) : PositiveMap.t T :=
    (fix from_list ls : positive -> PositiveMap.t T :=
       match ls with
         | nil => fun _ => PositiveMap.empty _
         | l :: ls => fun p =>
                        PositiveMap.add p l (from_list ls (Pos.succ p))
       end) ls 1%positive.

End typed.



(*

  Fixpoint subst0_typ (t : typ) (tv : typ) : typ :=
    match tv with
      | tyArr l r => tyArr (subst0_typ t l) (subst0_typ t r)
      | tyVar 0 => t
      | tyVar (S n) => tyVar n
      | tyProp
      | tyType _ => tv
    end.

  Theorem typD_subst0_typ : forall acc t l,
    typD (typD acc l :: acc) t = typD acc (subst0_typ l t).
  Proof.
    induction t; try reflexivity.
    { intros. simpl. rewrite IHt1. rewrite IHt2. reflexivity. }
    { intros. destruct n; simpl; reflexivity. }
  Defined.

  (** TODO: I want this **)
  Definition instantiate_typ (ls : list typ) (tv : typ) : typ :=
    List.fold_right subst0_typ tv ls.

  Theorem typD_instantiate_typD_cons : forall c t a b,
    typD (typD b a :: b) (instantiate_typ c t) =
    typD b (instantiate_typ (a :: c) t).
  Proof.
    simpl; intros. rewrite typD_subst0_typ. reflexivity.
  Defined.

  Fixpoint type_apply n ls acc t {struct n} :
    parametric n acc (fun env => typD env t) ->
    option (typD acc (instantiate_typ ls t)) :=
    match n as n , ls as ls
      return parametric n acc (fun env => typD env t) ->
             option (typD acc (instantiate_typ ls t))
      with
      | 0 , nil => fun X => Some X
      | S n , l :: ls => fun X =>
        match @type_apply n ls _ _ (X (typD acc l)) with
          | None => None
          | Some res =>
            Some match @typD_instantiate_typD_cons _ _ _ _ in _ = t
                   return t with
                   | eq_refl => res
                 end
        end
      | _ , _ => fun _ => None
    end.

  Theorem type_apply_length_equal : forall ft ts' n z fd,
    length ts' = n ->
    exists r, type_apply n ts' z ft fd = Some r.
  Proof.
    induction ts'; simpl in *; intros; subst; simpl; eauto.
    match goal with
      | [ |- exists x, match ?X with _ => _ end = _ ] =>
        consider X
    end; intros; eauto.
    destruct (@IHts' (length ts') (typD z a :: z) (fd (typD z a))
                     eq_refl).
    simpl in *.
    match goal with
      | [ H : ?X = None , H' : ?Y = Some _ |- _ ] =>
        let H'' := fresh in
        assert (H'' : X = Y) by reflexivity; congruence
    end.
  Qed.

  Theorem type_apply_length_equal' : forall ft ts' n z fd r,
    type_apply n ts' z ft fd = Some r ->
    length ts' = n.
  Proof.
    induction ts'; simpl in *; intros; subst; simpl; eauto.
    { destruct n; simpl in *; auto; congruence. }
    { destruct n; simpl in *; try congruence.
      f_equal.
      match goal with
        | [ H : match ?X with _ => _ end = _ |- _ ] =>
          consider X; intros; try congruence
      end.
      inversion H0; clear H0; subst. eauto. }
  Qed.

*)