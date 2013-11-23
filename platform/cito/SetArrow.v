Require Import SetInterface.
Require Import SetNotations SetFunctors.
Require Import Equalities.

Set Implicit Arguments.

Module SetArrow (Key : MiniDecidableType) <: MembershipDecidableSet Key.

  Definition set := Key.t -> bool.

  Definition mem x (s : set) := s x = true.

  Definition union (a b : set) := fun x => orb (a x) (b x).

  Lemma union_correct : forall a b x, mem x (union a b) <-> mem x a \/ mem x b.
    unfold mem, union; intuition; eapply Bool.orb_true_elim in H; destruct H; intuition.
  Qed.

  Definition diff (a b : set) := fun x => andb (a x) (negb (b x)).

  Lemma diff_correct : forall a b x, mem x (diff a b) <-> mem x a /\ ~ mem x b.
    unfold mem, diff; intuition; eapply Bool.andb_true_iff in H; destruct H; intuition; rewrite H0 in H1; intuition.
  Qed.

  Definition empty : set := fun _ => false.

  Lemma empty_correct : forall x, ~ mem x empty.
    unfold empty, mem; eauto.
  Qed.

  Definition singleton x := 
    fun x' =>
      if Key.eq_dec x' x then
        true
      else
        false.

  Lemma singleton_correct : forall x x', mem x' (singleton x) <-> x' = x.
    unfold mem, singleton; intros; destruct (Key.eq_dec x' x); intuition; intuition; discriminate.
  Qed.

  Definition mem_dec : forall x s, {mem x s} + {~ mem x s}.
    unfold mem; intros; destruct (Bool.bool_dec (s x) true); intuition.
  Qed.

  Include Notations Key.
  Include Relations Key.
  Include Util Key.

End SetArrow.