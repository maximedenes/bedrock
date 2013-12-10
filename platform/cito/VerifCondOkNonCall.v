Require Import CompileStmtSpec CompileStmtImpl.

Set Implicit Arguments.

Section TopSection.

  Require Import Inv.

  Variable layout : Layout.

  Variable vars : list string.

  Variable temp_size : nat.

  Variable imports : LabelMap.t assert.

  Variable imports_global : importsGlobal imports.

  Variable modName : string.

  Require Import Syntax.
  Require Import Wrap.

  Definition compile := compile layout vars temp_size imports_global modName.

  Require Import Semantics.
  Require Import Safe.
  Require Import Notations.
  Require Import SemanticsFacts.
  Require Import ScopeFacts.
  Require Import ListFacts.
  Require Import StringSet.
  Require Import SetFacts.
  Require Import CompileStmtTactics.

  Open Scope stmt.

  Opaque funcs_ok.
  Opaque mult.
  Opaque star. (* necessary to use eapply_cancel *)

  Hint Resolve Subset_in_scope_In.
  Hint Extern 0 (Subset _ _) => progress (simpl; subset_solver).
  Hint Resolve map_length.

  Set Printing Coercions.

  Require Import SemanticsExpr.
  Require Import SepHints.
  Require Import GeneralTactics.
  Require Import WordFacts.
  Require Import Arith.
  Require Import InvFacts.
  Require Import VerifCondOkTactics.

  Open Scope nat.

  Lemma verifCond_ok_skip : 
    forall k (pre : assert),
      let s := skip in
      vcs (verifCond layout vars temp_size s k pre) ->
      vcs
        (VerifCond (compile s k pre)).
  Proof.

    unfold verifCond, imply.

    (* skip *)
    wrap0.

  Qed.

  Lemma verifCond_ok_seq : 
    forall s1 s2
           (IHs1 : forall (k : Stmt) (pre : assert),
                     vcs
                       ((forall (specs : codeSpec W (settings * state))
                                (x : settings * state),
                           interp specs (pre x) ->
                           interp specs (precond layout vars temp_size s1 k x))
                          :: in_scope vars temp_size (s1;; k) :: nil) ->
                     vcs (VerifCond (compile s1 k pre)))
           (IHs2 : forall (k : Stmt) (pre : assert),
                     vcs
                       ((forall (specs : codeSpec W (settings * state))
                                (x : settings * state),
                           interp specs (pre x) ->
                           interp specs (precond layout vars temp_size s2 k x))
                          :: in_scope vars temp_size (s2;; k) :: nil) ->
                     vcs (VerifCond (compile s2 k pre)))
           k (pre : assert),
      let s := s1 ;; s2 in
      vcs (verifCond layout vars temp_size s k pre) ->
      vcs
        (VerifCond (compile s k pre)).
  Proof.

    unfold verifCond, imply.
    intros.

    (* seq *)
    Require PostOk.

    wrap0.
    eapply IHs1.
    wrap0.
    eapply H2 in H.
    unfold precond in *.
    unfold inv in *.
    unfold inv_template in *.
    post.
    descend; eauto.
    eapply Safe_Seq_assoc; eauto.
    repeat hiding ltac:(step auto_ext).
    descend.
    eapply RunsTo_Seq_assoc; eauto.
    eapply in_scope_Seq_Seq; eauto.

    eapply IHs2.
    wrap0.
    unfold TopSection.compile in H.
    eapply PostOk.post_ok in H.
    unfold postcond in *.
    unfold inv in *.
    unfold inv_template in *.
    post.

    unfold verifCond in *.
    unfold imply in *.
    wrap0.
    eapply H2 in H0.
    unfold precond in *.
    unfold inv in *.
    unfold inv_template in *.
    post.
    descend; eauto.
    eapply Safe_Seq_assoc; eauto.
    repeat hiding ltac:(step auto_ext).
    descend.
    eapply RunsTo_Seq_assoc; eauto.
    eapply in_scope_Seq_Seq; eauto.
    eapply in_scope_Seq; eauto.

  Qed.

  Lemma verifCond_ok_if : 
    forall e s1 s2
           (IHs1 : forall (k : Stmt) (pre : assert),
                     vcs
                       ((forall (specs : codeSpec W (settings * state))
                                (x : settings * state),
                           interp specs (pre x) ->
                           interp specs (precond layout vars temp_size s1 k x))
                          :: in_scope vars temp_size (s1;; k) :: nil) ->
                     vcs (VerifCond (compile s1 k pre)))
           (IHs2 : forall (k : Stmt) (pre : assert),
                     vcs
                       ((forall (specs : codeSpec W (settings * state))
                                (x : settings * state),
                           interp specs (pre x) ->
                           interp specs (precond layout vars temp_size s2 k x))
                          :: in_scope vars temp_size (s2;; k) :: nil) ->
                     vcs (VerifCond (compile s2 k pre)))
           k (pre : assert),
           let s := Syntax.If e s1 s2 in
      vcs (verifCond layout vars temp_size s k pre) ->
      vcs
        (VerifCond (compile s k pre)).
  Proof.

    unfold verifCond, imply.
    intros.

    (* if *)
    wrap0.
    unfold CompileExpr.imply in *.
    unfold CompileExpr.new_pre in *.
    unfold CompileExpr.is_state in *.
    intros.
    eapply H2 in H.
    unfold precond in *.
    unfold inv in *.
    unfold inv_template in *.
    unfold is_state in *.
    post.
    descend.
    repeat hiding ltac:(step auto_ext).
    eauto.
    eapply in_scope_If_e; eauto.

    unfold evalCond in *.
    simpl in *.
    discriminate H0.

    (* true *)
    eapply IHs1.
    wrap0.
    eapply H2 in H0.
    unfold precond in *.
    unfold inv in *.
    unfold inv_template in *.
    unfold is_state in *.
    unfold CompileExpr.runs_to in *.
    unfold CompileExpr.is_state in *.
    post.
    transit.
    destruct_state.
    post.
    hide_upd_sublist.
    descend.
    eauto.
    instantiate (5 := (_, _)); simpl.
    instantiate (6 := l).
    unfold_all; repeat rewrite length_upd_sublist.
    repeat hiding ltac:(step auto_ext).
    find_cond.
    eapply Safe_Seq_If_true; eauto.
    unfold_all; rewrite length_upd_sublist; eauto.
    eauto.
    eauto.

    repeat hiding ltac:(step auto_ext).

    descend.
    find_cond.
    eapply RunsTo_Seq_If_true; eauto.
    eapply in_scope_If_true; eauto.

    (* false *)
    eapply IHs2.
    wrap0.
    eapply H2 in H0.
    unfold precond in *.
    unfold inv in *.
    unfold inv_template in *.
    unfold is_state in *.
    unfold CompileExpr.runs_to in *.
    unfold CompileExpr.is_state in *.
    post.
    transit.
    destruct_state.
    post.
    hide_upd_sublist.
    descend.
    eauto.
    instantiate (5 := (_, _)); simpl.
    instantiate (6 := l).
    unfold_all; repeat rewrite length_upd_sublist.
    repeat hiding ltac:(step auto_ext).
    find_cond.
    eapply Safe_Seq_If_false; eauto.
    unfold_all; rewrite length_upd_sublist; eauto.
    eauto.
    eauto.

    repeat hiding ltac:(step auto_ext).

    descend.
    find_cond.
    eapply RunsTo_Seq_If_false; eauto.
    eapply in_scope_If_false; eauto.

  Qed.

  Lemma verifCond_ok_while : 
    forall e s
           (IHs : forall (k : Stmt) (pre : assert),
                    vcs
                      ((forall (specs : codeSpec W (settings * state))
                               (x : settings * state),
                          interp specs (pre x) ->
                          interp specs (precond layout vars temp_size s k x))
                         :: in_scope vars temp_size (s;; k) :: nil) ->
                    vcs (VerifCond (compile s k pre)))
           k (pre : assert),
      let s := Syntax.While e s in
      vcs (verifCond layout vars temp_size s k pre) ->
      vcs
        (VerifCond (compile s k pre)).
  Proof.

    unfold verifCond, imply.
    intros.

    (* while *)
    wrap0.
    unfold CompileExpr.imply in *.
    unfold CompileExpr.new_pre in *.
    unfold CompileExpr.is_state in *.
    intros.
    eapply H2 in H.
    unfold precond in *.
    unfold inv in *.
    unfold inv_template in *.
    unfold is_state in *.
    post.
    descend.
    repeat hiding ltac:(step auto_ext).
    eauto.
    eapply in_scope_While_e; eauto.

    eapply H2 in H0.
    unfold precond in *.
    unfold inv in *.
    unfold inv_template in *.
    unfold is_state in *.
    unfold CompileExpr.runs_to in *.
    unfold CompileExpr.is_state in *.
    post.
    transit.
    destruct_state.
    post.
    hide_upd_sublist.
    descend.
    eauto.
    instantiate (5 := (_, _)); simpl.
    instantiate (6 := l).
    unfold_all; repeat rewrite length_upd_sublist.
    repeat hiding ltac:(step auto_ext).
    eauto.
    unfold_all; rewrite length_upd_sublist; eauto.
    eauto.
    eauto.

    repeat hiding ltac:(step auto_ext).

    descend.

    unfold evalCond in *.
    simpl in *.
    discriminate H0.

    unfold TopSection.compile in H0.
    eapply PostOk.post_ok in H0.
    unfold postcond in *.
    unfold inv in *.
    unfold inv_template in *.
    unfold is_state in *.
    unfold CompileExpr.runs_to in *.
    unfold CompileExpr.is_state in *.
    post.
    transit.
    destruct_state.
    post.
    hide_upd_sublist.
    descend.
    eauto.
    instantiate (5 := (_, _)); simpl.
    instantiate (6 := l).
    unfold_all; repeat rewrite length_upd_sublist.
    repeat hiding ltac:(step auto_ext).
    eauto.
    unfold_all; rewrite length_upd_sublist; eauto.
    eauto.
    eauto.

    repeat hiding ltac:(step auto_ext).

    descend.

    unfold verifCond in *.
    unfold imply in *.
    wrap0.
    post.
    descend; eauto.
    find_cond.
    eapply Safe_Seq_While_true; eauto.

    repeat hiding ltac:(step auto_ext).

    descend.
    find_cond.
    eapply RunsTo_Seq_While_true; eauto.
    eapply in_scope_While; eauto.

    eapply IHs.
    wrap0.
    post.
    descend; eauto.
    find_cond.
    eapply Safe_Seq_While_true; eauto.

    repeat hiding ltac:(step auto_ext).

    descend.
    find_cond.
    eapply RunsTo_Seq_While_true; eauto.
    eapply in_scope_While; eauto.

    unfold CompileExpr.verifCond in *.
    unfold CompileExpr.imply in *.
    wrap0.
    unfold TopSection.compile in H.
    eapply PostOk.post_ok in H.
    unfold postcond in *.
    unfold inv in *.
    unfold inv_template in *.
    unfold is_state in *.
    unfold CompileExpr.is_state in *.
    post.
    descend.
    repeat hiding ltac:(step auto_ext).
    eauto.

    unfold verifCond in *.
    unfold imply in *.
    wrap0.
    post.
    descend; eauto.
    find_cond.
    eapply Safe_Seq_While_true; eauto.

    repeat hiding ltac:(step auto_ext).

    descend.
    find_cond.
    eapply RunsTo_Seq_While_true; eauto.
    eapply in_scope_While; eauto.

    eapply in_scope_While_e; eauto.

  Qed.

End TopSection.