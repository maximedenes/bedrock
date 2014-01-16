Require Import CompileStmtSpec CompileStmtImpl.

Set Implicit Arguments.

Section TopSection.

  Require Import Inv.

  Variable vars : list string.

  Variable temp_size : nat.

  Variable imports : LabelMap.t assert.

  Variable imports_global : importsGlobal imports.

  Variable modName : string.

  Require Import Syntax.
  Require Import Wrap.

  Variable rv_postcond : W -> Semantics.State -> Prop.

  Definition compile := compile vars temp_size imports_global modName rv_postcond.

  Lemma post_ok : 
    forall (s k : Stmt) (pre : assert) (specs : codeSpec W (settings * state))
           (x : settings * state),
      vcs (verifCond vars temp_size s k rv_postcond pre) ->
      interp specs
             (Postcondition
                (compile s k pre) x) ->
      interp specs (postcond vars temp_size k rv_postcond x).
  Proof.

    Require Import Semantics.
    Require Import Safe.
    Require Import Notations.
    Require Import SemanticsFacts.
    Require Import SynReqFacts.
    Require Import ListFacts.
    Require Import StringSet.
    Require Import SetFacts.
    Require Import CompileStmtTactics.
    Require Import GeneralTactics.
    Require Import WordFacts.
    Require Import SemanticsFacts3.
    Require Import SynReqFacts2.

    Open Scope stmt.

    Opaque funcs_ok.
    Opaque mult.
    Opaque star. (* necessary to use eapply_cancel *)

    Hint Resolve Subset_syn_req_In.
    Hint Extern 0 (Subset _ _) => progress (simpl; subset_solver).

    Set Printing Coercions.

    Ltac auto_apply :=
      match goal with
          H : _ |- _ => eapply H
      end.

    unfold verifCond, imply; induction s.

    Focus 6.
    wrap0.
    eapply H3 in H0.
    unfold precond in *.
    unfold inv in *.
    unfold inv_template in *.
    unfold is_state in *.
    post.
    unfold var_slot in *.
    unfold vars_start in *.
    destruct_state.
    Ltac inversion_Safe :=
      repeat match goal with
               | H : Safe _ _ _ |- _ => inversion H; clear H; subst
             end.

    inversion_Safe.
    Ltac auto_apply_in t :=
      match goal with
          H : _ |- _ => eapply t in H
      end.

    auto_apply_in ex_up.
    openhyp.
    simpl in *.
    rewrite_natToW_plus.
    assert (List.In s vars) by (eapply syn_req_Label_in; eauto).
    assert (
        evalInstrs s0 x0
                   (IL.Assign 
                      (LvMem (Imm (Regs x0 Sp ^+ $8 ^+ $(variablePosition vars s))))
                      (RvImm x) :: nil) =
        Some s1
) ; [ | clear H1 ].
    rewrite <- H1.
    Transparent evalInstrs.
    simpl.
    repeat rewrite wplus_assoc in *.
    Require Import ConvertLabel.
    unfold from_bedrock_label_map in *.
    rewrite H.
    eauto.
    Opaque evalInstrs.
    unfold from_bedrock_label_map in *.
    hiding ltac:(evaluate auto_ext).
    descend.
    eauto.
    instantiate (6 := (_, _)); simpl.
    match goal with
      | H : Regs s1 Sp = _ |- _ => rewrite H in *
    end.
    repeat hiding ltac:(step auto_ext).
    auto_apply.
    econstructor; simpl; eauto.
    eauto.
    eauto.
    eauto.

    repeat hiding ltac:(step auto_ext).
    descend.
    eapply RunsTo_Seq_Label; eauto.

    Focus 6.
    wrap0.
    eapply H3 in H0.
    unfold precond in *.
    unfold inv in *.
    unfold inv_template in *.
    unfold CompileExpr.runs_to in *.
    unfold is_state in *.
    unfold CompileExpr.is_state in *.
    post.

    transit.

    destruct_state.
    post.
    unfold var_slot in *.
    unfold vars_start in *.
    rewrite_natToW_plus.
    assert (List.In s vars) by (eapply syn_req_Assign_in; eauto).
    assert (
        evalInstrs s0 x0
                   (IL.Assign 
                      (LvMem (Imm (Regs x0 Sp ^+ $8 ^+ $(variablePosition vars s))))
                      Rv :: nil) =
        Some s1
) ; [ | clear H1 ].
    rewrite <- H1.
    Transparent evalInstrs.
    simpl.
    repeat rewrite wplus_assoc in *.
    eauto.
    Opaque evalInstrs.
    hiding ltac:(evaluate auto_ext).
    descend.
    eauto.
    instantiate (6 := (_, _)); simpl.
    instantiate (7 := upd_sublist _ _ _).
    rewrite length_upd_sublist.
    match goal with
      | H : Regs s1 Sp = _ |- _ => rewrite H in *
    end.
    match goal with
      | H : Regs x0 Sp = _ |- _ => rewrite H in *
    end.
    repeat hiding ltac:(step auto_ext).
    inversion_Safe.
    auto_apply.
    econstructor; simpl; eauto.
    rewrite length_upd_sublist; eauto.
    eauto.
    eauto.

    repeat hiding ltac:(step auto_ext).
    descend.
    eapply RunsTo_Seq_Assign; eauto.

    Focus 5.
    (* call *)
    wrap0.
    post.
    destruct_state.
    hiding ltac:(evaluate auto_ext).
    unfold is_state in *.
    unfold frame_len_w in *.
    unfold frame_len in *.
    unfold temp_start in *.
    unfold var_slot in *.
    unfold vars_start in *.
    unfold SaveRet.runs_to in *.
    unfold SaveRet.is_state in *.
    simpl in *.
    transit.
    openhyp.
    descend.
    eauto.
    instantiate (6 := (_, _)); simpl.
    rewrite <- H in *.
    rewrite <- H1 in *.
    instantiate (6 := heap_upd_option (heap_merge x5 x6) x10 x11).
    set (upd_option _ _ _) in H11.

    repeat hiding ltac:(step auto_ext).

    Require Import LayoutHints3.
    set (h := heap_merge _ _) in *.
    replace (is_heap (heap_upd_option _ _ _)) with (is_heap_upd_option h x10 x11) by (unfold is_heap_upd_option; eauto).
    hiding ltac:(step hints_heap_upd_option).
    unfold_all.

    replace (is_heap (heap_merge _ _)) with (is_heap_merge x5 x6) by (unfold is_heap_merge; eauto).
    hiding ltac:(step hints_heap_merge).

    match goal with
      | H : Regs _ Rv = _ |- _ => rewrite H in *
    end.
    auto_apply.
    rearrange_stars (is_heap x5 * is_heap x6 * layout_option x10 x11)%Sep.
    eapply star_merge_separated; eauto.
    eauto.
    eauto.
    eauto.

    repeat hiding ltac:(step auto_ext).

    descend.
    rearrange_stars (is_heap x5 * is_heap x6 * layout_option x10 x11)%Sep.
    eapply star_merge_separated; eauto.

    (* skip *)

    intros.
    wrap0.
    eapply H3 in H0.
    unfold precond in *.
    unfold inv in *.
    unfold inv_template in *.
    post.
    descend.
    eauto.
    eauto.

    eapply Safe_Seq_Skip; eauto.
    eauto.
    eauto.
    eauto.

    repeat hiding ltac:(step auto_ext).
    descend.
    eapply RunsTo_Seq_Skip; eauto.

    (* seq *)
    wrap0.
    eapply IHs2 in H0.
    unfold postcond in *.
    unfold inv in *.
    unfold inv_template in *.
    post.

    wrap0.
    eapply IHs1 in H.
    unfold postcond in *.
    unfold inv in *.
    unfold inv_template in *.
    post.

    wrap0.
    eapply H3 in H1.
    unfold precond in *.
    unfold inv in *.
    unfold inv_template in *.
    post.
    descend.
    eauto.
    eauto.
    eapply Safe_Seq_assoc; eauto.

    eauto.
    eauto.
    eauto.
    repeat hiding ltac:(step auto_ext).
    descend.
    eapply RunsTo_Seq_assoc; eauto.
    eapply syn_req_Seq_Seq; eauto.
    eapply syn_req_Seq; eauto.

    (* if - true *)
    wrap0.
    eapply IHs1 in H.
    unfold postcond in *.
    unfold inv in *.
    unfold inv_template in *.
    post.

    wrap0.
    eapply H3 in H1.
    unfold precond in *.
    unfold inv in *.
    unfold inv_template in *.
    unfold CompileExpr.runs_to in *.
    unfold is_state in *.
    unfold CompileExpr.is_state in *.
    post.

    transit.

    destruct_state.
    post.
    descend.
    eauto.
    instantiate (6 := (_, _)).
    simpl.
    instantiate (7 := upd_sublist _ _ _).
    rewrite length_upd_sublist.
    repeat hiding ltac:(step auto_ext).

    find_cond.
    eapply Safe_Seq_If_true; eauto.
    rewrite length_upd_sublist; eauto.
    eauto.
    eauto.

    repeat hiding ltac:(step auto_ext).

    descend.
    find_cond.
    eapply RunsTo_Seq_If_true; eauto.
    eapply syn_req_If_true; eauto.

    (* if - false *)
    wrap0.
    eapply IHs2 in H.
    unfold postcond in *.
    unfold inv in *.
    unfold inv_template in *.
    post.

    wrap0.
    eapply H3 in H1.
    unfold precond in *.
    unfold inv in *.
    unfold inv_template in *.
    unfold CompileExpr.runs_to in *.
    unfold is_state in *.
    unfold CompileExpr.is_state in *.
    post.

    transit.

    destruct_state.
    post.
    descend.
    eauto.
    instantiate (6 := (_, _)).
    simpl.
    instantiate (7 := upd_sublist _ _ _).
    rewrite length_upd_sublist.
    repeat hiding ltac:(step auto_ext).

    find_cond.
    eapply Safe_Seq_If_false; eauto.
    rewrite length_upd_sublist; eauto.
    eauto.
    eauto.

    repeat hiding ltac:(step auto_ext).

    descend.
    find_cond.
    eapply RunsTo_Seq_If_false; eauto.
    eapply syn_req_If_false; eauto.

    (* while *)
    wrap0.
    post.
    descend.
    eauto.
    eauto.
    find_cond.
    eapply Safe_Seq_While_false; eauto.
    eauto.
    eauto.
    eauto.
    repeat hiding ltac:(step auto_ext).
    descend.
    find_cond.
    eapply RunsTo_Seq_While_false; eauto.

  Qed.

End TopSection.