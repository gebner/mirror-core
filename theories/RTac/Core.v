Require Import ExtLib.Structures.Monad.
Require Import ExtLib.Structures.Traversable.
Require Import ExtLib.Data.Prop.
Require Import ExtLib.Data.Monads.OptionMonad.
Require Import ExtLib.Tactics.
Require Import MirrorCore.EnvI.
Require Import MirrorCore.ExprI.
Require Import MirrorCore.TypesI.
Require Import MirrorCore.SubstI.
Require Import MirrorCore.ExprDAs.

Require Import MirrorCore.Util.Forwardy.

Set Implicit Arguments.
Set Strict Implicit.

Section parameterized.
  Variable typ : Type.
  Variable expr : Type.
  Variable subst : Type.

  Context {RType_typ : RType typ}.
  Context {Expr_expr : Expr RType_typ expr}.
  Context {Typ0_Prop : Typ0 _ Prop}.
  Context {Subst_subst : Subst subst expr}.
  Context {SubstOk_subst : @SubstOk _ _ _ _ Expr_expr Subst_subst}.
  Context {SubstUpdate_subst : SubstUpdate subst expr}.
  Context {SubstUpdateOk_subst : @SubstUpdateOk _ _ _ _ Expr_expr Subst_subst _ _}.


  (** NOTE: It seems for performance this should be inverted, otherwise
   ** every operation is going to be expensive.
   **)
  Inductive Goal :=
  | GAll    : typ -> Goal -> Goal
  | GEx     : typ -> option expr -> Goal -> Goal
  | GHyp    : expr -> Goal -> Goal
  | GConj   : list Goal -> Goal
  | GGoal   : expr -> Goal
  | GSolved : Goal.

  Inductive Ctx :=
  | CTop
  | CAll : Ctx -> typ -> Ctx
  | CEx  : Ctx -> typ -> Ctx
  | CHyp : Ctx -> expr -> Ctx.

  (** StateT subst Option Goal **)
  Inductive Result :=
  | Fail
  | More   : subst -> Goal -> Result
  | Solved : subst -> Result.

  (** Treat this as opaque! **)
  Definition rtac : Type :=
    Ctx -> subst -> expr -> Result.

  Fixpoint countVars' (ctx : Ctx) acc : nat :=
    match ctx with
      | CTop => acc
      | CAll ctx' t => countVars' ctx' (S acc)
      | CEx  ctx' _
      | CHyp ctx' _ => countVars' ctx' acc
    end.

  Fixpoint countUVars' (ctx : Ctx) acc : nat :=
    match ctx with
      | CTop => acc
      | CEx  ctx' t => countUVars' ctx' (S acc)
      | CAll ctx' _
      | CHyp ctx' _ => countUVars' ctx' acc
    end.

  Definition countVars ctx := countVars' ctx 0.
  Definition countUVars ctx := countUVars' ctx 0.

  Definition mapUnderEx (t : typ) (nus : nat) (r : Result) : Result :=
    match r with
      | Fail => Fail
      | Solved s' =>
        match lookup nus s' with
          | None => let s'' := s' in
                    More s'' (GEx t None GSolved)
          | Some e =>
            match drop nus s' with
              | None => Fail (** DEAD **)
              | Some s'' => Solved s''
            end
        end
      | More s' g' =>
        match lookup nus s' with
          | None => let s'' := s' in
                    More s' (GEx t None g')
          | Some e =>
            match drop nus s' with
              | None => (** DEAD **) Fail
              | Some s'' => More s'' (GEx t (Some e) g')
            end
        end
    end.

  Section runRTac'.
    Variable tac : rtac.

    Fixpoint runRTac' (ctx : Ctx) (s : subst) (g : Goal) (nus nvs : nat) {struct g}
    : Result :=
      match g with
        | GGoal e => tac ctx s e
        | GSolved => Solved s
        | GAll t g =>
          match runRTac' (CAll ctx t) s g nus (S nvs) with
            | Fail => Fail
            | Solved s => Solved s
            | More s g => More s (GAll t g)
          end
        | GEx  t None g =>
          mapUnderEx t nus (runRTac' (CEx  ctx t) s g (S nus) nvs)
        | GEx  t (Some e) g =>
          match set nus e s with
            | None => Fail (** DEAD **)
            | Some s' =>
              mapUnderEx t nus (runRTac' (CEx  ctx t) s' g (S nus) nvs)
          end
        | GHyp h g =>
          match runRTac' (CHyp ctx h) s g nus nvs with
            | Fail => Fail
            | Solved s => Solved s
            | More s g => More s (GHyp h g)
          end
        | GConj gs =>
          (fix do_each (gs : list Goal) (s : subst)
               (acc : list Goal -> subst -> Result)
           : Result :=
             match gs with
               | nil => acc nil s
               | g :: gs =>
                 match runRTac' ctx s g nus nvs with
                   | Fail => Fail
                   | Solved s => do_each gs s acc
                   | More s g =>
                     do_each gs s (fun other s => acc (g :: other) s)
                 end
             end) gs s
                  (fun rem s =>
                     match rem with
                       | nil => Solved s
                       | _ :: _ => More s (GConj rem)
                     end)
      end.

    Definition runRTac (ctx : Ctx) (s : subst) (g : Goal)
    : Result :=
      runRTac' ctx s g (countVars ctx) (countUVars ctx).
  End runRTac'.


  Definition propD := @exprD'_typ0 _ _ _ _ Prop _.

  Fixpoint _foralls (ls : list typ)
  : (HList.hlist typD ls -> Prop) -> Prop :=
    match ls as ls return (HList.hlist typD ls -> Prop) -> Prop with
      | nil => fun P => P HList.Hnil
      | l :: ls => fun P => forall x : typD l,
                              _foralls (fun z => P (HList.Hcons x z))
    end.

  Fixpoint _exists (ls : list typ)
  : (HList.hlist typD ls -> Prop) -> Prop :=
    match ls as ls return (HList.hlist typD ls -> Prop) -> Prop with
      | nil => fun P => P HList.Hnil
      | l :: ls => fun P => exists x : typD l,
                              _exists (fun z => P (HList.Hcons x z))
    end.

  Fixpoint _impls (ls : list Prop) (P : Prop) :=
    match ls with
      | nil => P
      | l :: ls => l -> _impls ls P
    end.

  Section _and.
    Context {A B : Type}.
    Variables (a : A) (b : B).
    Fixpoint _and (ls : list (A -> B -> Prop)) :=
      match ls with
        | nil => True
        | l :: nil => l a b
        | l :: ls => l a b /\ _and ls
      end.
  End _and.


  Fixpoint WellFormed_goal (goal : Goal) : Prop :=
    match goal with
      | GAll _ goal' => WellFormed_goal goal'
      | GEx t e goal' => False (** TODO: This isn't going to work, maybe we need to coalesce... **)
      | GHyp _ goal' => WellFormed_goal goal'
      | GGoal _ => True
      | GSolved => True
      | GConj ls =>
        (fix Forall (ls : list Goal) : Prop :=
           match ls with
             | nil => True
             | l :: ls => WellFormed_goal l /\ Forall ls
           end) ls
    end.

  (** NOTE:
   ** Appending the newly introduced terms makes tactics non-local.
   ** Requiring globalness seems bad.
   ** - The alternative, however, is to expose a lot more operations
   **   on substitute
   **)
  Fixpoint goalD (tus tvs : list typ) (goal : Goal) {struct goal}
  : ResType tus tvs Prop.
  refine
    match goal with
      | GAll tv goal' =>
        match goalD tus (tvs ++ tv :: nil) goal' with
          | None => None
          | Some D =>
            Some (fun us vs => @_foralls (tv :: nil) (fun vs' => D us (HList.hlist_app vs vs')))
        end
      | GEx tu e goal' =>
        match goalD (tus ++ tu :: nil) tvs goal' with
          | None => None
          | Some D =>
            match e with
              | None =>
                Some (fun us vs => @_exists (tu :: nil)
                        (fun us' => D (HList.hlist_app us us') vs))
              | Some e =>
                match exprD' tus tvs e tu with
                  | None => None
                  | Some eD =>
                    Some (fun us vs =>
                           D (HList.hlist_app us
                                (HList.Hcons (eD us vs) HList.Hnil)) vs)
                end
            end
        end
      | GHyp hyp' goal' =>
        match mapT (T:=list) (F:=option) (propD tus tvs) (hyp' :: nil) with
          | None => None
          | Some hs =>
            match goalD tus tvs goal' with
              | None => None
              | Some D =>
                Some (fun us vs => _impls (map (fun x => x us vs) hs) (D us vs))
            end
        end
      | GConj ls =>
        (** This is actually:
        match mapT (T:=list) (F:=option) (goalD tus tvs) ls with
          | None => None
          | Some lD =>
            Some (fun us vs => _and us vs lD)
        end
        **)
        (fix mapT gs : option (HList.hlist _ tus -> HList.hlist _ tvs -> Prop) :=
           match gs with
             | nil => Some (fun _ _ => True)
             | g :: gs => match goalD tus tvs g
                              , mapT gs
                          with
                            | Some gD , Some gsD =>
                              Some (fun us vs => gD us vs /\ gsD us vs)
                            | _ , _ => None
                          end
           end) ls
      | GSolved => Some (fun _ _ => True)
      | GGoal goal' => propD tus tvs goal'
    end.
  Defined.

  Definition OpenT (tus tvs : tenv typ) (T : Type) : Type :=
    HList.hlist typD tus -> HList.hlist typD tvs -> T.

  Section ctxD.
    Variable P : forall (tus' tvs' : tenv typ),
                   unit + option (OpenT tus' tvs' Prop).


    Fixpoint ctxD (tus tvs : tenv typ) (ctx : Ctx) {struct ctx}
    : unit + option (OpenT tus tvs Prop) :=
      match ctx with
        | CTop => P tus tvs
        | CEx ctx' t =>
          match ctxD (tus ++ t :: nil) tvs ctx' with
            | inr (Some PD) =>
              (** The [forall] here is on purpose, [ctxD] is used to construct
               ** holes and in holes, everything is a variable
               **)
              inr (Some (fun us vs => forall x : typD t,
                           PD (HList.hlist_app us (HList.Hcons x HList.Hnil))
                              vs))
            | inl x => inl x
            | inr None => inr None
          end
        | CAll ctx' t =>
          match ctxD tus (tvs ++ t :: nil) ctx' with
            | inr (Some PD) =>
              inr (Some (fun us vs => forall x : typD t,
                           PD us
                              (HList.hlist_app vs (HList.Hcons x HList.Hnil))))
            | inl x => inl x
            | inr None => inr None
          end
        | CHyp ctx' h =>
          match propD tus tvs h with
            | None => inl tt
            | Some hD =>
              match ctxD tus tvs ctx' with
                | inr (Some PD) =>
                  inr (Some (fun us vs => hD us vs -> PD us vs))
                | inl x => inl x
                | inr None => inr None
              end
          end
      end.
  End ctxD.

  Definition rtac_sound (tus tvs : tenv typ) (tac : rtac) : Prop :=
    forall ctx s g result,
      tac ctx s g = result ->
      match result with
        | Fail => True
        | Solved s' =>
          WellFormed_subst s ->
          WellFormed_subst s' /\
          match ctxD (fun tus' tvs' =>
                        match propD tus' tvs' g
                            , substD tus' tvs' s
                            , substD tus' tvs' s'
                        with
                          | None , _ , _ => inl tt
                          | Some _ , None , _ => inl tt
                          | Some _ , Some _ , None => inr None
                          | Some gD , Some sD , Some sD' =>
                            inr (Some (fun us vs =>
                                         sD' us vs ->
                                         sD us vs /\ gD us vs))
                        end)
                     tus tvs ctx
          with
            | inl _ => True
            | inr None => False
            | inr (Some gD) => forall us vs, gD us vs
          end
        | More s' g' =>
          WellFormed_subst s ->
          WellFormed_subst s' /\
          match ctxD (fun tus' tvs' =>
                        match propD tus' tvs' g
                            , substD tus' tvs' s
                            , goalD tus' tvs' g'
                            , substD tus' tvs' s'
                        with
                          | None , _ , _ , _
                          | Some _ , None , _ , _ => inl tt
                          | Some _ , Some _ , None , _
                          | Some _ , Some _ , Some _ , None => inr None
                          | Some gD , Some sD , Some gD' , Some sD' =>
                            inr (Some (fun us vs =>
                                         sD' us vs -> gD' us vs ->
                                         sD us vs /\ gD us vs))
                        end)
                     tus tvs ctx
          with
            | inl _ => True
            | inr None => False
            | inr (Some gD) => forall us vs, gD us vs
          end
      end.

(*
  Section at_bottom.
    Variable m : Type -> Type.
    Context {Monad_m : Monad m}.
    Variable gt : list typ -> list typ -> subst -> option expr -> m Goal.

    Let under (gt : Goal -> Goal) (x : m Goal) : m Goal :=
      bind x (fun x => ret (gt x)).

    Fixpoint at_bottom tus tvs (g : Goal) : m Goal :=
      match g with
        | GAll x g' => under (GAll x) (at_bottom tus (tvs ++ x :: nil) g')
        | GEx  x g' => under (GEx  x) (at_bottom (tus ++ x :: nil) tvs g')
        | GHyp x g' => under (GHyp x) (at_bottom tus tvs g')
        | GGoal s e => gt tus tvs s e
      end.
  End at_bottom.
*)
  Lemma goalD_conv
  : forall tus tvs tus' tvs' (pfu : tus' = tus) (pfv : tvs' = tvs),
      goalD tus tvs =
      match pfu in _ = t
            return Goal -> option (HList.hlist _ t -> _) with
        | eq_refl =>
          match pfv in _ = t
                return Goal -> option (_ -> HList.hlist _ t -> _) with
            | eq_refl => goalD tus' tvs'
          end
      end.
  Proof.
    clear. destruct pfu; destruct pfv. reflexivity.
  Qed.

  Lemma _impls_sem
  : forall ls P,
      _impls ls P <-> (Forall (fun x => x) ls -> P).
  Proof.
    induction ls; simpl; intros.
    + intuition.
    + rewrite IHls. intuition.
      inversion H0. eapply H; eauto.
  Qed.
  Lemma _exists_iff
  : forall ls P Q,
      (forall x, P x <-> Q x) ->
      (@_exists ls P <-> @_exists ls Q).
  Proof.
    clear.
    induction ls; simpl; intros.
    + eapply H.
    + apply exists_iff; intro. eapply IHls.
      intro; eapply H.
  Qed.
  Lemma _forall_iff
  : forall ls P Q,
      (forall x, P x <-> Q x) ->
      (@_foralls ls P <-> @_foralls ls Q).
  Proof.
    clear.
    induction ls; simpl; intros.
    + eapply H.
    + apply forall_iff; intro. eapply IHls.
      intro; eapply H.
  Qed.

(*
  Lemma at_bottom_sound_option
  : forall goal tus tvs f goal',
      (forall tus' tvs' s e e',
         f (tus ++ tus') (tvs ++ tvs') s e = Some e' ->
         WellFormed_subst s ->
         match goalD (tus ++ tus') (tvs ++ tvs') (GGoal s e)
             , goalD (tus ++ tus') (tvs ++ tvs') e'
         with
           | None , _ => True
           | Some _ , None => False
           | Some g , Some g' =>
             forall us vs,
               g' us vs -> g us vs
         end) ->
      at_bottom f tus tvs goal = Some goal' ->
      forall (Hwf : WellFormed_goal goal),
      match goalD tus tvs goal
          , goalD tus tvs goal'
      with
        | None , _ => True
        | Some _ , None => False
        | Some g , Some g' =>
          forall us vs,
            g' us vs -> g us vs
      end.
  Proof.
    induction goal; simpl; intros.
    { forwardy. inv_all; subst.
      eapply IHgoal in H0; clear IHgoal; auto.
      { simpl. forward. auto. }
      { intros.
        specialize (H tus' (t :: tvs') s e).
        rewrite app_ass in H1. simpl in *.
        eapply H in H1; clear H; auto.
        forward.
        rewrite substD_conv
           with (pfu := eq_refl _) (pfv := eq_sym (HList.app_ass_trans _ _ _)) in H.
        unfold propD in *.
        rewrite exprD'_typ0_conv with (pfu := eq_refl _)
             (pfv := eq_sym (HList.app_ass_trans _ _ _)) in H.
        simpl in *.
        unfold ResType in *.
        autorewrite with eq_rw in *.
        destruct e; forwardy.
        { inv_all; subst.
          rewrite H in *.
          autorewrite with eq_rw in H3.
          forwardy.
          rewrite H3 in *.
          inv_all; subst.
          rewrite goalD_conv with (pfu := eq_refl)
                                  (pfv := eq_sym (HList.app_ass_trans _ _ _)).
          simpl.
          forwardy.
          autorewrite with eq_rw.
          rewrite H1.
          intros us vs. autorewrite with eq_rw.
          clear - H4.
          match goal with
            | |- _ _ match ?X with _ => _ end ->
                 _ _ match ?Y with _ => _ end /\
                 _ _ match ?Z with _ => _ end =>
              change X with Y ; change Z with Y ; destruct Y
          end.
          eauto. }
        { rewrite H in *.
          rewrite goalD_conv with (pfu := eq_refl)
                                  (pfv := eq_sym (HList.app_ass_trans _ _ _)).
          simpl.
          forwardy.
          autorewrite with eq_rw.
          rewrite H1. intros.
          inv_all; subst.
          revert H6.
          match goal with
            | |- match ?X with _ => _ end _ _ ->
                 match ?Y with _ => _ end _ _ =>
              change Y with X ; destruct X
          end. auto. } } }
    { forwardy; inv_all; subst.
      eapply IHgoal in H0; clear IHgoal; auto.
      + simpl; forward; eauto.
        destruct H3. eauto.
      + intros.
        rewrite goalD_conv
           with (pfu := eq_sym (HList.app_ass_trans _ _ _))
                (pfv := eq_refl).
        autorewrite with eq_rw.
        simpl. forward.
        rewrite HList.app_ass_trans in H1.
        simpl in H1.
        eapply H in H1; clear H; eauto.
        destruct e; forward.
        - inv_all; subst.
          revert H7. autorewrite with eq_rw.
          eauto.
        - inv_all; subst.
          revert H6. autorewrite with eq_rw.
          eauto. }
    { forwardy; inv_all; subst.
      eapply IHgoal in H0; clear IHgoal; eauto.
      + simpl; forward; eauto.
        inv_all. subst.
        eapply _impls_sem; intro.
        eapply _impls_sem in H5; eauto. }
    { specialize (H nil nil s o goal').
      simpl in H.
      repeat rewrite HList.app_nil_r_trans in H.
      eapply H in H0; clear H; auto. }
  Qed.
*)

  Lemma _exists_sem : forall ls P,
                        _exists (ls := ls) P <->
                        exists x, P x.
  Proof.
    clear. induction ls; simpl; auto.
    - intuition. exists HList.Hnil. auto.
      destruct H. rewrite (HList.hlist_eta x) in H.
      assumption.
    - intros. split.
      + destruct 1.
        eapply IHls in H.
        destruct H. eauto.
      + destruct 1.
        exists (HList.hlist_hd x).
        eapply IHls.
        exists (HList.hlist_tl x).
        rewrite (HList.hlist_eta x) in H.
        assumption.
  Qed.
  Lemma _forall_sem : forall ls P,
                        _foralls (ls := ls) P <->
                        forall x, P x.
  Proof.
    clear. induction ls; simpl; auto.
    - intuition. rewrite (HList.hlist_eta x).
      assumption.
    - intros. split.
      + intros.
        rewrite (HList.hlist_eta x).
        eapply IHls in H.
        eapply H.
      + intros.
        eapply IHls.
        intros. eapply H.
  Qed.

(*
  Lemma at_bottom_WF_option
  : forall f,
      (forall a b c d g,
         f a b c d = Some g ->
         WellFormed_subst c ->
         WellFormed_goal g) ->
    forall g tus tvs g',
      at_bottom f tus tvs g = Some g' ->
      WellFormed_goal g ->
      WellFormed_goal g'.
  Proof.
    clear.
    induction g; simpl; intros; forwardy; inv_all; subst; simpl in *; eauto.
  Qed.
*)

(*
  Lemma WellFormed_goal_GAll
  : forall ls g,
      WellFormed_goal g <-> WellFormed_goal (fold_right GAll g ls).
  Proof.
    clear. induction ls; simpl; intros; auto.
    reflexivity.
  Qed.
  Lemma WellFormed_goal_GEx
  : forall ls g,
      WellFormed_goal g <-> WellFormed_goal (fold_right GEx g ls).
  Proof.
    clear. induction ls; simpl; intros; auto.
    reflexivity.
  Qed.
  Lemma WellFormed_goal_GHyp
  : forall ls g,
      WellFormed_goal g <-> WellFormed_goal (fold_right GHyp g ls).
  Proof.
    clear. induction ls; simpl; intros; auto.
    reflexivity.
  Qed.
*)

(*
  Instance Monad_writer_nat : Monad (fun T : Type => (T * nat)%type) :=
  { ret := fun T x => (x,0)
  ; bind := fun T U c c1 =>
              let (x,n) := c in
              let (y,n') := c1 x in
              (y,n+n')
  }.

  (** On [Proved], I need to check, that means that I probably need to do
   ** deltas so that I know where I need to pull to...
   **)
  Definition with_new_uvar (t : typ) (k : nat -> rtac)
  : rtac :=
    fun g =>
      let (g',n) :=
          at_bottom (m := fun T => (T * nat))%type
                    (fun tus _ s g => (GEx t (GGoal s g), length tus)) nil nil g
      in
      k n g'.
*)
(*
  Axiom ty : typ.
  Axiom s : subst.

  Eval compute in fun (f : nat -> rtac) => with_new_uvar ty f (GGoal s None).

  Definition with_new_var (t : typ) (k : nat -> rtac)
  : rtac :=
    fun g =>
      let (g',uv) :=
          at_bottom (fun _ tvs g => (GAll t g, length tvs)) nil nil g
      in
      k uv g'.
*)

  (** NOTE: Probably not neccessary **)
  Fixpoint closeGoal (ctx : Ctx) (s : subst) (g : Goal) (nus : nat)
  : Goal :=
    match ctx with
      | CTop => g
      | CAll c t => closeGoal c s (GAll t g) nus
      | CEx  c t =>
        closeGoal c s (GEx t (lookup nus s) g) (S nus)
      | CHyp c h => closeGoal c s (GHyp h g) nus
    end.


End parameterized.

(*
Arguments propD {typ expr _ _ _} tus tvs e : rename.
Arguments rtac_sound {typ expr subst} tus tvs tac : rename.
*)
Arguments GEx {typ expr} _ _ _ : rename.
Arguments GAll {typ expr} _ _ : rename.
Arguments GHyp {typ expr} _ _ : rename.
Arguments GConj {typ expr} _ : rename.
Arguments GGoal {typ expr} _ : rename.
Arguments GSolved {typ expr} : rename.
Arguments CTop {typ expr} : rename.
Arguments CEx {typ expr} _ _ : rename.
Arguments CAll {typ expr} _ _ : rename.
Arguments CHyp {typ expr} _ _ : rename.

Arguments Fail {typ expr subst} : rename.
Arguments More {typ expr subst} _ _ : rename.
Arguments Solved {typ expr subst} _ : rename.
