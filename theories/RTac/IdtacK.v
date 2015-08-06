Require Import ExtLib.Data.Sum.
Require Import ExtLib.Tactics.
Require Import MirrorCore.RTac.CoreK.

Require Import MirrorCore.Util.Forwardy.

Set Implicit Arguments.
Set Strict Implicit.

Section parameterized.
  Context {typ : Type}.
  Context {expr : Type}.
  Context {RType_typ : RType typ}.
  Context {RTypeOk_typ : RTypeOk}.
  Context {Typ0_Prop : Typ0 _ Prop}.
  Context {Expr_expr : Expr RType_typ expr}.
  Context {ExprUVar_expr : ExprUVar expr}.

  Definition IDTACK : rtacK typ expr :=
    fun _ _ _ _ ctx sub gl => More_ sub gl.

  (** TODO: Move this **)
  Lemma rtacK_spec_More_
    : forall (ctx : Ctx typ expr) (s : ctx_subst ctx) g,
      rtacK_spec s g (More_ s g).
  Proof.
    red. intros. split; auto. split; auto.
    forward.
    split.
    - reflexivity.
    - intros. eapply Pure_pctxD; eauto.
  Qed.

  Theorem IDTACK_sound : rtacK_sound IDTACK.
  Proof.
    unfold IDTACK, rtacK_sound.
    intros; subst.
    eapply rtacK_spec_More_.
  Qed.

End parameterized.