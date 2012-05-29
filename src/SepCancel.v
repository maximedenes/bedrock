Require Import List.
Require Import SepTheoryX PropX.
Require Import PropXTac.
Require Import RelationClasses EqdepClass.
Require Import Expr ExprUnify.
Require Import SepExpr SepHeap.
Require Import Setoid.
Require Import Prover.
Require Import SepExpr.
Require Import Folds.

Set Implicit Arguments.
Set Strict Implicit.

Module Make (U : SynUnifier) (SH : SepHeap).
  Module Import SE := SH.SE.
  Module Import SEP_FACTS := SepExprFacts SE.

  Section env.
    Variable types : list type.
    Variable pcType : tvar.
    Variable stateType : tvar.

    Variable funcs : functions types.
    Variable preds : SE.predicates types pcType stateType.

    (** The actual tactic code **)
    Variable Prover : ProverT types.
    Variable Prover_correct : ProverT_correct Prover funcs.


    Definition unifyArgs (bound : nat) (summ : Facts Prover) (l r : list (expr types)) (ts : list tvar) (sub : U.Subst types)
      : option (U.Subst types) :=
      Folds.fold_left_3_opt 
        (fun l r t (acc : U.Subst _) =>
          if Prove Prover summ (Expr.Equal t (U.exprInstantiate sub l) (U.exprInstantiate sub r))
            then Some acc
            else U.exprUnify bound l r acc)
        l r ts sub.

    Fixpoint unify_remove (bound : nat) (summ : Facts Prover) (l : exprs types) (ts : list tvar) (r : list (exprs types))
      (sub : U.Subst types)
      : option (list (list (expr types)) * U.Subst types) :=
        match r with 
          | nil => None
          | a :: b => 
            match unifyArgs bound summ l a ts sub with
              | None => 
                match unify_remove bound summ l ts b sub with
                  | None => None
                  | Some (x,sub) => Some (a :: x, sub)
                end
              | Some sub => Some (b, sub)
            end
        end.
    
    Section with_typing.
      Variable tfuncs : tfunctions.
      Variables tU tG : tenv.
      Variables U G : env types.

      Hypothesis WT_funcs : WellTyped_funcs tfuncs funcs.
      Hypothesis WT_env_U : WellTyped_env tU U.
      Hypothesis WT_env_G : WellTyped_env tG G.

      Lemma unifyArgsOk : forall bound summ R l r ts f S S',
        U.Subst_WellTyped tfuncs tU tG S ->
        Valid Prover_correct U G summ ->
        all2 (@is_well_typed _ tfuncs tU tG) l ts = true ->
        all2 (@is_well_typed _ tfuncs tU tG) r ts = true ->
        unifyArgs bound summ l r ts S = Some S' ->
        @applyD types (exprD funcs U G) ts (map (U.exprInstantiate S') l) R f =
        @applyD types (exprD funcs U G) ts (map (U.exprInstantiate S') r) R f /\
        U.Subst_Extends S' S /\
        U.Subst_WellTyped tfuncs tU tG S'.
      Proof.
        unfold unifyArgs; induction l; destruct r; destruct ts; simpl; intros; try congruence.
        { inversion H2. inversion H3; subst; intuition; auto. }
        { repeat match goal with
          | [ H : (if ?X then _ else _) = true |- _ ] =>
            revert H; case_eq X; intros; [ | congruence ]
                   | [ |- context [ exprD ?A ?B ?C ?D ?E ] ] =>
                     case_eq (exprD A B C D E); intros
                 end; simpl in *;
        try solve [ 
          match goal with
            | [ H : is_well_typed _ _ _ ?e _ = true , H' : exprD _ _ _ (U.exprInstantiate ?S' ?e) _ = None |- _ ] =>
              exfalso; revert H; revert H'; clear; intros H' H;
                eapply WellTyped_exprInstantiate with (S := S') in H;
                  eapply is_well_typed_correct in H;
                    rewrite H' in H ; destruct H; congruence
          end ].
          revert H3. case_eq (Prove Prover summ (Equal t (U.exprInstantiate S a) (U.exprInstantiate S e))); intros.
          { eapply Prove_correct in H3; eauto.
            erewrite U.exprInstantiate_WellTyped in H2 by eauto.
            erewrite U.exprInstantiate_WellTyped in H1 by eauto.
            eapply is_well_typed_correct in H2; eauto.
            eapply is_well_typed_correct in H1; eauto.
            destruct H2; destruct H1.
            unfold ValidProp, Provable in *. simpl in *.
            repeat match goal with 
                     | [ H : _ = _ |- _ ] => rewrite H in *
                     | [ H : ?X -> ?Y |- _ ] => 
                       let H' := fresh in assert (H':X) by eauto; specialize (H H')
                   end.
            subst.
            admit. (** TODO: still need more semantic information from ExprUnify **)

          }
          admit.
          admit.
          admit.
          admit. }
      Qed.

      Lemma unify_removeOk : forall U G cs bound summ f l ts r r' S S' P,
        unify_remove bound summ l ts r S = Some (r', S') ->
        SE.heq funcs preds U G cs
          (SE.Star (SE.Func f l) P) (SH.starred (SE.Func f) r Emp) ->
        SE.heq funcs preds U G cs P (SH.starred (SE.Func f) r' Emp) /\
        U.Subst_Extends S' S.
      Proof.
      Admitted.
    End with_typing.

    Require Ordering.

    Definition cancel_list : Type := 
      list (exprs types * nat).

    (** This function determines whether an expression [l] is more "defined"
     ** than an expression [r]. An expression is more defined if it "uses UVars later".
     ** NOTE: This is a "fuzzy property" but correctness doesn't depend on it.
     **)
    Fixpoint expr_count_meta (e : expr types) : nat :=
      match e with
        | Expr.Const _ _
        | Var _ => 0
        | UVar _ => 1
        | Not l => expr_count_meta l
        | Equal _ l r => expr_count_meta l + expr_count_meta r
        | Less l r => expr_count_meta l + expr_count_meta r
        | Expr.Func _ args =>
          fold_left plus (map expr_count_meta args) 0
      end.

    Definition meta_order_args (l r : exprs types) : Datatypes.comparison :=
      let cmp l r := Compare_dec.nat_compare (expr_count_meta l) (expr_count_meta r) in
      Ordering.list_lex_cmp _ cmp l r.


    Definition meta_order_funcs (l r : exprs types * nat) : Datatypes.comparison :=
      match meta_order_args (fst l) (fst r) with
        | Datatypes.Eq => Compare_dec.nat_compare (snd l) (snd r)
        | x => x
      end.

    Definition order_impures (imps : MM.mmap (exprs types)) : cancel_list :=
      FM.fold (fun k => fold_left (fun (acc : cancel_list) (args : exprs types) => 
        Ordering.insert_in_order _ meta_order_funcs (args, k) acc)) imps nil.

    Lemma impuresD'_flatten : forall U G cs imps,
      SE.heq funcs preds U G cs
        (SH.impuresD _ _ imps)
        (SH.starred (fun v => SE.Func (snd v) (fst v)) 
          (FM.fold (fun f argss acc => 
            map (fun args => (args, f)) argss ++ acc) imps nil) SE.Emp).
    Proof.
      clear. intros. eapply MM.PROPS.fold_rec; intros.
        rewrite (SH.impuresD_Empty funcs preds U G cs H).
        rewrite SH.starred_def. simpl. reflexivity.

        rewrite SH.impuresD_Add; eauto. rewrite SH.starred_app. 
        rewrite H2. symmetry. rewrite SH.starred_base. heq_canceler.
        repeat rewrite SH.starred_def.
        clear; induction e; simpl; intros; try reflexivity.
        rewrite IHe. reflexivity.
    Qed.

    Lemma starred_perm : forall T L R,
      Permutation.Permutation L R ->
      forall (F : T -> _) U G cs base,
      heq funcs preds U G cs (SH.starred F L base) (SH.starred F R base).
    Proof.
      clear. intros.
      repeat rewrite SH.starred_def.
      induction H; simpl; intros;
      repeat match goal with
               | [ H : _ |- _ ] => rewrite H
             end; try reflexivity; heq_canceler.
    Qed.

    Lemma fold_Permutation : forall imps L R,
      Permutation.Permutation L R ->
      Permutation.Permutation
      (FM.fold (fun (f : FM.key) (argss : list (exprs types)) (acc : list (exprs types * FM.key)) =>
        map (fun args : exprs types => (args, f)) argss ++ acc) imps L)
      (FM.fold
        (fun k : FM.key =>
         fold_left
           (fun (acc : cancel_list) (args : exprs types) =>
            Ordering.insert_in_order (exprs types * nat) meta_order_funcs
              (args, k) acc)) imps R).
    Proof.
      clear. intros.
      eapply @MM.PROPS.fold_rel; simpl; intros; auto.
        revert H1; clear. revert a; revert b; induction e; simpl; intros; auto.
        rewrite <- IHe; eauto.
        
        destruct (@Ordering.insert_in_order_inserts (exprs types * nat) meta_order_funcs (a,k) b) as [ ? [ ? [ ? ? ] ] ].
        subst. rewrite H.
        rewrite <- app_ass.
        eapply Permutation.Permutation_cons_app.
        rewrite app_ass. eapply Permutation.Permutation_app; eauto.
    Qed.

    Lemma order_impures_D : forall U G cs imps,
      heq funcs preds U G cs 
        (SH.impuresD _ _ imps)
        (SH.starred (fun v => (Func (snd v) (fst v))) (order_impures imps) Emp).
    Proof.
      clear. intros. rewrite impuresD'_flatten. unfold order_impures.
      eapply starred_perm. eapply fold_Permutation. reflexivity.
    Qed.
    
    (** NOTE : l and r are reversed here **)
    Fixpoint cancel_in_order (bound : nat) (summ : Facts Prover) 
      (ls : cancel_list) (acc rem : MM.mmap (exprs types)) (sub : U.Subst types) 
      : MM.mmap (exprs types) * MM.mmap (exprs types) * U.Subst types :=
      match ls with
        | nil => (acc, rem, sub)
        | (args,f) :: ls => 
          match FM.find f rem with
            | None => cancel_in_order bound summ ls (MM.mmap_add f args acc) rem sub
            | Some argss =>
              match nth_error preds f with
                | None => cancel_in_order bound summ ls (MM.mmap_add f args acc) rem sub (** Unused! **)
                | Some ts => 
                  match unify_remove bound summ args (SDomain ts) argss sub with
                    | None => cancel_in_order bound summ ls (MM.mmap_add f args acc) rem sub
                    | Some (rem', sub) =>
                      cancel_in_order bound summ ls acc (FM.add f rem' rem) sub
                  end
              end                      
          end
      end.
    
    Definition sheapInstantiate (s : U.Subst types) : MM.mmap (exprs types) -> MM.mmap (exprs types) :=
      MM.mmap_map (map (@U.exprInstantiate _ s)).

    Lemma sheapInstantiate_mmap_add : forall U G cs S n e acc,
      heq funcs preds U G cs
        (SH.impuresD pcType stateType 
          (sheapInstantiate S (MM.mmap_add n e acc)))
        (SH.impuresD pcType stateType 
          (MM.mmap_add n (map (@U.exprInstantiate _ S) e) 
                         (sheapInstantiate S acc))).
    Proof.
      clear. intros. eapply MM.PROPS.map_induction with (m := acc); intros.
      { unfold MM.mmap_add, sheapInstantiate, MM.mmap_map.
        repeat rewrite MF.find_Empty by auto using MF.map_Empty.
        rewrite SH.impuresD_Equiv. reflexivity.
        rewrite MF.map_add. simpl.
        reflexivity. }
      { unfold MM.mmap_add, sheapInstantiate, MM.mmap_map.
        rewrite MF.FACTS.map_o. simpl in *. unfold exprs in *. case_eq (FM.find n m'); simpl; intros.
        { rewrite SH.impuresD_Equiv. reflexivity.
          rewrite MF.map_add. reflexivity. }
        { rewrite SH.impuresD_Equiv. reflexivity.
          rewrite MF.map_add. simpl. reflexivity. } }
    Qed.

    Lemma sheapInstantiate_Equiv : forall S a b,
      MM.mmap_Equiv a b ->
      MM.mmap_Equiv (sheapInstantiate S a) (sheapInstantiate S b).
    Proof.
      clear. unfold sheapInstantiate, MM.mmap_Equiv, MM.mmap_map, FM.Equiv; intuition;
      try solve [ repeat match goal with
                           | [ H : FM.In _ (FM.map _ _) |- _ ] => apply MF.FACTS.map_in_iff in H
                           | [ |- FM.In _ (FM.map _ _) ] => apply MF.FACTS.map_in_iff
                         end; firstorder ].
      repeat match goal with
               | [ H : FM.MapsTo _ _ (FM.map _ _) |- _ ] =>
                 apply MF.FACTS.map_mapsto_iff in H; destruct H; intuition; subst
             end.
      apply Permutation.Permutation_map. firstorder.
    Qed.

    Lemma cancel_in_order_equiv : forall bound summ ls acc rem sub L R S acc',
      MM.mmap_Equiv acc acc' ->
      cancel_in_order bound summ ls acc rem sub = (L, R, S) ->
      exists L' R' S',
        cancel_in_order bound summ ls acc' rem sub = (L', R', S') /\
        MM.mmap_Equiv L L' /\
        MM.mmap_Equiv R R' /\
        U.Subst_Equal S S'.
    Proof.
      clear. induction ls; simpl; intros.
      { inversion H0; subst; auto. 
        do 3 eexists. split; [ reflexivity | intuition ]. }
      { repeat match goal with
                 | [ H : match ?X with 
                           | (_,_) => _
                         end = _ |- _ ] => destruct X
                 | [ H : match ?X with
                           | Some _ => _ | None => _ 
                         end = _ |- _ ] =>
                 revert H; case_eq X; intros
                 
               end;
        (eapply IHls; [ eauto using MM.mmap_add_mor | eassumption ]). }
    Qed.

    Lemma cancel_in_order_mmap_add_acc : forall bound summ ls n e acc rem sub L R S,
      cancel_in_order bound summ ls (MM.mmap_add n e acc) rem sub = (L, R, S) ->
      exists L' R' S',
        cancel_in_order bound summ ls acc rem sub = (L', R', S') /\
        MM.mmap_Equiv (MM.mmap_add n e L') L /\
        MM.mmap_Equiv R R' /\
        U.Subst_Equal S S'.
    Proof.
      clear. induction ls; simpl; intros.
      { inversion H; subst. do 3 eexists; split. 
        reflexivity. split; try reflexivity. split; try reflexivity. }
      { repeat match goal with
                 | [ H : match ?X with 
                           | (_,_) => _
                         end = _ |- _ ] => destruct X
                 | [ H : match ?X with
                           | Some _ => _ | None => _ 
                         end = _ |- _ ] =>
                 revert H; case_eq X; intros
                 
               end;
        try solve [ eapply IHls; eauto ];
        match goal with
          | [ H : cancel_in_order _ _ _ _ _ _ = _ |- _ ] =>
            eapply cancel_in_order_equiv in H; [ | eapply MM.mmap_add_comm ]
        end;
        repeat match goal with
                 | [ H : exists x, _ |- _ ] => destruct H
                 | [ H : _ /\ _ |- _ ] => destruct H
               end;
        match goal with
          | [ H : cancel_in_order _ _ _ _ _ _ = _ |- _ ] =>
            eapply IHls in H
        end;
        repeat match goal with
                 | [ H : exists x, _ |- _ ] => destruct H
                 | [ H : _ /\ _ |- _ ] => destruct H
                 | [ |- exists x, _ /\ _ ] => eexists; split; [ eassumption | ]
                 | [ |- exists x, _ ] => eexists
                 | [ H : MM.mmap_Equiv _ _ |- _ ] => rewrite H
                 | [ H : U.Subst_Equal _ _ |- _ ] => rewrite H
               end; intuition reflexivity. }
    Qed.

(*
    Lemma cancel_in_order_add_acc : forall bound summ ls n e acc rem sub L R S,
      ~FM.In n acc ->
      cancel_in_order bound summ ls (FM.add n e acc) rem sub = (L, R, S) ->
      exists L' R' S',
        cancel_in_order bound summ ls acc rem sub = (L', R', S') /\
        MM.mmap_Equiv (FM.add n e L') L /\
        MM.mmap_Equiv R R' /\
        U.Subst_Equal S S'.
    Proof.
      clear. induction ls; simpl; intros.
      { inversion H0; subst. do 3 eexists; split. 
        reflexivity. split; try reflexivity. split; try reflexivity. }
      { repeat match goal with
                 | [ H : match ?X with 
                           | (_,_) => _
                         end = _ |- _ ] => destruct X
                 | [ H : match ?X with
                           | Some _ => _ | None => _ 
                         end = _ |- _ ] =>
                 revert H; case_eq X; intros
                 
               end;
        try solve [ eapply IHls; eauto |
        match goal with
          | [ H : cancel_in_order _ _ _ _ _ _ = _ |- _ ] =>
            eapply cancel_in_order_equiv in H; [ | eapply MM.mmap_add_comm ]
        end;
        repeat match goal with
                 | [ H : exists x, _ |- _ ] => destruct H
                 | [ H : _ /\ _ |- _ ] => destruct H
               end;
        match goal with
          | [ H : cancel_in_order _ _ _ _ _ _ = _ |- _ ] =>
            eapply IHls in H
        end;
        repeat match goal with
                 | [ H : exists x, _ |- _ ] => destruct H
                 | [ H : _ /\ _ |- _ ] => destruct H
                 | [ |- exists x, _ /\ _ ] => eexists; split; [ eassumption | ]
                 | [ |- exists x, _ ] => eexists
                 | [ H : MM.mmap_Equiv _ _ |- _ ] => rewrite H
                 | [ H : U.Subst_Equal _ _ |- _ ] => rewrite H
               end; intuition reflexivity ].
        Focus 3.
        match goal with
          | [ H : cancel_in_order _ _ _ _ _ _ = _ |- _ ] =>
            eapply cancel_in_order_equiv in H; [ | ]
        end.
        repeat match goal with
                 | [ H : exists x, _ |- _ ] => destruct H
                 | [ H : _ /\ _ |- _ ] => destruct H
               end;
        match goal with
          | [ H : cancel_in_order _ _ _ _ _ _ = _ |- _ ] =>
            eapply IHls in H
        end.



 }
    Qed.
*)

    Lemma sheapInstantiate_add : forall U G cs S n e acc,
      heq funcs preds U G cs
        (SH.impuresD pcType stateType (sheapInstantiate S (FM.add n e acc)))
        (SH.starred (fun v => Func n (map (U.exprInstantiate S) v)) e
          (SH.impuresD pcType stateType (sheapInstantiate S (FM.remove n acc)))).
    Proof.
      clear. intros.
        unfold sheapInstantiate, MM.mmap_map.
    Admitted.

    Lemma cancel_in_orderOk : forall U G cs bound summ ls acc rem sub L R S,
      cancel_in_order bound summ ls acc rem sub = (L, R, S) ->
      himp funcs preds U G cs 
        (SH.impuresD _ _ (sheapInstantiate S R))
        (SH.impuresD _ _ (sheapInstantiate S L)) ->
      himp funcs preds U G cs 
        (SH.impuresD _ _ (sheapInstantiate S rem))
        (Star (SH.starred (fun v => (Func (snd v) (map (@U.exprInstantiate _ S) (fst v)))) ls Emp)
              (SH.impuresD _ _ (sheapInstantiate S acc))).
    Proof.
      induction ls; simpl; intros.
      { inversion H; clear H; subst.
        rewrite SH.starred_def. simpl. heq_canceler. auto. }
      { repeat match goal with
                 | [ H : match ?X with 
                           | (_,_) => _
                         end = _ |- _ ] => destruct X
                 | [ H : match ?X with
                           | Some _ => _ | None => _ 
                         end = _ |- _ ] =>
                 revert H; case_eq X; intros
               end.
        { eapply IHls in H3; eauto.
          rewrite SH.impuresD_Equiv.
          2: eapply sheapInstantiate_Equiv.
          2: eapply MF.equiv_eq_mor.
          2: reflexivity. 3: reflexivity. 2: symmetry. 2: apply MF.MapsTo_add_remove_Equal.
          2: eapply MF.FACTS.find_mapsto_iff; eauto.
          
(*
          rewrite sheapInstantiate_add in H3.
          rewrite sheapInstantiate_add.

        eapply cancel_in_order_mmap_add_acc in H3.
        rewrite IHls. 2: 
        

destruct a. 
        revert H. case_eq (FM.find n rem).
        { admit. }
        { intros.


    eapply IHls in H; destruct H; intuition; subst. eexists.

    eapply IHls in H1; destruct H1; intuition; subst.
    eapply IHls in H.
  


etransitivity. 
          rewrite IHls.


          rewrite sheapInstantiate_mmap_add in H1.
          SearchAbout SH.impuresD.


          Lemma impuresD_mmap_add : forall
    (U G : env types)
    (cs : codeSpec (tvarD types pcType) (tvarD types stateType)) 
    f args
    (i : FM.t (list (exprs types))),
  SH.SE.heq funcs preds U G cs 
    (SH.impuresD pcType stateType (MM.mmap_add f args i))
    (SH.SE.Star (SH.SE.Func f args)
       (SH.impuresD pcType stateType i)).
          Proof.
          Admitted.
          rewrite impuresD_mmap_add in H1.
*)
    Admitted.


    Definition sepCancel (bound : nat) (summ : Facts Prover) (l r : SH.SHeap types pcType stateType) :
      SH.SHeap _ _ _ * SH.SHeap _ _ _ * U.Subst types :=
      let ordered_r := order_impures (SH.impures r) in
      let sorted_l := FM.map (fun v => Ordering.sort _ meta_order_args v) (SH.impures l) in 
      let '(rf, lf, sub) := 
        cancel_in_order bound summ ordered_r (MM.empty _) sorted_l (U.Subst_empty _)
      in
      ({| SH.impures := lf ; SH.pures := SH.pures l ; SH.other := SH.other l |},
       {| SH.impures := rf ; SH.pures := SH.pures r ; SH.other := SH.other r |},
       sub).

    Theorem sepCancel_correct : forall U G cs bound summ l r l' r' sub,
      Valid Prover_correct U G summ ->
      sepCancel bound summ l r = (l', r', sub) ->
      himp funcs preds U G cs (SH.sheapD l) (SH.sheapD r) ->
      U.Subst_equations funcs U G sub ->
      himp funcs preds U G cs (SH.sheapD l') (SH.sheapD r').
    Proof.
      clear. destruct l; destruct r. unfold sepCancel. simpl.
      intros. repeat rewrite sheapD_sheapD'. repeat rewrite sheapD_sheapD' in H1.
      destruct l'; destruct r'. 

      
    Admitted.

  End env.

End Make.
