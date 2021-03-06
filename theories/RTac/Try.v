Require Import ExtLib.Tactics.
Require Import MirrorCore.RTac.Core.

Require Import MirrorCore.Util.Forwardy.

Set Implicit Arguments.
Set Strict Implicit.

Section parameterized.
  Context {typ : Type}.
  Context {expr : Type}.
  Context {RType_typ : RType typ}.
  Context {RTypeOk_typ : RTypeOk}.
  Context {Typ0_Prop : Typ0 _ Prop}.
  Context {Expr_expr : Expr typ expr}.
  Context {ExprUVar_expr : ExprUVar expr}.

  Definition TRY (tac : rtac typ expr) : rtac typ expr :=
    fun tus tvs nus nvs ctx s g =>
      match tac tus tvs nus nvs ctx s g with
        | Fail => More_ s (GGoal g)
        | x => x
      end.

  Theorem TRY_sound
  : forall tac, rtac_sound tac -> rtac_sound (TRY tac).
  Proof.
    unfold TRY, rtac_sound.
    intros; subst.
    specialize (H ctx s g _ eq_refl).
    destruct (tac (getUVars ctx) (getVars ctx)
           (length (getUVars ctx)) (length (getVars ctx)) ctx s
           g); eauto using rtac_spec_More_.
  Qed.

End parameterized.

Arguments TRY {_ _} _%rtac _ _ _ _ _ _ _.