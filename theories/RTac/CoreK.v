Require Import Coq.Classes.Morphisms.
Require Import Coq.Relations.Relations.
Require Import ExtLib.Core.RelDec.
Require Import ExtLib.Structures.Monad.
Require Import ExtLib.Structures.Traversable.
Require Import ExtLib.Data.Option.
Require Import ExtLib.Data.Prop.
Require Import ExtLib.Data.Pair.
Require Import ExtLib.Data.List.
Require Import ExtLib.Data.HList.
Require Import ExtLib.Data.Monads.OptionMonad.
Require Import ExtLib.Tactics.
Require Import MirrorCore.ExprI.
Require Import MirrorCore.SubstI.
Require Import MirrorCore.ExprDAs.
Require Import MirrorCore.RTac.Core.

Require Import MirrorCore.Util.Quant.
Require Import MirrorCore.Util.Forwardy.

Set Implicit Arguments.
Set Strict Implicit.

Section parameterized.
  Variable typ : Type.
  Variable expr : Type.

  Context {RType_typ : RType typ}.
  Context {Expr_expr : Expr RType_typ expr}.
  Context {Typ0_Prop : Typ0 _ Prop}.

(*
  (** TODO(gmalecha): These should go somewhere more useful *)
  Fixpoint forgets (from : nat) (ts : list typ) (s : subst)
  : list (option expr) :=
    match ts with
      | nil => nil
      | t :: ts =>
        let rr := forgets (S from) ts s in
        let ne := subst_lookup from s in
        ne :: rr
    end.

  Fixpoint remembers (from : nat) (tes : list (typ * option expr)) (s : subst)
  : option subst :=
    match tes with
      | nil => Some s
      | (_,None) :: tes' => remembers (S from) tes' s
      | (_,Some e) :: tes' =>
        (* This should not be necessary but to eliminate it, we must have a
         * syntactic soundness condition for [set] *)
        match subst_lookup from s with
          | None =>
            match subst_set from e s with
              | None => None
              | Some s' => remembers (S from) tes' s'
            end
          | Some _ => None
        end
    end.
*)


  Definition rtacK_spec ctx (s : ctx_subst ctx) (g : Goal _ _)
             (r : Result ctx) : Prop :=
    match r with
      | Fail => True
      | Solved s' =>
        WellFormed_Goal (getUVars ctx) (getVars ctx) g ->
        WellFormed_ctx_subst s ->
        WellFormed_ctx_subst s' /\
        match pctxD s
            , goalD _ _ g
            , pctxD s'
        with
          | None , _ , _
          | Some _ , None , _ => True
          | Some _ , Some _ , None => False
          | Some cD , Some gD , Some cD' =>
            SubstMorphism s s' /\
            forall us vs, cD' gD us vs
        end
      | More_ s' g' =>
        WellFormed_Goal (getUVars ctx) (getVars ctx) g ->
        WellFormed_ctx_subst s ->
        WellFormed_ctx_subst s' /\
        WellFormed_Goal (getUVars ctx) (getVars ctx) g' /\
        match pctxD s
            , goalD _ _ g
            , pctxD s'
            , goalD _ _ g'
        with
          | None , _ , _ , _
          | Some _ , None , _ , _ => True
          | Some _ , Some _ , None , _
          | Some _ , Some _ , Some _ , None => False
          | Some cD , Some gD , Some cD' , Some gD' =>
            SubstMorphism s s' /\
            forall us vs,
              cD' (fun us vs => gD' us vs -> gD us vs) us vs
        end
    end.

  Theorem Proper_rtacK_spec ctx s
  : Proper (EqGoal (getUVars ctx) (getVars ctx) ==>
            @EqResult _ _ _ _ _ (getUVars ctx) (getVars ctx) ctx
            ==> iff)
           (@rtacK_spec ctx s).
  Proof.
(*
    red. red. red.
    unfold rtacK_spec.
    inversion 2.
    { destruct x0; destruct y0; simpl in *; try congruence.
      reflexivity. }
    { destruct x0; destruct y0; simpl in *;
      try solve [ reflexivity | congruence ]; inv_all; subst; inv_all;
      try (eapply impl_iff; try reflexivity; intros;
           eapply and_iff; try reflexivity; intros;
           try inversion H; try reflexivity;
           try inversion H5; try reflexivity;
           repeat match goal with
                    | |- context [ match ?X with _ => _ end ] =>
                      consider X; intros; try reflexivity; [ ]
                  end;
           eapply and_iff; try reflexivity; intros;
           do 2 (eapply forall_iff; intro);
           eapply Fmap_pctxD_iff; eauto; try reflexivity;
           do 5 red; intros).
      { apply impl_iff; [ eapply H10; eauto | intro ].
        apply H7; eauto. }
      { do 5 red in H10.
        rewrite H10; try reflexivity.
        rewrite impl_True_iff.
        eapply H7; eauto. }
      { do 5 red in H10.
        rewrite <- H10; try reflexivity.
        rewrite impl_True_iff.
        eapply H7; eauto. } }
*)
  Admitted. (** Port **)

  (** Treat this as opaque! **)
  Definition rtacK : Type :=
    tenv typ -> tenv typ -> nat -> nat ->
    forall c : Ctx typ expr, ctx_subst c -> Goal typ expr -> Result c.

  Definition rtacK_sound (tac : rtacK)
  : Prop :=
    forall ctx s g result,
      (let tus := getUVars ctx in
       let tvs := getVars ctx in
       tac tus tvs (length tus) (length tvs) ctx s g = result) ->
      @rtacK_spec ctx s g result.

End parameterized.

Export MirrorCore.ExprI.
Export MirrorCore.SubstI.
Export MirrorCore.ExprDAs.
Export MirrorCore.RTac.Core.