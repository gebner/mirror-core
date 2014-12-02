(** Bounded Instantiated Maps **)
Require Import Coq.Bool.Bool.
Require Import Coq.Classes.Morphisms.
Require Import Coq.Relations.Relations.
Require Import ExtLib.Core.RelDec.
Require Import ExtLib.Structures.Monad.
Require Import ExtLib.Structures.Traversable.
Require Import ExtLib.Data.Option.
Require Import ExtLib.Data.Prop.
Require Import ExtLib.Data.Pair.
Require Import ExtLib.Data.List.
Require Import ExtLib.Data.ListFirstnSkipn.
Require Import ExtLib.Data.HList.
Require Import ExtLib.Data.Monads.OptionMonad.
Require Import ExtLib.Tactics.
Require Import MirrorCore.ExprI.
Require Import MirrorCore.SubstI.
Require Import MirrorCore.VariablesI.
Require Import MirrorCore.ExprDAs.
Require Import MirrorCore.Subst.FMapSubst.

Require Import MirrorCore.Util.Quant.
Require Import MirrorCore.Util.Forwardy.

Set Implicit Arguments.
Set Strict Implicit.

(** TODO: This has to be somewhere else **)
Instance Reflexive_pointwise
         {T U} {R : U -> U -> Prop} (Refl : Reflexive R)
: Reflexive (pointwise_relation T R).
Proof.
  red. red. reflexivity.
Qed.


Section parameterized.
  Variable typ : Type.
  Variable expr : Type.

  Context {RType_typ : RType typ}.
  Context {RTypeOk_typ : RTypeOk}.
  Context {Typ0_Prop : Typ0 _ Prop}.
  Context {Expr_expr : Expr RType_typ expr}.
  Context {ExprOk_expr : ExprOk Expr_expr}.
  Context {ExprVar_expr : ExprVar expr}.
  Context {ExprVarOk_expr : ExprVarOk _}.
  Context {ExprUVar_expr : ExprUVar expr}.
  Context {ExprUVarOk_expr : ExprUVarOk _}.
  Context {MentionsAny_expr : MentionsAny expr}.
  Context {MentionsAnyOk_expr : MentionsAnyOk _ _ _}.

  Local Instance RelDec_eq_typ : RelDec (@eq typ) :=
    RelDec_Rty _.
  Local Instance RelDecOk_eq_typ : RelDec_Correct RelDec_eq_typ :=
    @RelDec_Correct_Rty _ _ _.

  Local Existing Instance SUBST.Subst_subst.
  Local Existing Instance SUBST.SubstOk_subst.
  Local Existing Instance SUBST.SubstOpen_subst.
  Local Existing Instance SUBST.SubstOpenOk_subst.

  Definition amap : Type := SUBST.raw expr.
  Definition WellFormed_amap : amap -> Prop := @SUBST.WellFormed _ _.
  Definition amap_empty : amap := UVarMap.MAP.empty _.
  Definition amap_lookup : nat -> amap -> option expr :=
    @UVarMap.MAP.find _.
  Definition amap_check_set : nat -> expr -> amap -> option amap :=
    @SUBST.raw_set _ _.
  Definition amap_instantiate (f : nat -> option expr) : amap -> amap :=
    UVarMap.MAP.map (fun e => instantiate f 0 e).
  Definition amap_substD
  : forall (tus tvs : tenv typ), amap -> option (exprT tus tvs Prop) :=
    @SUBST.raw_substD _ _ _ _.
  Definition amap_is_full (* min : uvar *) (len : nat) (m : amap) : bool :=
    UVarMap.MAP.cardinal m ?[ eq ] len.
  Definition amap_domain (m : amap) : list uvar :=
    map fst (UVarMap.MAP.elements m).

  Definition Forall_amap (P : uvar -> expr -> Prop) (m : amap) : Prop :=
    forall u e,
      amap_lookup u m = Some e ->
      P u e.

  Lemma Forall_amap_empty
  : forall P, Forall_amap P amap_empty.
  Proof.
    clear. intros.
    red. unfold amap_lookup, amap_empty.
    intros. rewrite FMapSubst.SUBST.FACTS.empty_o in H. congruence.
  Qed.


  Definition WellFormed_bimap (min : nat) (len : nat) (m : amap)
  : Prop :=
    (** 'acyclic' **)
    SUBST.WellFormed m /\
    (** only in this range **)
    Forall_amap (fun k _ => min <= k < min + len) m /\
    (** no forward pointers **)
    Forall_amap (fun k e => forall u'',
                              mentionsU u'' e = true ->
                              u'' < min + len) m.

  Lemma WellFormed_bimap_empty
  : forall a b, WellFormed_bimap a b amap_empty.
  Proof.
    clear - Expr_expr. red.
    intros. refine (conj _ (conj _ _));
            eauto using SUBST.WellFormed_empty, Forall_amap_empty.
    eapply SUBST.WellFormed_empty.
  Qed.

  Lemma WellFormed_bimap_WellFormed_amap
  : forall a b s,
      WellFormed_bimap a b s ->
      WellFormed_amap s.
  Proof.
    destruct 1. assumption.
  Qed.

  Lemma amap_instantiates_substD
  : forall tus tvs C (_ : CtxLogic.ExprTApplicative C) f s sD a b,
      WellFormed_bimap a b s ->
      amap_substD tus tvs s = Some sD ->
      sem_preserves_if_ho C f ->
      exists sD',
        amap_substD tus tvs (amap_instantiate f s) = Some sD' /\
        C (fun us vs => sD us vs <-> sD' us vs).
  Proof.
    unfold amap_instantiate.
    intros.
    eapply SUBST.raw_substD_instantiate_ho in H2; eauto.
    forward_reason.
    eexists; split; eauto.
    revert H3.
    eapply CtxLogic.exprTAp.
    eapply CtxLogic.exprTPure.
    intros us vs.
    clear. tauto.
  Qed.

  Lemma amap_lookup_substD
  : forall (s : amap) (uv : uvar) (e : expr),
      amap_lookup uv s = Some e ->
      forall (tus tvs : list typ)
             (sD : hlist typD tus -> hlist typD tvs -> Prop),
        amap_substD tus tvs s = Some sD ->
        exists
          (t : typ) (val : exprT tus tvs (typD t))
          (get : hlist typD tus -> typD t),
          nth_error_get_hlist_nth typD tus uv =
          Some (existT (fun t0 : typ => hlist typD tus -> typD t0) t get) /\
          exprD' tus tvs e t = Some val /\
          (forall (us : hlist typD tus) (vs : hlist typD tvs),
             sD us vs -> get us = val us vs).
  Proof. eapply SUBST.substD_lookup'. Qed.

  Lemma amap_domain_WellFormed
  : forall (s : amap) (ls : list uvar),
       WellFormed_amap s ->
       amap_domain s = ls ->
       forall n : nat, In n ls <-> amap_lookup n s <> None.
  Proof. eapply SUBST.WellFormed_domain. Qed.

  Lemma amap_lookup_normalized
  : forall (s : amap) (e : expr) (u : nat),
      WellFormed_amap s ->
      amap_lookup u s = Some e ->
      forall (u' : nat) (e' : expr),
        amap_lookup u' s = Some e' -> mentionsU u' e = false.
  Proof. eapply SUBST.normalized_fmapsubst. Qed.

  Lemma amap_lookup_amap_instantiate
  : forall u f m,
      amap_lookup u (amap_instantiate f m) =
      match amap_lookup u m with
        | None => None
        | Some e => Some (instantiate f 0 e)
      end.
  Proof.
    unfold amap_lookup, amap_instantiate; intros.
    apply SUBST.FACTS.map_o.
  Qed.

  Lemma syn_check_set
  : forall uv e s s',
      WellFormed_amap s ->
      amap_check_set uv e s = Some s' ->
      let e' := instantiate (fun u => amap_lookup u s) 0 e in
      WellFormed_amap s' /\
      mentionsU uv e'= false /\
      forall u,
        amap_lookup u s' =
        if uv ?[ eq ] u then Some e'
        else
          match amap_lookup u s with
            | None => None
            | Some e =>
              Some (instantiate (fun u =>
                                   if uv ?[ eq ] u then Some e'
                                   else None) 0 e)
          end.
  Proof.
    intros. unfold amap_check_set, SUBST.raw_set in *.
    forward. inv_all; subst.
    split.
    { eapply SUBST.raw_set_WellFormed; eauto.
      instantiate (1 := e). instantiate (1 := uv).
      unfold amap_check_set, SUBST.raw_set in *.
      rewrite H0. reflexivity. }
    split.
    { assumption. }
    intros.
    unfold amap_lookup.
    rewrite SUBST.FACTS.add_o.
    destruct (SUBST.PROPS.F.eq_dec uv u); subst.
    { rewrite rel_dec_eq_true; eauto with typeclass_instances. }
    { rewrite rel_dec_neq_false; eauto with typeclass_instances.
      unfold SUBST.raw_instantiate.
      rewrite SUBST.FACTS.map_o.
      destruct (UVarMap.MAP.find u s); try reflexivity. }
  Qed.

  Lemma WellFormed_bimap_check_set
  : forall uv e s min len s',
      amap_check_set uv e s = Some s' ->
      (forall u, mentionsU u e = true -> u < min + len) ->
      min <= uv < min + len ->
      WellFormed_bimap min len s ->
      WellFormed_bimap min len s'.
  Proof.
    intros.
    eapply syn_check_set in H; eauto.
    red in H2. red.
    { forward_reason.
      split; auto.
      split.
      { red in H3. red.
        intros.
        rewrite H7 in H8.
        consider (uv ?[ eq ] u); intros; subst.
        omega.
        forward. eapply H3; eauto. }
      { red in H4; red; intros.
        rewrite H7 in H8; clear H7.
        consider (uv ?[ eq ] u); intros; subst.
        { inv_all; subst.
          eapply mentionsU_instantiate in H9.
          destruct H9.
          { eapply H0. tauto. }
          { forward_reason.
            eapply H4 in H7. eauto. eauto. } }
        { forward.
          inv_all; subst.
          eapply mentionsU_instantiate in H9.
          destruct H9.
          { forward_reason.
            consider (uv ?[ eq ] u''); intros; subst; try congruence.
            eauto. }
          { forward_reason.
            consider (uv ?[ eq ] x); intros; subst; try congruence.
            inv_all; subst.
            eapply mentionsU_instantiate in H11.
            destruct H11.
            { forward_reason. eauto. }
            { forward_reason. eauto. } } } } }
    { destruct H2. assumption. }
  Qed.

  Lemma Forall_amap_instaniate
  : forall (P Q : uvar -> expr -> Prop) f m,
      (forall u e, Q u e -> P u (instantiate f 0 e)) ->
      Forall_amap Q m ->
      Forall_amap P (amap_instantiate f m).
  Proof.
    clear.
    intros. red.
    unfold amap_lookup, amap_instantiate, amap_lookup. intros u e.
    rewrite SUBST.FACTS.map_o.
    consider (UVarMap.MAP.find u m); simpl; intros; try congruence.
    inv_all. eapply H0 in H1. subst; eauto.
  Qed.

  Lemma WellFormed_bimap_instantiate
  : forall s f min len s',
      amap_instantiate f s = s' ->
      (forall u e,
         f u = Some e ->
         forall u',
           mentionsU u' e = true ->
           u' < min) ->
      WellFormed_bimap min len s ->
      WellFormed_bimap min len s'.
  Proof.
    red; intros; subst.
    red in H1. forward_reason.
    split.
    { red. intros.
      rewrite SUBST.PROPS.F.find_mapsto_iff in H3.
      unfold amap_instantiate in *.
      rewrite SUBST.FACTS.map_o in H3.
      red. intros.
      consider (UVarMap.MAP.find k s); simpl in *; try congruence.
      intros. inv_all; subst.
      eapply SUBST.PROPS.F.not_find_in_iff.
      rewrite SUBST.FACTS.map_o.
      consider (UVarMap.MAP.find u s); try reflexivity.
      intros. exfalso.
      eapply mentionsU_instantiate in H4.
      destruct H4.
      { destruct H4.
        eapply H. 2: eassumption.
        eapply SUBST.PROPS.F.find_mapsto_iff. eassumption.
        red. eexists.
        eapply SUBST.PROPS.F.find_mapsto_iff. eassumption. }
      { forward_reason.
        specialize (H0 _ _ H4 _ H7).
        eapply H1 in H5. omega. } }
    split.
    { revert H1. eapply Forall_amap_instaniate. trivial. }
    { revert H2. eapply Forall_amap_instaniate; intros.
      eapply mentionsU_instantiate in H3. destruct H3.
      { destruct H3; eauto. }
      { forward_reason.
        eapply H0 in H3. 2: eassumption. omega. } }
  Qed.

  Definition nothing_in_range a b m : Prop :=
    forall u, u < b -> amap_lookup (a + u) m = None.
  Definition only_in_range min len m :=
    Forall_amap (fun k _ => min <= k < min + len) m.

  Lemma only_in_range_0_empty
  : forall a am,
      only_in_range a 0 am ->
      UVarMap.MAP.Equal am amap_empty.
  Proof.
    clear. unfold Forall_amap. red.
    intros.
    specialize (H y). unfold amap_lookup in *.
    rewrite SUBST.FACTS.empty_o.
    destruct (UVarMap.MAP.find y am); auto.
    exfalso. specialize (H _ eq_refl). omega.
  Qed.

  Lemma Forall_amap_Proper
  : Proper (pointwise_relation _ (pointwise_relation _ iff) ==> UVarMap.MAP.Equal ==> iff)
           Forall_amap.
  Proof.
    do 3 red; intros.
    split; intros; red; intros;
    eapply SUBST.FACTS.find_mapsto_iff in H2;
    eapply SUBST.FACTS.Equal_mapsto_iff in H0; eauto.
    - eapply H0 in H2.
      eapply H1 in H2.
      eapply H; eauto.
    - eapply H0 in H2.
      eapply H1 in H2.
      eapply H; eauto.
  Qed.

  Lemma only_in_range_0_WellFormed_pre_entry
  : forall a am,
      only_in_range a 0 am ->
      WellFormed_bimap a 0 am.
  Proof.
    clear. unfold WellFormed_bimap.
    intros. eapply only_in_range_0_empty in H.
    split.
    - red. intros.
      eapply SUBST.FACTS.Equal_mapsto_iff in H.
      eapply H in H0. clear - H0.
      eapply SUBST.FACTS.empty_mapsto_iff in H0.
      destruct H0.
    - split.
      + eapply Forall_amap_Proper; eauto.
        eapply Reflexive_pointwise.
        eapply Reflexive_pointwise. eauto with typeclass_instances.
        eapply Forall_amap_empty.
      + eapply Forall_amap_Proper; eauto.
        eapply Reflexive_pointwise.
        eapply Reflexive_pointwise. eauto with typeclass_instances.
        eapply Forall_amap_empty.
  Qed.

  (** Start pigeonhole stuff **)
  Lemma cardinal_remove
  : forall m x y,
      amap_lookup x m = Some y ->
      UVarMap.MAP.cardinal m = S (UVarMap.MAP.cardinal (UVarMap.MAP.remove x m)).
  Proof.
    clear. intros.
    do 2 rewrite SUBST.PROPS.cardinal_fold.
    assert (UVarMap.MAP.Equal m (UVarMap.MAP.add x y (UVarMap.MAP.remove x m))).
    { red. intros.
      rewrite SUBST.PROPS.F.add_o.
      rewrite SUBST.PROPS.F.remove_o.
      destruct (SUBST.PROPS.F.eq_dec x y0). subst; auto.
      auto. }
    etransitivity.
    (rewrite SUBST.PROPS.fold_Equal with (eqA := @eq nat); try eassumption); eauto.
    compute; intros; subst; auto.
    compute; intros; subst; auto.
    rewrite SUBST.PROPS.fold_add. reflexivity.
    eauto.
    compute; intros; subst; auto.
    compute; intros; subst; auto.
    eapply UVarMap.MAP.remove_1. reflexivity.
  Qed.

  Lemma cardinal_not_remove
  : forall m x,
      amap_lookup x m = None ->
      UVarMap.MAP.cardinal m = UVarMap.MAP.cardinal (UVarMap.MAP.remove x m).
  Proof.
    clear. intros.
    assert (UVarMap.MAP.Equal m (UVarMap.MAP.remove x m)).
    { red. intros.
      rewrite SUBST.PROPS.F.remove_o.
      destruct (SUBST.PROPS.F.eq_dec x y). subst; auto.
      auto. }
    rewrite <- H0. reflexivity.
  Qed.

  Lemma subst_pull_sound
  : forall b a m m',
      subst_pull a b m = Some m' ->
      nothing_in_range a b m' /\
      UVarMap.MAP.cardinal m' = UVarMap.MAP.cardinal m - b /\
      (forall u, u < a \/ u >= a + b -> amap_lookup u m = amap_lookup u m') /\
      (forall u, u < b -> amap_lookup (a + u) m <> None).
  Proof.
    clear.
    induction b.
    { simpl. intros. inv_all; subst.
      split.
      { red. intros; exfalso; omega. }
      split.
      { omega. }
      split.
      { auto. }
      { intros. exfalso; omega. } }
    { simpl. unfold SUBST.raw_drop.
      intros. forwardy.
      eapply IHb in H. forward_reason.
      inv_all. subst.
      split.
      { red. intros.
        unfold amap_lookup. rewrite SUBST.PROPS.F.remove_o.
        destruct (SUBST.PROPS.F.eq_dec a (a + u)); auto.
        destruct u.
        { exfalso; omega. }
        { replace (a + S u) with (S a + u) by omega.
          red in H. eapply H. omega. } }
      split.
      { replace (UVarMap.MAP.cardinal m - S b) with
        ((UVarMap.MAP.cardinal m - b) - 1) by omega.
        rewrite <- H2. clear - H0.
        rewrite (@cardinal_remove _ _ _ H0). omega. }
      split.
      { intros.
        destruct H1.
        + rewrite H3; [ | left; eauto ].
          unfold amap_lookup.
          rewrite SUBST.PROPS.F.remove_neq_o; auto.
        + rewrite H3; [ | right; omega ].
          unfold amap_lookup.
          rewrite SUBST.PROPS.F.remove_neq_o; auto.
          omega. }
      { intros.
        destruct u.
        { rewrite H3; [ | left; omega ].
          replace (a + 0) with a. change_rewrite H0. congruence.
          clear. apply plus_n_O. }
        { replace (a + S u) with (S a + u) by omega.
          apply H4. omega. } } }
  Qed.

  Lemma subst_pull_complete
  : forall b a m,
      (forall u, u < b -> amap_lookup (a + u) m <> None) ->
      exists m',
        subst_pull a b m = Some m'.
  Proof.
    clear. induction b; simpl; intros; eauto.
    { destruct (IHb (S a) m); clear IHb.
      { intros. replace (S a + u) with (a + S u) by omega.
        eapply H. omega. }
      { rewrite H0.
        eapply subst_pull_sound in H0.
        forward_reason. unfold SUBST.raw_drop.
        rewrite <- H2 by (left; omega).
        specialize (H 0).
        replace (a + 0) with a in H by omega.
        destruct (amap_lookup a m); eauto.
        exfalso. eapply H; auto. omega. } }
  Qed.

  Fixpoint test_range from len m :=
    match len with
      | 0 => true
      | S len =>
        match amap_lookup from m with
          | None => false
          | Some _ => test_range (S from) len (UVarMap.MAP.remove from m)
        end
    end.

  Lemma test_range_true_all
  : forall l f m,
      test_range f l m = true ->
      forall u, u < l -> amap_lookup (f + u) m <> None.
  Proof.
    clear. induction l.
    { intros; exfalso; omega. }
    { simpl; intros; forward.
      specialize (IHl _ _ H1).
      destruct u.
      { replace (f + 0) with f by omega. congruence. }
      { replace (f + S u) with (S f + u) by omega.
        cutrewrite (amap_lookup (S f + u) m =
                    amap_lookup (S f + u) (UVarMap.MAP.remove f m)).
        { apply IHl. omega. }
        unfold amap_lookup.
        rewrite SUBST.PROPS.F.remove_neq_o; auto. omega. } }
  Qed.

  Lemma cardinal_le_range
  : forall len min m,
      only_in_range min len m ->
      UVarMap.MAP.cardinal m <= len.
  Proof.
    clear.
    induction len.
    { intros.
      eapply only_in_range_0_empty in H.
      cut (UVarMap.MAP.cardinal m = 0); try omega.
      apply SUBST.PROPS.cardinal_1.
      rewrite H.
      apply UVarMap.MAP.empty_1. }
    { intros.
      assert (only_in_range min len (UVarMap.MAP.remove (min + len) m)).
      { red. red in H. red. intros.
        unfold amap_lookup in H0.
        rewrite SUBST.PROPS.F.remove_o in H0.
        destruct (SUBST.PROPS.F.eq_dec (min + len) u); try congruence.
        eapply H in H0. omega. }
      { eapply IHlen in H0.
        consider (UVarMap.MAP.find (min + len) m); intros.
        { erewrite cardinal_remove; eauto.
          omega. }
        { erewrite cardinal_not_remove; eauto. } } }
  Qed.

  Lemma subst_getInstantiation
  : forall tus tvs ts m P,
      WellFormed_bimap (length tus) (length ts) m ->
      amap_substD (tus ++ ts) tvs m = Some P ->
      amap_is_full (length ts) m = true ->
      exists x : hlist (fun t => exprT tus tvs (typD t)) ts,
        forall us vs,
          let us' :=
              hlist_map (fun t (x : exprT tus tvs (typD t)) => x us vs) x
          in
          P (HList.hlist_app us us') vs.
  Proof.
    intros.
    assert (exists m',
              subst_pull (length tus) (length ts) m = Some m' /\
              UVarMap.MAP.Empty m').
    { unfold amap_is_full in H1.
      consider (UVarMap.MAP.cardinal m ?[ eq ] length ts); intros.
      assert (only_in_range (length tus) (length ts) m).
      { clear - H. red in H. red; intros.
        tauto. }
      clear - H1 H2.
      destruct (@subst_pull_complete (length ts) (length tus) m).
      { eapply test_range_true_all.
        generalize dependent (length tus).
        generalize dependent m.
        induction (length ts); intros.
        { reflexivity. }
        { simpl.
          consider (amap_lookup n0 m).
          { intros.
            eapply IHn.
            - erewrite cardinal_remove in H1; eauto.
            - red. intros. red. intros.
              unfold amap_lookup in H0.
              rewrite SUBST.PROPS.F.remove_o in H0.
              destruct (SUBST.PROPS.F.eq_dec n0 u); try congruence.
              eapply H2 in H0. omega. }
          { intros. exfalso.
            assert (only_in_range (S n0) n m).
            { red. red; intros. red in H2.
              consider (n0 ?[ eq ] u); intros; subst; try congruence.
              eapply H2 in H0. omega. }
            eapply cardinal_le_range in H0. omega. } }  }
      rewrite H. eexists; split; eauto.
      eapply subst_pull_sound in H.
      assert (only_in_range (length tus) 0 x).
      { forward_reason.
        red. red. intros.
        exfalso.
        assert ((u < length tus \/ u >= length tus + length ts) \/
                (exists u', u' < length ts /\ u = length tus + u')).
        { consider (u ?[ lt ] length tus); try auto; intros.
          consider (u ?[ ge ] (length tus + length ts)); try auto; intros.
          right. exists (u - length tus). split; try omega. }
        destruct H6.
        { rewrite <- H3 in H5; eauto.
          eapply H2 in H5. omega. }
        { forward_reason. subst.
          red in H.
          rewrite H in H5. congruence. auto. } }
      { eapply  only_in_range_0_empty in H0.
        rewrite H0.
        eapply UVarMap.MAP.empty_1. } }
    { forward_reason.
      eapply pull_sound in H2; eauto using SUBST.SubstOpenOk_subst.
      { forward_reason.
        specialize (@H4 tus ts tvs _ eq_refl eq_refl H0).
        forward_reason.
        exists x2. simpl. intros.
        eapply H9.
        assert (UVarMap.MAP.Equal x (UVarMap.MAP.empty expr)).
        { red. red in H3. intros.
          rewrite SUBST.FACTS.empty_o.
          eapply SUBST.FACTS.not_find_in_iff.
          red. intro. destruct H10. eapply H3.
          eauto. }
        generalize (@SUBST.raw_substD_Equal typ _ expr _ tus tvs x (UVarMap.MAP.empty _) _ H7 H10).
        destruct (SUBST.substD_empty tus tvs).
        intros.
        forward_reason.
        eapply H13; clear H13.
        change_rewrite H12 in H11. inv_all; subst. eauto. }
      { eapply WellFormed_bimap_WellFormed_amap; eauto. } }
  Qed.

End parameterized.