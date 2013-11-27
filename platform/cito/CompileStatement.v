Require Import DepthExpr.

Local Notation edepth := DepthExpr.depth.

Local Notation "fs ~:~ v1 ~~ s ~~> v2" := (RunsToRelax fs s v1 v2) (no associativity, at level 60).
  Local Notation "v [( e )]" := (eval (fst v) e) (no associativity, at level 60).


Section LayoutSection.

Require Import AutoSep Wrap Arith.
Require Import ExprLemmas.
Require Import VariableLemmas.
Require Import GeneralTactics.
Require Import SyntaxExpr SemanticsExpr.
Require Import Syntax Semantics.
Require Import SyntaxNotations.
Require Import RunsToRelax.
Require Import Footprint Depth.
Require Import DefineStructured.
Require Import Safety.
Require Import Malloc.

Definition good_name name := prefix name "!" = false.

  Require Import SemanticsExprLemmas.
  Require Import SemanticsLemmas.

  Lemma star_diff_ptrs : forall specs st other p1 p2, interp specs (![p1 =?>1 * p2 =?> 1 * other] st) -> p1 <> p2.
    rewrite sepFormula_eq.
    propxFo.
    subst.
    unfold smem_get_word in *.
    simpl in *.
    case_eq (smem_get p2 x3).
    intros.
    clear H6.
    case_eq (smem_get p2 x6).
    clear H9.
    intros.
    destruct H2.
    subst.
    destruct H5.
    subst.
    destruct H4.
    subst.
    Require Import Bootstrap.
    eapply disjoint_get_fwd in H2.
    eauto.
    erewrite join_Some by eassumption.
    discriminate.
    erewrite join_Some by eassumption.
    discriminate.
    intros.
    rewrite H0 in H9.
    discriminate.
    intros.
    rewrite H in H6.
    discriminate.
  Qed.

  Hint Resolve star_diff_ptrs.

  Ltac rearrange_stars HEAD :=
    match goal with
      H : interp ?SPECS (![?P] ?ST) |- _ =>
        let OTHER := fresh in 
          evar (OTHER : HProp); 
          assert (interp SPECS (![HEAD * OTHER] ST));
            unfold OTHER in *; clear OTHER;
              [ hiding ltac:(step auto_ext) | .. ]
    end.

  Infix "=~*>" := (ptsto32 nil) (at level 30).

  Import MHeap.MSet.

  Ltac auto_apply :=
    match goal with
      H : _ |- _ => eapply H
    end.

  Open Scope nat.

  Hint Rewrite sum_S : arith.
  Hint Resolve S_le_lt.
  Hint Resolve sel_upd_firstn.
  Hint Resolve firstn_S_upd.
  Hint Resolve VariableLemmas.noChange.
  Hint Resolve Max.le_max_l Max.le_max_r.
  Hint Extern 12 => rv_solver.
  Hint Extern 12 => sp_solver.
  Hint Resolve le_plus_lt lt_max_l lt_max_r.
  Hint Resolve plus_le.
  Hint Resolve lt_le_S plus_lt.

  Hint Resolve le_max_l_trans.
  Hint Resolve le_max_r_trans.
  Hint Extern 0 (_ <= _) => progress max_le_solver.
  Hint Extern 0 (List.incl _ _) => progress incl_app_solver.

  Hint Resolve in_eq In_incl.
  Hint Resolve List.incl_cons incl_cons_l incl_cons_r List.incl_refl incl_nil incl_tl incl_array.
  Hint Resolve incl_app incl_appl incl_appr.
  Hint Resolve List.incl_tran.
  Hint Resolve disjoint_trans_lr.
  Hint Resolve changedVariables_upd.
  Hint Resolve unchanged_in_except_disjoint unchanged_in_except_upd unchanged_in_except_shrink.
  Hint Constructors or.
  Hint Resolve sel_upd_eq.

  Hint Constructors RunsTo.
  Hint Constructors runs_loop_partially.
  Hint Resolve unchanged_eval.
  Hint Resolve changedVariables_upd_bwd.
  Hint Resolve unchanged_incl.
  Hint Resolve two_merge_equiv.
  Hint Resolve changed_in_upd_same.

  Hint Extern 12 (unchanged_in _ _ _) => use_changed_unchanged.
  Hint Extern 12 (unchanged_in _ _ _) => use_changed_unchanged'.
  Hint Extern 12 (changed_in _ _ _) => use_changed_trans2.
  Hint Extern 12 (changed_in _ _ _) => use_changed_incl.
  Hint Extern 12 => condition_solver'.
  Hint Extern 12 (unchanged_in _ _ _) => use_unchanged_in_symm.
  Hint Extern 12 (changed_in _ _ _) => use_changed_in_symm.

  Hint Resolve runs_loop_partially_finish.
  Hint Resolve eval_disjoint.
  Hint Resolve RunsTo_footprint.

  Hint Extern 12 (_ = _) => condition_solver.

  Ltac use_unchanged_eval :=
    match goal with
      |- eval ?E _ = eval ?E _ => eapply unchanged_eval; solve [eauto]
    end.
  Hint Extern 12 => use_unchanged_eval.

  Hint Resolve incl_tempChunk2.

  Ltac inv_Safe :=
    match goal with
      H : Safe _ _ _ |- _ => inversion H
    end.

  Ltac break_st := unfold st in *; repeat break_pair; simpl in *.

  Ltac use_Safe_immune :=
    match goal with
      H : RunsTo _ _ _ _, H2 : context [RunsTo _ _ _ _ -> Safe _ _ _] |- _ => eapply H2 in H; break_st; eapply Safe_immune
    end.

  Ltac change_RunsTo :=
    match goal with
      H : RunsTo _ _ (?VS1, ?ARRS) _, H2 : changed_in ?VS2 ?VS1 _ |- _ => 
        generalize H; eapply RunsTo_immune with (vs1' := (VS2, ARRS)) in H; intros
    end.

  Definition equiv (a b : Heap) := fst a %= fst b /\ forall e, e %in fst a -> snd a e = snd b e.

  Infix "%%=" := equiv (at level 70, no associativity).

  Lemma disjoint_cons : forall A a (e : A) b, ~In e a -> disjoint a b -> disjoint a (e :: b).
    unfold disj; intros; simpl; intuition; eauto.
  Qed.

  Lemma disjoint_disj : forall A (a : list A) b, disjoint a b -> disj a b.
    unfold disj, disj; eauto.
  Qed.

  Lemma del_not_in : forall s e, ~ e %in s %- e.
    unfold mem, del; intros; intuition.
  Qed.

  Ltac is_reg t r :=
    match t with
      | _ # r => idtac
      | Regs _ r => idtac
    end.

  Ltac sp_solver' := 
    match goal with
      |- ?A = ?B => is_reg A Sp; is_reg B Sp; pattern_r; rewriter_r
    end.

  Hint Extern 12 => sp_solver'.

  Ltac use_disjoint_trans :=
    match goal with
      H : disjoint ?A ?B |- disjoint ?C _ =>
        match A with context [ C ] =>
          eapply (@disjoint_trans_lr _ A B C _ H); [ | eapply List.incl_refl ]
        end 
    end.

  Hint Resolve del_not_in.
  Hint Resolve temp_in_array.
  Hint Resolve temps_not_in_array.
  Hint Resolve true_false_contradict.

  Ltac to_temp_var :=
    replace "!!" with (temp_var 1) in * by eauto;
      replace "!" with (temp_var 0) in * by eauto.

  Lemma del_add : forall s e, e %in s -> s %- e %+ e %= s.
    clear; intros.
    set (s %- e).
    eapply equiv_symm.
    eapply del_to_add.
    eauto.
    unfold s0; eauto.
  Qed.

  Hint Resolve le_n_S.

  Ltac use_disjoint_trans' :=
    match goal with
      H : disjoint ?A ?B |- disjoint ?C _ =>
        match A with context [ C ] =>
          eapply (@disjoint_trans_lr _ A B C _ H)
        end 
    end.

  Hint Resolve Safe_cond_true Safe_cond_false.

  Ltac decide_constructor :=
    match goal with
      H : evalCond _ _ _ _ _ = Some ?B |- RunsTo (Syntax.If _ _ _) _ _ =>
        match B with
          | true => econstructor 6
          | false => econstructor 7
        end
    end.

  Hint Extern 1 => decide_constructor.

  Hint Resolve runs_loop_partially_body_safe.

  Hint Resolve Safe_immune.

  Ltac temp_var_solver :=
    match goal with
      H : List.incl (tempVars _) ?VARS |- In (temp_var ?N) ?VARS =>
        eapply In_incl; [eapply temp_in_array with (n := S N); omega | eapply incl_tran with (2 := H) ]
    end.

  Hint Extern 1 => temp_var_solver.

  Ltac incl_tran_tempVars :=
    match goal with
      H : List.incl (tempVars _) ?VARS |- List.incl (tempVars _) ?VARS => eapply incl_tran with (2 := H)
    end.

  Hint Extern 1 => incl_tran_tempVars.

  Ltac clear_step := try clear_imports; step auto_ext.

  Ltac in_solver :=
    match goal with
      H : Safe _ _ (_, ?ARRS) |- _ %in fst ?ARRS => rewriter; inv_Safe
    end.

  Hint Extern 1 => in_solver.

  Ltac use_Safe_immune2 :=
    match goal with
      | H : Safe _ ?S_H (?VS1, ?ARRS), H2 : changed_in ?VS1 ?VS2 _ |- Safe _ ?S_G (?VS2, ?ARRS) =>
        match S_H with
          context [ S_G ] => eapply (@Safe_immune _ S_G VS1 VS2 ARRS); [ | simpl; use_changed_unchanged; use_disjoint_trans']
        end
      | H : Safe _ (Syntax.Seq ?A ?B) ?V, H2 : RunsTo _ ?A ?V ?V' |- Safe _ ?B _ => break_st; rewriter; eapply Safe_immune
      | H : Safe _ (While ?E ?B) _, H2 : runs_loop_partially ?E ?B _ _ |- Safe _ ?B _ => break_st; rewriter; eapply Safe_immune; [ eapply (@runs_loop_partially_body_safe _ _ _ _ _ H2) | ]; [ try use_Safe_immune2 | .. ]
    end.

  Lemma Safe_seq_first : forall fs a b v, Safe fs (Syntax.Seq a b) v -> Safe fs a v.
    intros; inv_Safe; eauto.
  Qed.

  Hint Resolve Safe_seq_first.

  Lemma unchanged_in_refl : forall vs vars, unchanged_in vs vs vars.
    unfold unchanged_in; eauto.
  Qed.

  Hint Resolve unchanged_in_refl.

  Lemma Safe_seq_second : forall fs a b v v', Safe fs (Syntax.Seq a b) v -> RunsTo fs a v v' -> Safe fs b v'.
    intros; inv_Safe; use_Safe_immune; eauto.
  Qed.

  Hint Resolve Safe_seq_second.

  Ltac change_RunsTo_arrs :=
    match goal with
      H : RunsTo _ ?S (?VS, ?ARRS1) _ |- RunsTo _ ?S (?VS, ?ARRS2) _ => replace ARRS2 with ARRS1
    end.

  Hint Extern 1 => change_RunsTo_arrs.

  Ltac extend_runs_loop_partially :=
    match goal with
      H : runs_loop_partially _ ?E ?B ?V (?VS, _), H2 : RunsTo _ ?B (?VS, _) ?V'' |- runs_loop_partially _ ?E ?B ?V _ =>
        eapply (@LoopPartialStep _ _ _ _ _ V'' H)
    end.

  Ltac pre_descend := first [change_RunsTo | auto_apply_in runs_loop_partially_finish; [change_RunsTo | ..] ]; open_hyp; break_st.

  Ltac arrays_eq_solver :=
    match goal with
      |- ?A = _ =>
      match type of A with
        Heap => simpl in *; congruence
      end
    end.

  Ltac choose_changed_unchanged :=
    match goal with
      H : disjoint ?A ?B |- unchanged_in _ _ ?C =>
        match A with
          context [ C ] => eapply (@changed_unchanged _ _ B _)
        end
    end.

  Ltac iter_changed_discharger := first [eassumption | eapply changedVariables_incl; [eassumption | ..] | eapply changedVariables_upd_fwd | eapply changedVariables_incl; [eapply changedVariables_upd_fwd | ..] ].

  Ltac iter_changed := repeat first [iter_changed_discharger | eapply changed_trans_l].

  Ltac format_solver :=
    match goal with
      |- _ = eval _ _ ^+ $4 ^* eval _ _ =>
      rewriter; erewrite changed_in_inv by eauto; rewrite sel_upd_eq by eauto; rewriter; repeat (f_equal; try (eapply unchanged_eval; choose_changed_unchanged; iter_changed))
    end.

  Opaque List.incl.

  Lemma changed_in_upd_eq : forall vs1 vs2 vars s val1 val2,
    changed_in vs1 vs2 vars ->
    val2 = val1 ->
    changed_in (upd vs1 s val1) (upd vs2 s val2) vars.
    intros; rewriter; eauto.
  Qed.

  Hint Resolve changed_in_upd_eq.

  Ltac use_changed_in_upd_same :=
    match goal with
      |- changed_in (upd _ ?S _) (upd _ ?S _) _ => eapply changed_in_upd_same; iter_changed
    end.

  Ltac auto_unfold :=
    repeat match goal with
             t := _ |- _ => unfold t in *; clear t
           end.

  Hint Resolve del_add.

  Hint Resolve equiv_symm.

  Ltac max_2_plus :=
    match goal with
      |- (max _ _ >= 2 + _)%nat => simpl
    end.

  Hint Extern 1 => max_2_plus.

  Ltac temp_var_neq :=
    match goal with
      |- ~ (temp_var _ = temp_var _) => discriminate
    end.

  Hint Extern 1 => temp_var_neq.

  Ltac not_in_solver :=
    match goal with 
      H : ?ARRS = _ |- ~ _ %in fst ?ARRS => rewriter
    end.

  Ltac no_question_mark :=
    match goal with
      |- ?T => match T with T => idtac end
    end.

  Ltac upd_chain_solver :=
    match goal with
      H1 : changed_in _ _ _, H2 : changed_in (upd _ _ _) _ _, H3 : changed_in (upd _ _ _) _ _ |- changed_in _ _ _ => no_question_mark; simpl; iter_changed
    end.

  Ltac rv_length_solver :=
    match goal with
      H : Regs ?ST Rv = natToW (length _) |- Regs ?ST Rv = natToW (length _) => rewriter
    end.

  Hint Extern 1 => rv_length_solver.

  Ltac arrays_eq_solver2 :=
    match goal with
      H : ?A = _ |- ?A = _ =>
        match type of A with
          Heap => rewriter
        end
    end.

  Hint Resolve RunsToRelax_loop_false.

  Hint Constructors Safe.
  Lemma Safe_cond_true_k : forall fs e t f k v, 
    Safe fs (Syntax.If e t f;: k) v ->
    wneb (v[(e)]) $0 = true ->
    Safe fs (t;: k) v.
    inversion 1; intros; econstructor; eauto.
  Qed.
  Hint Resolve Safe_cond_true_k.
  Lemma Safe_cond_false_k : forall fs e t f k v, 
    Safe fs (Syntax.If e t f;: k) v ->
    wneb (v[(e)]) $0 = false ->
    Safe fs (f;: k) v.
    inversion 1; intros; econstructor; eauto.
  Qed.
  Hint Resolve Safe_cond_false_k.

  Hint Extern 1 => use_disjoint_trans''.

  Ltac change_rp :=
    match goal with
      H : ?SPECS (sel ?VS1 "rp") = Some _ |- ?SPECS (sel ?VS2 "rp") = Some _ =>
        replace (sel VS2 "rp") with (sel VS1 "rp") by (symmetry; eapply changed_in_inv; [ eauto | ]; eapply in_tran_not; [ | eauto ]; eapply incl_tran; [ | eassumption ]; eauto)
    end.
  Local Notation "'tmps' s" := (tempVars (depth s)) (at level 60).
  Local Notation "'etmps' s" := (tempVars (edepth s)) (at level 60).
  Local Notation agree_in := unchanged_in.
  Local Notation agree_except := changed_in.
  Local Notation "b [ vars => c ]" := (merge c b vars) (no associativity, at level 60).
  Infix "==" := VariableLemmas.equiv.
  Local Notation "v1 =~= v2 [^ except ]" := (st_agree_except v1 v2 except) (no associativity, at level 60).

  Local Notation "fs -:- v1 -- s --> v2" := (RunsTo fs s v1 v2) (no associativity, at level 60).

  Hint Resolve Max.max_lub.

  Lemma st_agree_except_refl : forall v ex, v =~= v [^ex].
    unfold st_agree_except; eauto.
  Qed.
  Hint Resolve st_agree_except_refl.

  Hint Resolve RunsToRelax_cond_true'.
  Hint Resolve RunsToRelax_cond_false'.
  Hint Resolve RunsToRelax_cond_true RunsToRelax_cond_false.

  Hint Unfold st_agree_except.

  Local Notation "v [ e ]" := (eval e v) (no associativity, at level 60).
  Lemma in_not_in_ne : forall A ls (a b : A), In a ls -> ~ In b ls -> a <> b.
    intuition.
  Qed.

  Lemma Safe_assoc_left : forall fs a b c v, Safe fs (a;: b;: c) v -> Safe fs (a;: (b;: c)) v.
    clear; intros; inv_Safe; subst; inversion H; subst; econstructor; [ | intros; econstructor ].
    eauto.
    eauto.
    eauto.
  Qed.
  Ltac true_not_false :=
    match goal with
      H1 : ?A = true, H2 : ?A = false |- _ => eapply Bool.eq_true_false_abs in H1; intuition
    end.
  Hint Extern 1 => true_not_false.
  Lemma Safe_loop_true : forall fs e b v,
    Safe fs (While e b) v ->
    wneb (v[(e)]) $0 = true ->
    Safe fs (b;: While e b) v.
    intros.
    inv_Safe.
    unfold statement0 in *.
    rewrite <- H2 in *.
    eauto.
    eauto.
  Qed.
  Hint Resolve Safe_loop_true.
  Hint Resolve RunsTo_loop_true.
  Lemma Safe_loop_true_k : forall fs e b k v, 
    Safe fs (While e b;: k) v ->
    wneb (v[(e)]) $0 = true ->
    Safe fs (b;: (While e b;: k)) v.
    intros.
    inv_Safe.
    subst.
    inversion H3; try (unfold vals in *; congruence).
    subst b.
    subst v.
    econstructor.
    eauto.
    intros.
    econstructor; eauto.
  Qed.
  Hint Resolve Safe_loop_true_k.
  Local Notation agree_except_trans := changedVariables_trans.

  Hint Resolve RunsToRelax_seq_bwd.

  Hint Resolve RunsToRelax_loop_true.

  Hint Resolve RunsToRelax_loop_true_k.

  Hint Resolve Safe_assoc_left.

  Hint Resolve RunsToRelax_skip.

  Lemma mult_S_distr : forall a b, a * S b = a + a * b.
    intros; ring.
  Qed.

  Definition heap_tag layout arrs (_ _ : W) := is_heap layout arrs.

  Ltac set_all t := let name := fresh "t" in set (name := t) in *.

  Definition heap_to_split layout arrs (_ : W) := is_heap layout arrs.

  Lemma star_comm : forall a b, a * b ===> b * a.
    clear; intros; sepLemma.
  Qed.

  Lemma star_cancel_left : forall a b c, b ===> c -> a * b ===> a * c.
    clear; intros; sepLemma.
  Qed.

  Lemma star_cancel_right : forall a b c, b ===> c -> b * a ===> c * a.
    clear; intros; sepLemma.
  Qed.

  Lemma equiv_symm : forall a b, a %%= b -> b %%= a.
    clear; unfold equiv, MHeap.MSet.equiv; simpl; intros; firstorder.
  Qed.

  Hint Resolve equiv_symm.

  Definition trigger A (_ : A) := True.

  Ltac trigger_bwd Hprop :=
    match Hprop with
      context [ is_heap _ ?ARRS ] =>
      assert (trigger ARRS) by (unfold trigger; trivial)
    end.

  Lemma equiv_refl : forall a, a %%= a.
    clear; unfold equiv; intros; firstorder.
  Qed.
  Hint Resolve equiv_refl.

  Hint Resolve in_not_in_ne.

  Hint Resolve RunsTo_RunsToRelax.

  Ltac apply_save_in lemma hyp := generalize hyp; eapply lemma in hyp; intro.

  Ltac assert_sp P Q H_sp :=
    match P with
      context [ locals _ _ _ ?P_SP ] =>
      match Q with
        context [ locals _ _ _ ?Q_SP] =>
        assert (Q_SP = P_SP) as H_sp
      end
    end.

  Ltac set_heap_goal :=
    match goal with
      |- context [ is_heap _ ?ARRS ] => set_all ARRS
    end.

  Ltac set_heap_hyp :=
    match goal with
      H : context [ is_heap _ ?ARRS ] |- _ => set_all ARRS
    end.

  Ltac set_array_hyp :=
    match goal with
      H : context [ array ?ARR ?PTR ] |- _ => set_all ARR; set_all PTR
    end.

  Lemma not_in_remove_arr : forall arr arrs, ~ arr %in fst (MHeap.remove arrs arr).
    intros; unfold MHeap.remove; simpl; eauto.
  Qed.

  Hint Resolve not_in_remove_arr.

  Hint Resolve in_tran_not.

  Lemma good_vars_imply : forall vars s1 s2, 
    good_vars vars s1 -> 
    List.incl (footprint s2) (footprint s1) ->
    depth s2 <= depth s1 ->
    good_vars vars s2.
    admit.
    (* clear; unfold good_vars; intros; openhyp; descend; eauto. *)
  Qed.

  Local Notation "'e_good_vars'" := CompileExpr.expr_good_vars.

  Lemma good_vars_imply_e : forall vars s e base, good_vars vars s -> List.incl (varsIn e) (footprint s) -> (base + edepth e <= depth s)%nat -> e_good_vars vars e base.
    admit.
    (* clear; unfold good_vars, CompileExpr.expr_good_vars; simpl; intuition; eauto. *)
  Qed.

  Ltac unfold_copy_good_vars :=
    match goal with
      H : good_vars _ _ |- _ => generalize H; unfold good_vars in H; simpl in H; intro; openhyp
    end.

  Ltac protect_hyps :=
    repeat 
      match goal with
        | H : agree_except _ _ _ |- _ => generalize dependent H
        | H : good_vars _ _ |- _ => generalize dependent H
        | H : Regs _ Rv = _ |- _ => generalize dependent H
        | H : _ %in _ |- _ => generalize dependent H
        | H : Safe _ _ _ |- _ => generalize dependent H
        | H : RunsToRelax _ _ _ _ |- _ => generalize dependent H
      end.

  Ltac changed_unchanged_disjoint :=
    match goal with
      H : disjoint ?A ?B |- agree_in _ _ _ => eapply changed_unchanged with (changed := B)
    end.

  Ltac changed_in_inv_disjoint := 
    match goal with
      H : disjoint ?A ?B |- _ = _ => eapply changed_in_inv with (vars := B)
    end.

  Ltac change_rp' :=
    match goal with
      H : ?SPECS (sel ?VS1 "rp") = Some _ |- ?SPECS (sel ?VS2 "rp") = Some _ =>
        replace (sel VS2 "rp") with (sel VS1 "rp"); [ | symmetry; changed_in_inv_disjoint; [ | eapply in_tran_not; [ | eassumption ] ] ]
    end.

  Ltac equiv_solver :=
    match goal with
      |- _ %%= MHeap.upd ?ARRS _ _ => auto_unfold; no_question_mark; rewriter; unfold MHeap.upd, MHeap.remove, equiv; simpl; to_temp_var; split; [ | intros; repeat f_equal; erewrite changed_in_inv by eauto; rewrite sel_upd_ne by eauto; erewrite changed_in_inv by eauto; rewrite sel_upd_eq by eauto]
    end.

  Ltac set_vs_hyp :=
    match goal with
      H : context [ locals _ ?VS _ _ ] |- _ => set_all VS
    end.

  Ltac equiv_solver2 :=
    match goal with
      |- _ %%= MHeap.upd ?ARRS _ _ => auto_unfold; no_question_mark; rewriter; unfold MHeap.upd, MHeap.remove, equiv; simpl; to_temp_var; split; [ | intros; repeat f_equal]
    end.

  Lemma upd_sel_equiv : forall d i i', MHeap.sel (MHeap.upd d i (MHeap.sel d i)) i' = MHeap.sel d i'.
    clear; intros; destruct (weq i i').
    rewrite MHeap.sel_upd_eq; congruence.
    rewrite MHeap.sel_upd_ne; congruence.
  Qed.

  Ltac upd_chain_solver2 :=
    match goal with
      H1 : changed_in _ _ _, H2 : changed_in (upd _ _ _) _ _ |- changed_in _ _ _ => no_question_mark; simpl; iter_changed
    end.

  Ltac good_vars_solver :=
    match goal with
      | H : good_vars _ _ |- good_vars _ _ => eapply good_vars_imply; repeat (simpl; eauto)
      | H : good_vars _ _ |- e_good_vars _ _ _ => eapply good_vars_imply_e; repeat (simpl; eauto)
    end.

  Ltac RunsToRelax_solver :=
    match goal with
      H : _ ~:~ _ ~~ ?S ~~> ?ST |- _ ~:~ _ ~~ ?S ~~> ?ST =>
        eapply RunsToRelax_immune; [ eassumption | unfold st_agree_except; repeat split .. | ]
    end.

  Ltac Safe_cond_solver :=
    match goal with
      H : Safe _ (Syntax.If _ _ _;: _) (?ST1, _) |- Safe _ _ _ =>
        eapply Safe_immune with (vs1 := ST1); [ | use_changed_unchanged; simpl; eapply disjoint_trans_lr]
    end.

  Ltac RunsToRelax_seq_solver :=
    match goal with
      H : _ ~:~ _ ~~ _;: (_;: _) ~~> _ |- _ ~:~ _ ~~ _;: _;: _ ~~> _ =>
        eapply RunsToRelax_assoc_left; simpl
    end.

  Ltac rv_solver' :=
    match goal with
      | H:Regs ?ST Rv = _ |- Regs ?ST Rv = _ => pattern_l; rewriter
      | H:Regs ?ST Rv = _ |- _ = Regs ?ST Rv => pattern_r; rewriter
      | H:_ = Regs ?ST Rv |- Regs ?ST Rv = _ => pattern_l; rewriter_r
      | H:_ = Regs ?ST Rv |- _ = Regs ?ST Rv => pattern_r; rewriter_r
    end.

  Ltac rp_upd_solver :=
    match goal with
      |- ?A = Some _ =>
      match A with
        context [ upd ] =>
        match A with
          context [ "rp" ] =>
          rewrite sel_upd_ne; [ change_rp' | eapply in_not_in_ne ]
        end
      end
    end.

  Local Notation agree_except_symm := changedVariables_symm.

  Ltac RunsToRelax_Stuff_solver :=
    eapply RunsToRelax_seq_bwd; [ | eassumption | eauto ];
      eapply RunsToRelax_immune; [ eapply RunsTo_RunsToRelax; econstructor; eauto | .. ];
        [ | unfold st_agree_except; repeat split; simpl | ];
        unfold st_agree_except; simpl; intuition eauto.

  Ltac do_RunsToRelax_Read_Write_solver := eapply RunsToRelax_seq_bwd; [ | eassumption | ..]; [ eapply RunsToRelax_immune; [ eapply RunsTo_RunsToRelax; econstructor; eauto | .. ]; [ | unfold st_agree_except; repeat split; simpl; eapply agree_except_symm | ] | ].

  Ltac freeable_goodSize_solver :=
    match goal with
      | |- freeable _ _ => auto_unfold; rewrite upd_length in *
      | |- goodSize _ => auto_unfold; rewrite upd_length in *
    end.

  Ltac equiv_solver2' :=
    match goal with
      |- _ %%= MHeap.upd _ _ _ =>
      equiv_solver2; [ | unfold MHeap.sel; symmetry; eapply upd_sel_equiv ]
    end.

  Ltac pre_eauto := try first [
    use_disjoint_trans' |
    use_Safe_immune2 |
    extend_runs_loop_partially |
    use_changed_in_eval |
    arrays_eq_solver |
    format_solver |
    use_changed_in_upd_same |
    not_in_solver |
    equiv_solver |
    upd_chain_solver |
    arrays_eq_solver2
    ].

  Lemma mult_S_distr_inv : forall a b, a + a * b = a * S b.
    intros; ring.
  Qed.

  Lemma wplus_wminus : forall (a b : W), a ^+ b ^- b = a.
    intros; words.
  Qed.

  Ltac change_locals ns' avail' :=
    match goal with
      H : context[locals ?ns ?vs ?avail ?p] |- _ =>
        let offset := eval simpl in (4 * List.length ns) in
          change (locals ns vs avail p) with (locals_call ns vs avail p ns' avail' offset) in H; assert (ok_call ns ns' avail avail' offset)%nat
    end.

  Ltac change_sp :=
    match goal with
      Hinterp : interp _ (![ ?P ] (_, ?ST)), Heval : evalInstrs _ ?ST _ = _ |- _ =>
        match P with
          context [ Regs ?ST2 Sp ] => not_eq ST ST2; replace (Regs ST2 Sp) with (Regs ST Sp) in Hinterp by words
        end
    end.

  Ltac generalize_sp :=
    repeat match goal with
             H : Regs _ Sp = Regs _ Sp |- _ => generalize dependent H
           end.

  Ltac agree_in_solver :=
    match goal with
      |- agree_in _ _ _ => changed_unchanged_disjoint; [ iter_changed; incl_app_solver | .. ]
    end.

  Ltac use_Safe_immune' :=
    match goal with
      H : Safe _ ?S (_, ?A) |- Safe _ ?S (_, ?A) =>
        eapply Safe_immune; [ eassumption | .. ]; agree_in_solver
    end.

  Ltac ok_call_solver :=
    match goal with
      |- ok_call _ _ _ _ _ =>
      repeat split; simpl; eauto; NoDup
    end.

  Ltac myPost := autorewrite with sepFormula in *; unfold substH in *; simpl in *.

  Ltac clear_or :=
    repeat match goal with 
             H : _ \/ _ |- _ => clear H 
           end.

  Ltac simpl_vars :=
    repeat match goal with 
             | H : context [footprint _] |- _ => progress simpl in H
             | H : context [tmps _] |- _ => progress simpl in H
           end.

  Lemma ignore_premise : forall pc state specs (P Q : PropX pc state),
    interp specs Q
    -> interp specs (P ---> Q).
    intros; apply Imply_I; apply interp_weaken; assumption.
  Qed.

  Ltac step_himp_helper :=
    match goal with
      |- himp _ ?A ?B =>
      match B with
        context [locals ?VARS ?VS1 _ ?SP1] =>
        match A with
          context [locals VARS ?VS2 _ ?SP2] =>
          match A with
            context [locals ?VARS2 _ _ ?SP3] =>
            not_eq VARS VARS2; replace SP1 with SP2; replace SP3 with (SP2 ^+ natToW (4 * length VARS)); replace VS1 with VS2
          end
        end
      end
    end.

  Ltac sel_eq_solver :=
    match goal with
      |- sel _ ?V = sel _ ?V => symmetry; changed_in_inv_disjoint
    end.

  Ltac pre_eauto2 := try first [
    ok_call_solver |
    use_Safe_immune2 |
    (format_solver; incl_app_solver) |
    equiv_solver |
    good_vars_solver |
    RunsToRelax_solver | 
    rp_upd_solver |
    change_rp' |
    rv_solver' |
    Safe_cond_solver |
    RunsToRelax_seq_solver |
    freeable_goodSize_solver |
    changed_unchanged_disjoint |
    equiv_solver2' |
    use_Safe_immune' |
    sel_eq_solver
    ].

  Lemma four_out : forall n, 4 * (S (S (S n))) = 4 * 3 + 4 * n.
    intros; omega.
  Qed.

  Ltac clear_specs :=
    repeat
      match goal with
        | H : interp ?SPECS_H _ |- context [simplify ?SPECS _ _] => not_eq SPECS_H SPECS; clear H
        | H : interp ?SPECS_H _ |- context [interp ?SPECS _] => not_eq SPECS_H SPECS; clear H
      end.

  Lemma Safe_skip : forall fs k v,
    Safe fs (skip;: k) v
    -> Safe fs k v.
    inversion 1; auto.
  Qed.

  Hint Resolve Safe_skip.

  Hint Extern 1 (agree_in _ _ _) => progress simpl.

  Lemma Safe_loop_false : forall fs e b v k,
    Safe fs (While e b;: k) v ->
    wneb (v[(e)]) $0 = false ->
    Safe fs k v.
    intros; inv_Safe; eauto.
  Qed.

  Hint Resolve Safe_loop_false.

  Ltac changed_in_inv_vars := 
    match goal with
      H : disjoint ?A ?B, H2 : List.incl ?A ?VARS |- _ = _ => eapply changed_in_inv with (vars := VARS)
    end.

  Ltac incl_arg_vars_solver :=
    match goal with
      H : List.incl ?FP ("__arg" :: ?VARS) |- List.incl (?S :: nil) ("__arg" :: ?VARS) => 
        match FP with
          context [S] => eapply incl_tran; [ | eassumption ]
        end
    end.

  Ltac temp_solver :=
    match goal with
      | H : List.incl (tempVars ?N) _ |- List.incl (tempChunk _ _) _ => eapply incl_tran with (m := tempVars N); [eapply incl_tempChunk2; simpl | ]
      | H : List.incl (tempVars ?N) _ |- List.incl (temp_var _ :: nil) _ => eapply incl_tran with (m := tempVars N)
    end.

  Ltac sel_eq_solver2 :=
    match goal with
      |- sel _ ?V = sel _ ?V => symmetry; changed_in_inv_vars; iter_changed; try temp_solver; try eapply in_tran_not; try incl_arg_vars_solver
    end.

  Ltac replace_reserved :=
    match goal with
      H : context [sel ?VS1 S_RESERVED] |- context [sel ?VS2 S_RESERVED] =>
        not_eq VS1 VS2; replace (sel VS2 S_RESERVED) with (sel VS1 S_RESERVED) in *
    end.

  Ltac le_eq_reserved_solver :=
    match goal with
      | |- _ <= wordToNat (sel _ S_RESERVED) => replace_reserved; [ omega | sel_eq_solver2 ]
      | |- _ = wordToNat (sel _ S_RESERVED) => replace_reserved; [ omega | sel_eq_solver2 ]
    end.

  Ltac change_rp'' :=
    try eassumption;     
      match goal with
        H : ?SPECS (sel ?VS1 "rp") = Some _ |- ?SPECS (sel ?VS2 "rp") = Some _ =>
          replace (sel VS2 "rp") with (sel VS1 "rp"); [ | symmetry; changed_in_inv_disjoint; [ | eapply in_tran_not; [ | eauto ] ] ]; [ | iter_changed; try (apply incl_tempChunk2; simpl) | ]
      end.

  Ltac decide_cond t f :=
    match goal with
      | H : _ = Some true |- _ => t
      | H : _ = Some false |- _ => f
    end.

  Ltac decide_cond_safe := decide_cond ltac:(eapply Safe_cond_true_k) ltac:(eapply Safe_cond_false_k).

  Ltac Safe_cond_solver2 :=
    match goal with
      H : Safe _ (Syntax.If _ _ _;: _) (?ST1, _) |- Safe _ _ _ =>
        eapply Safe_immune with (vs1 := ST1); [ decide_cond_safe | use_changed_unchanged; simpl; eapply disjoint_trans_lr]
    end.

  Ltac Safe_loop_solver :=
    match goal with
      |- Safe _ (_ ;: (While _ _ ;: _)) _ => decide_cond ltac:(eapply Safe_loop_true_k) ltac:(eapply Safe_loop_false)
    end.

  Ltac pre_eauto3 := try first [
    ok_call_solver |
    use_Safe_immune2 |
    (format_solver; incl_app_solver) |
    equiv_solver |
    good_vars_solver |
    RunsToRelax_solver | 
    rp_upd_solver |
    change_rp'' |
    rv_solver' |
    Safe_cond_solver2 |
    RunsToRelax_seq_solver |
    freeable_goodSize_solver |
    changed_unchanged_disjoint |
    equiv_solver2' |
    use_Safe_immune' |
    sel_eq_solver2 |
    le_eq_reserved_solver | 
    Safe_loop_solver
    ].

  Ltac smack := to_temp_var; pre_eauto3; info_eauto 7.

  Ltac var_solver :=
    try apply unchanged_in_upd_same; smack; try apply changed_in_upd_same;
      try (upd_chain_solver2; simpl; incl_app_solver); try (apply incl_tempChunk2; simpl); info_eauto 8.

  Ltac pick_vs :=
    (*try match goal with
          | [ x : (settings * state)%type |- _ ] => destruct x; simpl in *
        end;*)
    match goal with
      H : interp ?SPECS (![?P] ?ST) |- context [ (![_] ?ST)%PropX ] =>
        match P with
          context [ locals _ ?VS _ _ ] => let a := fresh in evar (a : Heap); (exists (VS, a)); unfold a in *; clear a
        end
    end.

  Ltac unfold_eval := unfold precond, postcond, inv, expr_runs_to, runs_to_generic in *.

  Ltac preamble := 
    wrap0; unfold_eval; unfold_copy_good_vars; myPost;
    repeat eval_step hints;
      repeat match goal with
               | [ |- vcs _ ] => wrap0;
                 try match goal with
                       | [ x : (settings * state)%type |- _ ] => destruct x
                     end; try eval_step hints;
                 try match goal with
                       | [ H : context[expr_runs_to] |- _ ] =>
                         unfold expr_runs_to, runs_to_generic in H; simpl in H
                     end; try eval_step hints
             end; smack;
      match goal with
        | [ x : (vals * Heap)%type |- _ ] => destruct x; simpl in *
        | [ x : st |- _ ] => destruct x; simpl in *
      end;
      myPost; try (unfold_eval; clear_imports; eval_step auto_ext; var_solver);
        try match goal with
              | [ fs : W -> option Callee
                  |- exists x : W -> option Callee, _ ] =>
                exists fs;
                  match goal with
                    | [ |- _ /\ _ ] => split; [ split; assumption | ]
                  end
            end;
        try match goal with
              | [ |- exists a0 : _ -> PropX _ _, _ ] => eexists
            end;
        pick_vs; descend; try (eauto 2; try solve [ eapply Safe_immune; [ eauto 2 | eauto 8 ] ]);
          clear_or.

  Ltac middle :=
    match goal with
      | [ |- context[is_heap _ ?a] ] => set_heap_goal; try reflexivity
      | [ |- interp _ (![_] _) ] => clear_imports; replace_reserved; [ repeat hiding ltac:(step auto_ext) | .. ]
      | _ => var_solver
    end.

  Ltac do_step := descend; try clear_imports;
    try match goal with
          | [ H : _ ~:~ _ ~~ _ ~~> _ |- interp _ (![_] _ ---> ![_] _)%PropX ] => clear H
        end;
    try match goal with
          | [ |- himp _ ?pre ?post ] =>
            match pre with
              | context[locals _ _ _ ?sp1] =>
                match post with
                  | context[locals _ _ _ ?sp2] =>
                    replace sp2 with sp1 by words
                end
            end
        end;
    hiding ltac:(step auto_ext).

  Ltac stepper := try replace_reserved; [ clear_or; repeat do_step | .. ].

  Ltac solver :=
    match goal with
      | _ => RunsToRelax_Stuff_solver
      | _ => smack
    end.

  Ltac finale := stepper; solver.

  Ltac t := preamble; middle; finale.

  Opaque mult.
  Opaque is_heap.

  Ltac discharge_fs :=
    match goal with
      | [ fs : W -> option Callee
          |- exists x : W -> option Callee, _ ] =>
        exists fs;
          match goal with
            | [ |- _ /\ _ ] => split; [ split; assumption | ]
          end
               end;
          match goal with
            | [ |- exists a0 : _ -> PropX _ _, _ ] => eexists
          end.

  Lemma good_vars_disjoint : forall vars s b n, good_vars vars s -> disjoint (footprint s) (tempChunk b n).
    admit.
  Qed.

  Hint Resolve good_vars_disjoint.

  Lemma good_vars_seq_assoc_left : forall vars s1 s2 k, good_vars vars (s1 ;: s2 ;: k) -> good_vars vars (s1 ;: (s2 ;: k)).
    admit.
  Qed.

  Hint Resolve good_vars_seq_assoc_left.

  Lemma good_vars_seq_part : forall vars s1 s2 k, good_vars vars (s1 ;: s2 ;: k) -> good_vars vars (s2 ;: k).
    admit.
  Qed.

  Hint Resolve good_vars_seq_part.

  Hint Resolve RunsToRelax_assoc_left.

  Lemma good_vars_disjoint_tempVars : forall vars s n, good_vars vars s -> disjoint (footprint s) (tempVars n).
    admit.
  Qed.

  Hint Resolve good_vars_disjoint_tempVars.

  Lemma pack_pair : forall A B (p : A * B), (fst p, snd p) = p.
    intuition.
  Qed.

  Lemma Safe_pair : forall fs s p, Safe fs s p -> Safe fs s (fst p, snd p).
    admit.
  Qed.

  Hint Resolve Safe_pair.

  Lemma reserved_not_in_tempChunk : forall b n, ~ In S_RESERVED (tempChunk b n).
    admit.
  Qed.

  Hint Resolve reserved_not_in_tempChunk.

  Lemma rp_not_in_tempChunk : forall b n, ~ In "rp" (tempChunk b n).
    admit.
  Qed.

  Hint Resolve rp_not_in_tempChunk.

  Lemma good_vars_if_part_true : forall vars e t f k, good_vars vars (Syntax.If e t f ;: k) -> good_vars vars (t ;: k).
    admit.
  Qed.

  Hint Resolve good_vars_if_part_true.

  Lemma good_vars_if_part_false : forall vars e t f k, good_vars vars (Syntax.If e t f ;: k) -> good_vars vars (f ;: k).
    admit.
  Qed.

  Hint Resolve good_vars_if_part_false.

  Lemma good_vars_if_cond : forall vars e t f k, good_vars vars (Syntax.If e t f ;: k) -> e_good_vars vars e 0.
    admit.
  Qed.

  Hint Resolve good_vars_if_cond.

  Ltac replace_sel := try eassumption;     
    match goal with
      H : context [sel ?VS1 ?V] |- context [sel ?VS2 ?V] =>
        not_eq VS1 VS2; replace (sel VS2 V) with (sel VS1 V) in *; try symmetry
    end.

  Hint Resolve changed_in_inv.

  Ltac do_wrap :=
    match goal with
      | [ |- vcs _ ] => wrap0
    end.

  Ltac do_unfold_eval :=
    match goal with
      | [ H : context[expr_runs_to] |- _ ] => unfold_eval
    end.

  Lemma post_ok : forall (s k : Stmt) (pre : assert) (specs : codeSpec W (settings * state))
    (x : settings * state),
    vcs (verifCond s k pre) ->
    interp specs (Postcondition (compile s k pre) x) ->
    interp specs (postcond k x).

    unfold verifCond, imply; induction s.

    (* skip *)
    wrap0; unfold_eval; repeat (first [do_wrap | do_unfold_eval | eval_step auto_ext]).
    discharge_fs; descend; try clear_imports; repeat hiding ltac:(step auto_ext); eauto.

    (* seq *)
    wrap0; unfold_eval; repeat (first [do_wrap | do_unfold_eval | eval_step auto_ext]).
    discharge_fs; descend; try clear_imports; repeat hiding ltac:(step auto_ext); eauto.
    eauto.

    (* if-true *)
    wrap0; unfold_eval; repeat (first [do_wrap | do_unfold_eval | eval_step auto_ext]).
    discharge_fs.
    rewrite pack_pair in *.
    pick_vs.
    descend; try clear_imports; repeat hiding ltac:(step auto_ext); post_step.
    simpl; replace_sel; eauto.
    eapply Safe_immune; eauto.
    simpl; replace_sel; eauto.
    eauto 6.
    eauto.
    eauto.

    (* if-false *)
    wrap0; unfold_eval; repeat (first [do_wrap | do_unfold_eval | eval_step auto_ext]).
    discharge_fs.
    rewrite pack_pair in *.
    pick_vs.
    descend; try clear_imports; repeat hiding ltac:(step auto_ext); post_step.
    simpl; replace_sel; eauto.
    eapply Safe_immune; eauto.
    simpl; replace_sel; eauto.
    eauto 6.
    eauto.
    eauto.

    (* while *)
    wrap0; unfold_eval; repeat (first [do_wrap | do_unfold_eval | eval_step auto_ext]).
    myPost.
    discharge_fs; descend; try clear_imports; repeat hiding ltac:(step auto_ext); eauto.

    (* call *)
    admit.

  Qed.

  Ltac unfold_wrap0 := unfold verifCond, imply, CompileExpr.expr_verifCond in *.

  Ltac clear_himp :=
    match goal with
      | [ H : _ ~:~ _ ~~ _ ~~> _ |- interp _ (![_] _ ---> ![_] _)%PropX ] => clear H
    end.

  Ltac stepper' := 
    match goal with
      |- context [locals _ _ _ _] => try replace_reserved; [ clear_or; descend; try clear_imports; try clear_himp; repeat hiding ltac:(step auto_ext) | .. ]
    end.

  Ltac destruct_st :=
    match goal with
      | [ x : (vals * Heap)%type |- _ ] => destruct x; simpl in *
      | [ x : st |- _ ] => destruct x; simpl in *
    end;
    try match goal with
          | [ x : (settings * state)%type |- _ ] => destruct x; simpl in *
        end.

  Ltac smack2 := pre_eauto3; simpl; info_eauto 8.

  Ltac eval_step2 hints :=
    match goal with
      | Hinterp : interp _ (![ ?P ] (_, ?ST)), Heval : evalInstrs _ ?ST ?INSTRS = _ |- _ =>
        match INSTRS with
          | context [ IL.Binop _ (RvLval (LvReg Sp)) Plus _ ] =>
            change_locals ("rp" :: S_RESERVED :: "__arg" :: nil) 0; [ clear Heval |repeat rewrite <- mult_plus_distr_l in *; change_sp; generalize_sp; eval_step hints ]
        end
      | _ => eval_step hints
    end.

  Lemma verifCond_ok : forall s k (pre : assert),
    vcs (verifCond s k pre) -> vcs (VerifCond (compile s k pre)).

    unfold verifCond, imply; induction s.

    (* skip *)
    wrap0; clear_imports; evaluate auto_ext.

    (* seq *)
    wrap0.
    auto_apply; wrap0; unfold_eval; clear_imports.
    repeat eval_step auto_ext.
(*here*)
    try stepper'; solver.

    auto_apply; wrap0; pre_eauto3; auto_apply_in post_ok; wrap0; unfold_wrap0; wrap0; pre_eauto3; unfold_eval; clear_imports; unfold_copy_good_vars; repeat eval_step hints; try stepper'; solver.

    (* if *)
    wrap0.
    unfold_eval; clear_imports; repeat eval_step hints; try stepper'; solver.
    clear_imports; evaluate auto_ext.

    (* true case *)
    auto_apply; wrap0; pre_eauto3; unfold_eval; clear_imports; unfold_copy_good_vars; repeat eval_step auto_ext; destruct_st; descend; [ propxFo | propxFo | instantiate (2 := (_, _)); simpl; stepper | .. ]; try stepper'; solver.

    (* false case *)
    auto_apply; wrap0; pre_eauto3; unfold_eval; clear_imports; unfold_copy_good_vars; repeat eval_step auto_ext; destruct_st; descend; [ propxFo | propxFo | instantiate (2 := (_, _)); simpl; stepper | .. ]; try stepper'; solver.

    (* while *)
    wrap0.
    unfold_eval; clear_imports; repeat eval_step hints; try stepper'; solver.

    unfold_eval; clear_imports; unfold_copy_good_vars; repeat eval_step auto_ext; destruct_st; descend; [ propxFo | propxFo | instantiate (2 := (_, _)); simpl; stepper | .. ]; try stepper'; smack2.

    clear_imports; unfold evalCond in *; unfold evalRvalue in *; intuition.

    auto_apply_in post_ok.
    unfold_eval; clear_imports; unfold_copy_good_vars; repeat eval_step auto_ext; destruct_st; descend; [ propxFo | propxFo | instantiate (2 := (_, _)); simpl; stepper' | .. ]; try stepper'; smack2.

    unfold_wrap0; wrap0; pre_eauto3; unfold_eval; clear_imports; unfold_copy_good_vars; post; descend; try stepper'; solver.

    auto_apply; wrap0; pre_eauto3; unfold_eval; clear_imports; unfold_copy_good_vars; post; descend; try stepper'; solver.

    unfold_wrap0 ; wrap0; auto_apply_in post_ok.
    unfold_eval; clear_imports; post; try stepper'; solver.

    unfold_wrap0; wrap0; pre_eauto3; unfold_eval; clear_imports; unfold_copy_good_vars; post; descend; try stepper'; solver.

    (* malloc *)
    wrap0; unfold CompileMalloc.verifCond; wrap0.

    (* free *)
    wrap0; unfold CompileFree.verifCond; wrap0.

    (* len *)
    wrap0; unfold_eval; clear_imports; unfold_copy_good_vars; repeat eval_step hints; try stepper'; solver.

    (* call *)
    wrap0.

    unfold_eval; clear_imports; unfold_copy_good_vars; myPost; repeat eval_step2 auto_ext; try stepper'; solver.
    unfold_eval; clear_imports; unfold_copy_good_vars; myPost; repeat eval_step2 auto_ext; try stepper'; solver.
    unfold_eval; clear_imports; unfold_copy_good_vars; myPost; repeat eval_step2 auto_ext; try stepper'; solver.
    unfold_eval; clear_imports; unfold_copy_good_vars; myPost; repeat eval_step2 auto_ext; try stepper'; solver.
    unfold_eval; clear_imports; unfold_copy_good_vars; myPost; repeat eval_step2 auto_ext; try stepper'; solver.
    2: unfold_eval; clear_imports; unfold_copy_good_vars; myPost; repeat eval_step2 auto_ext; try stepper'; solver.
    2: unfold_eval; clear_imports; unfold_copy_good_vars; myPost; repeat eval_step2 auto_ext; try stepper'; solver.

    unfold_eval; clear_imports; unfold_copy_good_vars; myPost.
    eval_step2 auto_ext.
    eval_step2 auto_ext.
    eval_step2 auto_ext.
    2: solver.
    solver.
    2: solver.
    eval_step2 auto_ext.
    2: solver.
    eval_step2 auto_ext.
    solver.

    change (locals ("rp" :: S_RESERVED :: "__arg" :: vars) (upd x10 (temp_var 1) (Regs x0 Rv)) x7 (Regs x0 Sp))
      with (locals_call ("rp" :: S_RESERVED :: "__arg" :: vars) (upd x10 (temp_var 1) (Regs x0 Rv)) x7
        (Regs x0 Sp)
        ("rp" :: S_RESERVED :: "__arg" :: nil) (x7 - 3)
        (S (S (S (S (S (S (S (S (S (S (S (S (4 * Datatypes.length vars)))))))))))))) in *.
    assert (ok_call ("rp" :: S_RESERVED :: "__arg" :: vars) ("rp" :: S_RESERVED :: "__arg" :: nil)
      x7 (x7 - 3)
      (S (S (S (S (S (S (S (S (S (S (S (S (4 * Datatypes.length vars))))))))))))))%nat.
    split.
    simpl; omega.
    split.
    simpl; omega.
    split.
    NoDup.
    simpl; omega.
    
    rename H15 into Hi.
    rename H16 into H15.
    rename H17 into H16.
    rename H18 into H17.
    rename H19 into H18.
    rename H20 into H19.
    rename H21 into H20.
    rename H22 into H21.
    rename H23 into H22.
    rename H24 into H23.
    rename H25 into H24.
    rename H26 into H25.
    rename H27 into H26.
    rename H28 into H27.
    rename H29 into H28.
    rename H30 into H29.
    rename H31 into H30.
    rename H32 into H31.

    inversion H18; clear H18; subst.
    inversion H34; clear H34; subst.
    (*here*)
    specialize (Imply_sound (H3 _ _ _ ) (Inj_I _ _ H32)); propxFo.
    repeat match goal with
             | [ H : context[eval] |- _ ] => generalize dependent H
             | [ H : context[Build_callTransition] |- _ ] => generalize dependent H
             | [ H : agree_except _ _ _ |- _ ] => generalize dependent H
           end.
    change (string -> W) with vals in *.
    generalize dependent H31.
    simpl in H25.
    evaluate auto_ext.
    intro.

    Lemma fold_4S' : forall n, S (S (S (S (S (S (S (S (S (S (S (S (4 * n)))))))))))) = 4 * S (S (S n)).
      intros; omega.
    Qed.
    
    rewrite fold_4S' in *.

    cond_gen.
    solver.
    let P := fresh "P" in
      match goal with
        | [ _ : context[Safe ?fs _ _] |- _ ] => set (P := Safe fs) in *
      end.
    assert (~In "rp" (S_RESERVED :: "__arg" :: vars)) by (simpl; intuition).
    prep_locals.
    replace (Regs x0 Sp) with (Regs x Sp) in * by congruence.
    generalize dependent H31.
    intro.
    generalize dependent x1.
    evaluate auto_ext.
    intros; descend.
    rewrite H9.
    descend.
    erewrite changed_in_inv by solver.
    descend.
    rewrite H41.
    simpl.
    eauto.
    step auto_ext.
    simpl fst in *.
    assert (sel vs S_RESERVED = sel x10 S_RESERVED) by solver.
    simpl in H17.
    assert (vs [e0] = upd x9 (temp_var 0) (Regs x2 Rv) [e0]).
    transitivity (x9 [e0]).
    symmetry; eapply sameDenote; try eassumption.
    generalize H4; clear; intros; solver.
    symmetry; eapply sameDenote.
    instantiate (1 := tempVars 1).
    generalize H4; clear; intros; solver.
    eapply changedVariables_upd'.
    eauto.
    solver.
    descend.

    generalize H7 H14; repeat match goal with
                                | [ H : _ |- _ ] => clear H
                              end; intros.
    step auto_ext.
    unfold upd; simpl.
    rewrite wordToNat_wminus.
    do 2 f_equal; auto.
    rewrite <- H43.
    simpl in H5.
    pre_nomega.
    change (wordToNat (natToW 3)) with 3; omega.
    unfold sel, upd; simpl.
    rewrite H39.
    unfold arg_v in H35.
    rewrite H44 in H35.
    eassumption.
    step auto_ext.
    eapply existsR.
    apply andR.
    apply andR.
    apply Imply_I; apply interp_weaken;
      do 3 (apply Forall_I; intro); eauto.
    apply Imply_I; apply interp_weaken;
      do 2 (apply Forall_I; intro); eauto.
    change (fst (vs, arrs)) with vs in *.
    descend.
    clear Hi H37 H25.
    repeat match goal with
             | [ H : _ \/ _ |- _ ] => clear H
             | [ H : not _ |- _ ] => clear H
             | [ H : evalInstrs _ _ _ = _ |- _ ] => clear H
           end.
    step auto_ext.
    rewrite (create_locals_return ("rp" :: S_RESERVED :: "__arg" :: nil)
      (wordToNat (sel vs S_RESERVED) - 3) ("rp" :: S_RESERVED :: "__arg" :: vars)
      (wordToNat (sel vs S_RESERVED))
      (S (S (S (S (S (S (S (S (S (S (S (S (4 * Datatypes.length vars)))))))))))))).
    assert (ok_return ("rp" :: S_RESERVED :: "__arg" :: vars) ("rp" :: S_RESERVED :: "__arg" :: nil)
      (wordToNat (sel vs S_RESERVED)) (wordToNat (sel vs S_RESERVED) - 3)
      (S (S (S (S (S (S (S (S (S (S (S (S (4 * Datatypes.length vars))))))))))))))
      by (split; simpl; omega).
    assert (Safe x4 k (upd x10 "!." (upd x9 "." (Regs x2 Rv) [e0]), x13)).
    eapply Safe_immune.
    apply H36.
    econstructor.
    eauto.
    eauto.
    unfold upd in H12; simpl in H12; congruence.

    Lemma agree_in_upd : forall vs vs' ls x v,
      agree_in vs vs' ls
      -> ~In x ls
      -> agree_in vs (upd vs' x v) ls.
      unfold agree_in; intros.
      destruct (string_dec x x0); subst; descend; eauto.
    Qed.

    apply agree_in_upd.
    solver.
    apply changedVariables_symm.
    eapply ChangeVar_tran'.
    apply changedVariables_symm; eassumption.
    apply changedVariables_symm; eassumption.
    solver.
    solver.
    solver.
    intro Hin.
    specialize (H4 _ (in_or_app _ _ _ (or_intror _ Hin))).
    apply H4.
    solver.

    generalize dependent (Safe x4 k); intros.
    clear H12 H32 H33 H40.
    instantiate (2 := (_, _)); simpl.
    rewrite fold_4S' in *.
    instantiate (3 := upd x10 "!." (upd x9 "." (Regs x2 Rv) [e0])).
    hiding ltac:(step auto_ext).
    congruence.
    repeat match goal with
             | [ H : Regs _ _ = _ |- _ ] => rewrite H
           end.
    repeat (rewrite wminus_wplus || rewrite wplus_wminus).
    hiding ltac:(step auto_ext).
    descend.
    replace (sel x10 "rp") with (sel vs "rp").
    eauto.
    erewrite <- (@changed_in_inv x10).
    2: apply changedVariables_symm; eassumption.
    descend.
    eapply changed_in_inv.
    apply changedVariables_symm; eassumption.

    Lemma rp_temp_var : forall n, temp_var n = "rp"
      -> False.
      induction n; simpl; intuition.
    Qed.

    Lemma rp_tempChunk : forall k n,
      ~In "rp" (tempChunk n k).
      induction k; simpl; intuition.
      apply in_app_or in H; intuition idtac.
      eauto.
      simpl in *; intuition.
      eapply rp_temp_var; eauto.
    Qed.

    eauto using rp_tempChunk.
    eauto using rp_tempChunk.
    descend; step auto_ext.
    descend; step auto_ext.
    descend; step auto_ext.
    repeat match goal with
             | [ H : _ = _ |- _ ] => rewrite H
           end; apply wplus_wminus.
    clear H15 H12 H40 H32 H33.
    descend; step auto_ext.
    eapply RunsToRelax_seq_bwd; [ | eauto | eauto ].
    eexists (_, _).
    split.
    econstructor.
    eauto.
    eauto.
    unfold upd in H12; simpl in H12.
    rewrite H39 in H12; rewrite <- H44 in H12; eauto.
    simpl.
    split; auto.
    solver.

    eapply changedVariables_upd'.
    2: solver.
    apply changedVariables_symm.
    eapply ChangeVar_tran'.
    apply changedVariables_symm; eassumption.
    apply changedVariables_symm; eassumption.
    solver.
    solver.
    solver.

    (* Switch to case for internal function calls. *)
    
    specialize (Imply_sound (Hi _ _) (Inj_I _ _ H32)); propxFo.
    repeat match goal with
             | [ H : context[eval] |- _ ] => generalize dependent H
             | [ H : context[Build_callTransition] |- _ ] => generalize dependent H
             | [ H : agree_except _ _ _ |- _ ] => generalize dependent H
           end.
    change (string -> W) with vals in *.
    generalize dependent H31.
    simpl in H25.
    evaluate auto_ext.
    intro.
    rewrite fold_4S' in *.

    cond_gen.
    solver.
    let P := fresh "P" in
      match goal with
        | [ _ : context[Safe ?fs _ _] |- _ ] => set (P := Safe fs) in *
      end.
    assert (~In "rp" (S_RESERVED :: "__arg" :: vars)) by (simpl; intuition).
    prep_locals.
    replace (Regs x0 Sp) with (Regs x Sp) in * by congruence.
    generalize dependent H31.
    intro.
    generalize dependent x1.
    evaluate auto_ext.
    intros; descend.
    rewrite H9.
    descend.
    erewrite changed_in_inv by solver.
    descend.
    rewrite H41.
    simpl.
    eauto.
    step auto_ext.
    simpl fst in *.
    assert (sel vs S_RESERVED = sel x10 S_RESERVED) by solver.
    simpl in H17.
    assert (vs [e0] = upd x9 (temp_var 0) (Regs x2 Rv) [e0]).
    transitivity (x9 [e0]).
    symmetry; eapply sameDenote; try eassumption.
    generalize H4; clear; intros; solver.
    symmetry; eapply sameDenote.
    instantiate (1 := tempVars 1).
    generalize H4; clear; intros; solver.
    eapply changedVariables_upd'.
    eauto.
    solver.
    descend.

    generalize H7 H14; repeat match goal with
                                | [ H : _ |- _ ] => clear H
                              end; intros.
    step auto_ext.
    unfold upd; simpl.
    rewrite wordToNat_wminus.
    do 2 f_equal; auto.
    rewrite <- H43.
    simpl in H5.
    pre_nomega.
    change (wordToNat (natToW 3)) with 3; omega.
    apply H35.
    unfold sel, upd; simpl.
    unfold arg_v; congruence.
    step auto_ext.
    eapply existsR.
    apply andR.
    apply andR.
    apply Imply_I; apply interp_weaken;
      do 3 (apply Forall_I; intro); eauto.
    apply Imply_I; apply interp_weaken;
      do 2 (apply Forall_I; intro); eauto.
    change (fst (vs, arrs)) with vs in *.
    descend.
    clear Hi H35 H37 H25.
    repeat match goal with
             | [ H : _ \/ _ |- _ ] => clear H
             | [ H : not _ |- _ ] => clear H
             | [ H : evalInstrs _ _ _ = _ |- _ ] => clear H
           end.
    step auto_ext.
    destruct H12.
    rewrite (create_locals_return ("rp" :: S_RESERVED :: "__arg" :: nil)
      (wordToNat (sel vs S_RESERVED) - 3) ("rp" :: S_RESERVED :: "__arg" :: vars)
      (wordToNat (sel vs S_RESERVED))
      (S (S (S (S (S (S (S (S (S (S (S (S (4 * Datatypes.length vars)))))))))))))).
    assert (ok_return ("rp" :: S_RESERVED :: "__arg" :: vars) ("rp" :: S_RESERVED :: "__arg" :: nil)
      (wordToNat (sel vs S_RESERVED)) (wordToNat (sel vs S_RESERVED) - 3)
      (S (S (S (S (S (S (S (S (S (S (S (S (4 * Datatypes.length vars))))))))))))))
      by (split; simpl; omega).
    assert (Safe x4 k (upd x10 "!." (upd x9 "." (Regs x2 Rv) [e0]), x13)).
    eapply Safe_immune.
    apply H36.
    econstructor 14.
    eauto.
    2: eauto.
    unfold sel, upd; simpl.
    congruence.

    apply agree_in_upd.
    solver.
    apply changedVariables_symm.
    eapply ChangeVar_tran'.
    apply changedVariables_symm; eassumption.
    apply changedVariables_symm; eassumption.
    solver.
    solver.
    solver.
    intro Hin.
    specialize (H4 _ (in_or_app _ _ _ (or_intror _ Hin))).
    apply H4.
    solver.

    generalize dependent (Safe x4 k); intros.
    clear H12 H40 H32 H33.
    instantiate (2 := (_, _)); simpl.
    rewrite fold_4S' in *.
    instantiate (3 := upd x10 "!." (upd x9 "." (Regs x2 Rv) [e0])).
    hiding ltac:(step auto_ext).
    congruence.
    repeat match goal with
             | [ H : Regs _ _ = _ |- _ ] => rewrite H
           end.
    repeat (rewrite wminus_wplus || rewrite wplus_wminus).
    hiding ltac:(step auto_ext).
    simpl.
    descend.
    replace (sel x10 "rp") with (sel vs "rp").
    eauto.
    erewrite <- (@changed_in_inv x10).
    2: apply changedVariables_symm; eassumption.
    descend.
    eapply changed_in_inv.
    apply changedVariables_symm; eassumption.

    eauto using rp_tempChunk.
    eauto using rp_tempChunk.

    descend; step auto_ext.
    descend; step auto_ext.
    descend; step auto_ext.
    descend; step auto_ext.
    repeat match goal with
             | [ H : _ = _ |- _ ] => rewrite H
           end; apply wplus_wminus.
    clear H15 H12 H40 H32 H33.
    descend; step auto_ext.

    eapply RunsToRelax_seq_bwd; [ | eauto | eauto ].
    eexists (_, _).
    split.
    econstructor 14.
    eauto.
    2: eauto.
    unfold sel, upd; simpl; congruence.
    split; auto.
    solver.

    simpl.
    eapply changedVariables_upd'.
    2: solver.
    apply changedVariables_symm.
    eapply ChangeVar_tran'.
    apply changedVariables_symm; eassumption.
    apply changedVariables_symm; eassumption.
    solver.
    solver.
    solver.
  Qed.

End Compile.

