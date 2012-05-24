Require Import List DepList Word Memory.
Require Import Heaps SepTheoryX.
Require Import Expr SepHeap.
Require Import Prover.
Require Import PropX.
Require Import Env.

Set Implicit Arguments.
Set Strict Implicit.

Module MemoryEvaluator (SH : SepHeap).
  Module SEP := SH.SE.
  Module ST := SEP.ST.

  (** Learn hook **)
  Section LearnHook.
    Variable types_ : list type.
    Variable SymState : Type.

    Definition LearnHook : Type := 
      forall P : ProverT types_, SymState -> Facts P -> SymState.

    Variables pcT stT : tvar.

    Record LearnHook_correct (L : LearnHook) 
      (stateD : env types_ -> env types_ -> 
        codeSpec (tvarD types_ pcT) (tvarD types_ stT) -> tvarD types_ stT -> SymState -> Prop)
      (funcs : functions types_) 
      (preds : SEP.predicates types_ pcT stT) : Prop :=
    { hook_sound : forall P (PC : ProverT_correct P funcs),
      forall uvars vars cs stn_st ss ss' pp,
        stateD uvars vars cs stn_st ss ->
        Valid PC uvars vars pp ->
        L P ss pp = ss' ->
        stateD uvars vars cs stn_st ss'
    }.
  End LearnHook.

  Module LearnHookDefault.

    Definition LearnHook_default (types : list type) (State : Type) : 
      LearnHook types State :=
      fun _ x _ => x.
    
    Definition LearnHook_default_correct types pcT stT State stateD funcs preds :
      @LearnHook_correct types pcT stT State (@LearnHook_default _ _) stateD funcs preds.
    Proof.
      unfold LearnHook_default; econstructor; intros; subst; auto.
    Qed.

    Ltac unfolder H :=
      match H with 
        | tt => cbv delta [ LearnHook_default ]
        | _ => cbv delta [ LearnHook_default ] in H
      end.
  End LearnHookDefault.

  Section MemEvaluator.
    Variable types : list type.
    Variables pcT stT : tvar.

    Record MemEvaluator : Type :=
    { smemeval_read_word : forall (P : ProverT types), Facts P -> 
      expr types -> SH.SHeap types pcT stT -> option (expr types)
    ; smemeval_write_word : forall (P : ProverT types), Facts P ->
      expr types -> expr types -> SH.SHeap types pcT stT -> option (SH.SHeap types pcT stT)
    }.

    Variable eval : MemEvaluator.

    Variable funcs : functions types.
    Variable preds : SEP.predicates types pcT stT.

    Variable stn_st : Type.
    
    Variables ptrT valT : tvar.

    Hypothesis mem_satisfies : PropX.codeSpec (tvarD types pcT) (tvarD types stT) -> ST.hprop (tvarD types pcT) (tvarD types stT) nil -> stn_st -> Prop.
    Hypothesis ReadWord : stn_st -> tvarD types ptrT -> option (tvarD types valT).
    Hypothesis WriteWord : stn_st -> tvarD types ptrT -> tvarD types valT -> option stn_st.

    Record MemEvaluator_correct : Type :=
    { ReadCorrect :
      forall (P : ProverT types) (PE : ProverT_correct P funcs),
        forall facts pe ve SH,
          smemeval_read_word eval P facts pe SH = Some ve ->
          forall uvars vars cs p stn_m,
            Valid PE uvars vars facts ->
            exprD funcs uvars vars pe ptrT = Some p ->
            mem_satisfies cs (SEP.sexprD funcs preds uvars vars (SH.sheapD SH)) stn_m ->
            match exprD funcs uvars vars ve valT with
              | Some v =>
                ReadWord stn_m p = Some v
              | _ => False
            end
    ; WriteCorrect :
      forall (P : ProverT types) (PE : ProverT_correct P funcs),
        forall uvars vars cs facts pe ve SH SH',
          smemeval_write_word eval P facts pe ve SH = Some SH' ->
          Valid PE uvars vars facts ->
          forall p v,
            exprD funcs uvars vars pe ptrT = Some p ->
            exprD funcs uvars vars ve valT = Some v ->
            forall stn_m,
            mem_satisfies cs (SEP.sexprD funcs preds uvars vars (SH.sheapD SH)) stn_m ->
            match WriteWord stn_m p v with
              | None => False
              | Some stn_m' =>
                mem_satisfies cs (SEP.sexprD funcs preds uvars vars (SH.sheapD SH')) stn_m'
            end
    }.
  End MemEvaluator.

  Record MemEvaluatorPackage (tr : Repr type) (pc st ptr val : tvar) 
    (sat : forall ts, codeSpec (tvarD (repr tr ts) pc) (tvarD (repr tr ts) st) -> 
      ST.hprop (tvarD (repr tr ts) pc) (tvarD (repr tr ts) st) nil -> tvarD (repr tr ts) st -> Prop) 
    (read  : forall ts, tvarD (repr tr ts) st -> tvarD (repr tr ts) ptr -> option (tvarD (repr tr ts) val))
    (write : forall ts, tvarD (repr tr ts) st -> tvarD (repr tr ts) ptr -> tvarD (repr tr ts) val -> option (tvarD (repr tr ts) st))
    : Type :=
  { MemEvalTypes : Repr type
  ; MemEvalFuncs : forall ts, Repr (signature (repr tr (repr MemEvalTypes ts)))
  ; MemEvalPreds : forall ts, Repr (SEP.ssignature (repr tr (repr MemEvalTypes ts)) pc st)
  ; MemEval : forall ts, MemEvaluator (repr tr (repr MemEvalTypes ts)) pc st
  ; MemEval_correct : forall ts fs ps, 
    @MemEvaluator_correct (repr tr (repr MemEvalTypes ts)) pc st (MemEval ts)
      (repr (MemEvalFuncs ts) fs) (repr (MemEvalPreds ts) ps)
      (tvarD (repr tr (repr MemEvalTypes ts)) st) ptr val
      (sat (repr MemEvalTypes ts)) (read (repr MemEvalTypes ts)) (write (repr MemEvalTypes ts))
  }.

  Module Default.
    Section with_prover.
      Variable types : list type.
      Variables pcT stT : tvar.
      Variable prover : ProverT types.
      
      Definition smemeval_read_word_default (_ : Facts prover) (_ : expr types)
        (_ : SH.SHeap types pcT stT) : option (expr types) :=
        None.

      Definition smemeval_write_word_default (_ : Facts prover)
        (_ : expr types) (_ : expr types) (_ : SH.SHeap types pcT stT)
        : option (SH.SHeap types pcT stT) :=
        None.
    End with_prover.

    Definition MemEvaluator_default types pcT stT : MemEvaluator types pcT stT.
    constructor.
    eapply smemeval_read_word_default.
    eapply smemeval_write_word_default.
    Defined.

    Definition MemEvaluator_default_correct types' (pcT stT : tvar) funcs preds X Y Z A B C :
      @MemEvaluator_correct types' pcT stT (MemEvaluator_default types' pcT stT) funcs preds X Y Z A B C.
    econstructor.
      simpl; unfold smemeval_read_word_default, smemeval_write_word_default; simpl; congruence.
      simpl; unfold smemeval_read_word_default, smemeval_write_word_default; simpl; congruence.
    Qed.

    Ltac unfolder H :=
      cbv delta 
        [ smemeval_read_word_default
          smemeval_write_word_default
          MemEvaluator_default
        ] in H.

    Definition package tr pcT stT ptr val X Y Z : @MemEvaluatorPackage tr pcT stT ptr val X Y Z :=
      {| MemEvalTypes := nil_Repr EmptySet_type
       ; MemEvalFuncs := fun ts => nil_Repr (Default_signature _)
       ; MemEvalPreds := fun ts => nil_Repr (SEP.Default_predicate _ pcT stT)
       ; MemEval := fun ts => MemEvaluator_default _ _ _
       ; MemEval_correct := fun ts fs ps => MemEvaluator_default_correct _ _ _ _ _ _ _ 
       |}.

  End Default.

  (** Plugins are symbolic evaluators that handle single predicates **)
  Module Plugin.
    Module SEP := SEP.
    Section typed.
      Variable types : list type.

      Record MemEvalPred : Type :=
      { smem_read  : 
        forall (P : ProverT types) (facts : Facts P) (args : exprs types) (p : expr types),
          option (expr types)
      ; smem_write : 
        forall (P : ProverT types) (facts : Facts P) (args : exprs types) (p v : expr types),
          option (exprs types)
      }.

      Theorem proj_sym_read : forall a b,
        smem_read (Build_MemEvalPred a b) = a.
      Proof. reflexivity. Qed.
      
      Theorem proj_sym_write : forall a b,
        smem_write (Build_MemEvalPred a b) = b.
      Proof. reflexivity. Qed.

      Variable me : MemEvalPred.

      Variables pcT stT : tvar.

      Variable stn_st : Type.
      Variables ptrT valT : tvar.

      Hypothesis mem_satisfies : PropX.codeSpec (tvarD types pcT) (tvarD types stT) -> ST.hprop (tvarD types pcT) (tvarD types stT) nil -> stn_st -> Prop.
      Hypothesis ReadWord : stn_st -> tvarD types ptrT -> option (tvarD types valT).
      Hypothesis WriteWord : stn_st -> tvarD types ptrT -> tvarD types valT -> option stn_st.

      (** TODO: funcs should be removed from this? **)
      Class MemEvalPred_correct (Predicate : SEP.ssignature types pcT stT)
        (funcs : functions types) : Prop :=
      { sym_read_correct : forall P (PE : ProverT_correct P funcs),
        forall args uvars vars cs facts pe p ve stn_st Q,
          smem_read me P facts args pe = Some ve ->
          Valid PE uvars vars facts ->
          exprD funcs uvars vars pe ptrT = Some p ->
          match 
            applyD (exprD funcs uvars vars) (SEP.SDomain Predicate) args _ (SEP.SDenotation Predicate)
            with
            | None => False
            | Some p => mem_satisfies cs (ST.star p Q) stn_st
          end ->
          match exprD funcs uvars vars ve valT with
            | Some v =>
              ReadWord stn_st p = Some v
            | _ => False
          end
       ; sym_write_correct : forall P (PE : ProverT_correct P funcs),
         forall args uvars vars cs facts pe p ve v stn_st args' Q,
           smem_write me P facts args pe ve = Some args' ->
           Valid PE uvars vars facts ->
           exprD funcs uvars vars pe ptrT = Some p ->
           exprD funcs uvars vars ve valT = Some v ->
           match
             applyD (@exprD _ funcs uvars vars) (SEP.SDomain Predicate) args _ (SEP.SDenotation Predicate)
             with
             | None => False
             | Some p => mem_satisfies cs (ST.star p Q) stn_st
           end ->
           match 
             applyD (@exprD _ funcs uvars vars) (SEP.SDomain Predicate) args' _ (SEP.SDenotation Predicate)
             with
             | None => False
             | Some pr => 
               match WriteWord stn_st p v with
                 | None => False
                 | Some sm' => mem_satisfies cs (ST.star pr Q) stn_st
               end
           end
      }.
    End typed.

    Section plugin.
      Variable types : list type.
      Variable pcT stT : tvar.
      Variable evals : list (nat * MemEvalPred types). 

      Section with_prover.
        Variable Prover : ProverT types.

        Section fold_first.
          Variables T V : Type.
          Variable F : T -> option V.

          Fixpoint fold_first (ls : list T) : option V :=
            match ls with
              | nil => None
              | t :: ls =>
                match F t with
                  | None => fold_first ls
                  | x => x
                end
            end.
        End fold_first.

        Section fold_first_update.
          Variable T : Type.
          Variable F : T -> option T.

          Fixpoint fold_first_update (ls : list T) (acc : list T) : option (list T) :=
            match ls with
              | nil => None
              | t :: ls =>
                match F t with
                  | None => fold_first_update ls (t :: acc)
                  | Some v => Some (rev acc ++ v :: ls)
                end
            end.
        End fold_first_update.

        Definition plugin_symeval_read_word (facts : Facts Prover) (p : expr types) 
          (s : SH.SHeap types pcT stT) : option (expr types) :=
          let impures := SH.impures s in
          let reader i_me :=
            let '(i,me) := i_me in
            match FM.find i impures with
              | Some argss =>
                fold_first (fun args => smem_read me Prover facts args p) argss
              | None => None
            end
          in
          fold_first reader evals.

        Definition plugin_symeval_write_word (facts : Facts Prover) (p v : expr types)
          (s : SH.SHeap types pcT stT) : option (SH.SHeap types pcT stT) :=
          let impures := SH.impures s in
          let writer i_me :=
          let '(i,me) := i_me in
            match FM.find i impures with
              | Some argss =>
                match fold_first_update (fun args => smem_write me Prover facts args p v) argss nil with
                  | None => None
                  | Some argss => Some (FM.add i argss impures) (** NOTE : add = replace **)
                end
              | None => None
            end
          in
          match fold_first writer evals with
            | None => None
            | Some impures => Some (SH.Build_SHeap _ _ impures (SH.pures s) (SH.other s))
          end.
      End with_prover.

      Definition MemEvaluator_plugin : MemEvaluator types pcT stT : Type :=
      {| smemeval_read_word := plugin_symeval_read_word
       ; smemeval_write_word := plugin_symeval_write_word
       |}.
    End plugin.

    Section plugin_correct.
      Variable types : list type.
      Variables pcT stT : tvar.      
      Variable evals : list (nat * MemEvalPred types).

      Variable funcs : functions types.
      Variable sfuncs : SEP.predicates types pcT stT .

      Variable stn_st : Type.
      Variables ptrT valT : tvar.

      Hypothesis mem_satisfies : PropX.codeSpec (tvarD types pcT) (tvarD types stT) -> 
        ST.hprop (tvarD types pcT) (tvarD types stT) nil -> stn_st -> Prop.
      Hypothesis ReadWord : stn_st -> tvarD types ptrT -> option (tvarD types valT).
      Hypothesis WriteWord : stn_st -> tvarD types ptrT -> tvarD types valT -> option stn_st.

      Fixpoint all T (P : T -> Prop) (ls : list T) : Prop :=
        match ls with
          | nil => True
          | l :: ls => P l /\ all P ls
        end.

      Definition ConsistentCondition : Prop := 
        all (fun (i_me : nat * MemEvalPred types) => 
          let (i,me) := i_me in
            match nth_error sfuncs i with
              | None => False
              | Some s => @MemEvalPred_correct _ me pcT stT _ ptrT valT mem_satisfies ReadWord WriteWord s funcs
            end) evals.
        
      Hypothesis sfuncs_evals : ConsistentCondition.

      Definition PluginMemEvaluator_correct : 
        @MemEvaluator_correct types _ _ (MemEvaluator_plugin pcT stT evals) funcs sfuncs _ _ _ mem_satisfies ReadWord WriteWord.
      Proof.
        constructor; unfold ConsistentCondition in *; simpl.
          (** read **)
          unfold plugin_symeval_read_word. generalize dependent evals. clear.
          induction evals; simpl; intros; try congruence ;
            repeat match goal with
                     | [ H : False |- _ ] => contradiction
                     | [ H : prod _ _ |- _ ] => destruct H
                     | [ H : context [ match FM.find ?A ?B with
                                         | None => _ 
                                         | Some _ => _ 
                                       end ] |- _ ] => 
                       revert H; case_eq (FM.find A B); intros
                     | [ H : context [ match fold_first ?A ?B with
                                         | None => _ 
                                         | Some _ => _ 
                                       end ] |- _ ] =>
                     revert H; case_eq (fold_first A B); intros
                     | [ H : context [ match nth_error ?A ?B with
                                         | None => _ 
                                         | Some _ => _ 
                                       end ] |- _ ] =>
                     revert H; case_eq (nth_error A B); intros
                     | [ H : _ /\ _ |- _ ] => destruct H; clear H
                     | [ H : Some _ = Some _ |- _ ] => inversion H; clear H; subst
                     | [ H : ?X , H' : ?X -> ?Y |- _ ] => 
                       specialize (H' H)
                   end.
          admit.
          admit.
          admit.


          (** write **)
          revert sfuncs_evals. admit.
      Qed.

    End plugin_correct.

    Ltac unfolder H :=
      cbv delta 
        [ fold_first fold_first_update 
          FM.find FM.add 
          plugin_symeval_read_word
          plugin_symeval_write_word
          MemEvaluator_plugin
          smem_read smem_write 
        ] in H.

  End Plugin.

  Module Composite.
    Section typed.
      Variable types : list type.
      Variable pcT stT : tvar.

      Definition MemEvaluator_composite (l r : MemEvaluator types pcT stT) : MemEvaluator types pcT stT :=
        {| smemeval_read_word := fun P f e h => 
           match smemeval_read_word l P f e h with
             | None => smemeval_read_word r P f e h
             | Some v => Some v
           end
         ; smemeval_write_word := fun P f p v h => 
           match smemeval_write_word l P f p v h with
             | None => smemeval_write_word r P f p v h
             | Some v => Some v
           end
         |}.

      Variables evalL evalR : MemEvaluator types pcT stT.

      Variable funcs : functions types.
      Variable preds : SEP.predicates types pcT stT.

      Variable stn_st : Type.
    
      Variables ptrT valT : tvar.

      Hypothesis mem_satisfies : PropX.codeSpec (tvarD types pcT) (tvarD types stT) -> ST.hprop (tvarD types pcT) (tvarD types stT) nil -> stn_st -> Prop.
      Hypothesis ReadWord : stn_st -> tvarD types ptrT -> option (tvarD types valT).
      Hypothesis WriteWord : stn_st -> tvarD types ptrT -> tvarD types valT -> option stn_st.

      Hypothesis Lcorr : MemEvaluator_correct evalL funcs preds ptrT valT mem_satisfies ReadWord WriteWord.
      Hypothesis Rcorr : MemEvaluator_correct evalR funcs preds ptrT valT mem_satisfies ReadWord WriteWord.

      Theorem MemEvaluator_correct_composite : @MemEvaluator_correct types pcT stT (MemEvaluator_composite evalL evalR)
        funcs preds stn_st ptrT valT mem_satisfies ReadWord WriteWord.
      Proof.
        unfold MemEvaluator_composite. econstructor; intros; simpl in *;
        repeat match goal with 
                 | [ H : match ?X with None => _ | Some _ => _ end = Some _ |- _ ] => revert H; case_eq X; intros
                 | [ H : Some _ = Some _ |- _ ] => inversion H; clear H; subst
                 | [ |- _ ] => 
                   eapply ReadCorrect; [ | eassumption | | | ]; eauto
                 | [ |- _ ] => 
                   eapply WriteCorrect; [ | eassumption | | | | ]; eauto
               end.
      Qed.
    End typed.
  End Composite.

End MemoryEvaluator.


(*
(* TODO: I want this to be a modularization of the plugin proofs *)
Module Type PluginFacts (B : Heap) (ST : SepTheoryX.SepTheoryXType B).
  Parameter Val : Type.

  Parameter  smem_get_value : IL.settings -> B.addr -> ST.HT.smem -> 
    option Val.
  Parameter mem_get_value : IL.settings -> B.addr -> B.mem -> 
    option Val.

  Parameter smem_set_value : IL.settings -> B.addr -> Val
    -> ST.HT.smem -> option ST.HT.smem.
  Parameter mem_set_value : IL.settings -> B.addr -> Val
    -> B.mem -> option B.mem.

  Parameter smem_mem_get : forall stn p sm m v,
    ST.HT.satisfies sm m ->
    smem_get_value stn p sm = Some v ->
    mem_get_value stn p m = Some v.

  Parameter smem_mem_set : forall stn p v sm sm' m,
    ST.HT.satisfies sm m ->
    smem_set_value stn p v sm = Some sm' ->
    exists m', 
      mem_set_value stn p v m = Some m' /\
      ST.HT.satisfies sm' m'.
End PluginFacts.

Module PluginWrap (B : Heap) (ST : SepTheoryX.SepTheoryXType B) (F : PluginFacts B ST) (PLUGIN : EvaluatorPluginType B ST).
  Module Import SEP := PLUGIN.SEP.

  Section typed.
    Variable types : list type.

    Variable tvState : tvar.
    Variable tvPc : tvar.
    Variable tvPtr : tvar.
    Variable tvVal : tvar.
    
    Variable funcs : functions types.
    Variable sfuncs : predicates types tvPc tvState.

    Variable known : list nat.
    Definition evals_type := 
      hlist (fun n : nat => match nth_error sfuncs n with
                              | None => Empty_set 
                              | Some ss => @PLUGIN.SymEval types tvState tvPc tvPtr tvVal
                                F.smem_get_value F.smem_set_value funcs ss
                            end) known.

    Variable evals : evals_type.

    Definition symeval_read (hyps : list (expr types)) (p : expr types) 
      (s : SEP.SHeap types tvPc tvState)
      : option (expr types) :=
      let hyps := hyps ++ pures s in
      let reader ss seb args :=
        PLUGIN.sym_read seb hyps args p
      in
      fold_known _ _ reader (impures s) evals.

    Definition symeval_write (hyps : list (expr types)) (p v : expr types) 
      (s : SEP.SHeap types tvPc tvState)
      : option (SEP.SHeap types tvPc tvState) :=
      let hyps := hyps ++ pures s in
      let writer _ seb args := 
        PLUGIN.sym_write seb hyps args p v
      in
      match fold_known_update _ _ writer (impures s) evals with
        | None => None
        | Some i' => Some {| impures := i' ; pures := pures s ; other := other s |}
      end.

  Lemma symeval_write_correct' : forall hyps pe ve s s',
    symeval_write hyps pe ve s = Some s' ->
    forall cs stn uvars vars m v,
      AllProvable funcs uvars vars hyps ->
      exprD funcs uvars vars ve tvPc = Some v ->
      (exists sm, 
           ST.satisfies cs (SEP.sexprD funcs sfuncs uvars vars (SH.sheapD s)) stn sm
        /\ ST.HT.satisfies sm m) ->
      match exprD funcs uvars vars pe tvPtr with
        | Some p =>
          exists m', 
                F.mem_set_value types _ _ stn p v m = Some m'
            /\ exists sm,
               ST.satisfies cs (SEP.sexprD funcs sfuncs uvars vars (SH.sheapD s')) stn sm
            /\ ST.HT.satisfies sm m'
        | _ => False
      end.
  Proof.
    unfold symeval_write. intros.
    generalize dependent H.
    match goal with
      | [ |- context [ fold_known_update ?A ?B ?C ?D ?E ] ] =>
        case_eq (fold_known_update A B C D E); intros; try congruence
    end.
    eapply fold_known_update_correct in H.
    do 5 destruct H. destruct H2.
    intuition. inversion H3; clear H3; subst. 
        
    eapply fold_args_update_correct in H6.
    repeat match goal with
             | [ H : exists x, _ |- _ ] => destruct H
           end. intuition; subst.
    generalize (SH.sheapD_pures _ _ _ _ _ H4).
    rewrite SH.sheapD_pull_impure in H4 by eauto.
    rewrite SEP.starred_In in H4.
    rewrite <- SEP.heq_star_assoc in H4. rewrite SEP.heq_star_comm in H4.
        
    simpl in *. rewrite H2 in *.
    intros.

    eapply ST.satisfies_star in H4. do 2 destruct H4. intuition.

    eapply PLUGIN.sym_write_correct with (stn := stn) (cs := cs) (m := x2)
      in H3; eauto.

    2: apply AllProvable_app; eauto.
(*    
    2: simpl in *;
    match goal with
      | [ |- context [ applyD ?A ?B ?C ?D ?E ] ] =>
        destruct (applyD A B C D E); try solve [ intros; intuition | eapply ST.satisfies_pure in H4; PropXTac.propxFo ]
    end.

    destruct (exprD funcs uvars vars pe pcT); eauto.

    repeat match goal with
             | [ H : context [ match applyD ?A ?B ?C ?D ?E with
                                 | Some _ => _
                                 | None => _ 
                               end ] |- _ ] =>
               generalize dependent H; case_eq (applyD A B C D E); intros; intuition
             | [ H : SepIL.ST.satisfies _ (SepIL.ST.inj _) _ _ |- _ ] =>
               eapply SepIL.ST.satisfies_pure in H; PropXTac.propxFo; instantiate; intuition
           end.
    generalize dependent H8. case_eq (smem_write stn t v x2); intros; intuition.
    
    exists (SepIL.ST.HT.join s0 x3).
    intuition.

    rewrite SH.sheapD_pull_impure by eapply FM.find_add.
    simpl. rewrite FM.remove_add.
    eapply SepIL.ST.satisfies_star. do 2 eexists. split.

    unfold tvarD in H4.

    generalize dependent H3.
    case_eq (SepIL.ST.HT.smem_set_word (IL.explode stn) a v x2); [ intros |
      match goal with 
        | [ |- context [ applyD ?A ?B ?C ?D ?E ] ] =>
          destruct (applyD A B C D E); intros; exfalso; assumption
      end ].
        
        exists (ST.HT.join s0 x3).
        rewrite sheapD_pull_impure by eapply FM.find_add.
        simpl. rewrite FM.remove_add.
        rewrite starred_In.
        simpl. rewrite H2. generalize dependent H8. 
        rewrite <- ST.heq_star_assoc. rewrite ST.heq_star_comm. 
        match goal with
          | [ |- context [ applyD ?A ?B ?C ?D ?E ] ] =>
            destruct (applyD A B C D E); try solve [ intros; intuition ]
        end. 
        generalize dependent H9.
        match goal with
          | [ |- ST.satisfies _ ?Y _ _ -> _ -> ST.satisfies _ (ST.star _ ?X) _ _ /\ _ ] => 
            change X with Y; generalize dependent Y
        end.
        intros.

        generalize (ST.HT.split_set_word _ _ (proj1 H7) _ _ _ _ H3).
        split.
        eapply ST.satisfies_star. do 2 eexists. split; eauto. eapply ST.HT.disjoint_split_join; eauto. tauto.

        eapply ST.HT.satisfies_set_word. eauto. destruct H7; subst. tauto.

        unfold tvarD. generalize dependent H4.
        match goal with
          | [ |- context [ applyD ?A ?B ?C ?D ?E ] ] =>
            destruct (applyD A B C D E); try solve [ intros; intuition ]
        end. intros.
        eapply ST.satisfies_pure in H4. PropXTac.propxFo.
      Qed.
*)
  Admitted.
  End typed.
End PluginWrap.

Module PluginFacts_Word <: PluginFacts SepIL.BedrockHeap SepIL.ST.
  Definition smem_get_value :=
  
End PluginFacts_Word.
*)

(*
Module Evaluator (B : Heap) (ST : SepTheoryX.SepTheoryXType B).
  Module Import SEP := SepExpr B ST.

  Section typed.
    Variable types' : list type.

    Variable stateIndex : nat.
    Variable pcIndex : nat.
    Variable ptrIndex : nat.
    Definition ptrType : type :=
      {| Impl := B.addr
       ; Eq := fun x y => match B.addr_dec x y with
                           | left pf => Some pf
                           | _ => None
                         end
       |}.

    (** * Bytes *)
    Section ByteAccess.
      Variable byteIndex : nat.
      Definition byteType : type :=
        {| Impl := B
         ; Eq := fun x y => match weq x y with
                              | left pf => Some pf
                              | _ => None
                            end
         |}.

      Hypothesis byte_ptr : byteIndex <> ptrIndex.

      Definition btypes := 
        updatePosition ptrIndex ptrType (updatePosition byteIndex byteType types').

      Variable funcs : functions btypes.

      Lemma ptrType_get : tvarD btypes (tvType ptrIndex) = B.addr.
        unfold btypes, tvarD. rewrite updatePosition_eq. reflexivity.
      Qed.

      Definition exprD_ptr (uvars vars : env btypes)
        (e : expr btypes) : option B.addr :=
        match ptrType_get in _ = t return option t with
          | refl_equal => exprD funcs uvars vars e (tvType ptrIndex)
        end.

      Lemma byteType_get : tvarD btypes (tvType byteIndex) = B.
        unfold btypes, tvarD. rewrite updatePosition_neq; auto;
        rewrite updatePosition_eq; auto. congruence.
      Qed.

      Definition exprD_byte (uvars vars : env btypes)
        (e : expr btypes) : option B :=
        match byteType_get in _ = t return option t with
          | refl_equal => exprD funcs uvars vars e (tvType byteIndex)
        end.

      Record SymEval_byte (Predicate : ssignature btypes (tvType pcIndex) (tvType stateIndex))
        : Type :=
      { sym_read_byte  : 
        forall (hyps args : list (expr btypes)) (p : expr btypes), option (expr btypes)
      ; sym_write_byte : 
        forall (hyps args : list (expr btypes)) (p v : expr btypes),
        option (list (expr btypes))
      ; sym_read_byte_correct : forall args uvars vars cs hyps pe ve m stn,
        sym_read_byte hyps args pe = Some ve ->
        AllProvable funcs uvars vars hyps ->
        match 
          applyD (@exprD _ funcs uvars vars) (SDomain Predicate) args _ (SDenotation Predicate)
          with
          | None => False
          | Some p => ST.satisfies cs p stn m
        end ->
        match exprD_ptr uvars vars pe , exprD_byte uvars vars ve with
          | Some p , Some v =>
            ST.HT.smem_get p m = Some v
          | _ , _ => False
        end
      ; sym_write_byte_correct : forall args uvars vars cs hyps pe ve v m stn args',
        sym_write_byte hyps args pe ve = Some args' ->
        AllProvable funcs uvars vars hyps ->
        exprD_byte uvars vars ve = Some v ->
        match
          applyD (@exprD _ funcs uvars vars) (SDomain Predicate) args _ (SDenotation Predicate)
          with
          | None => False
          | Some p => ST.satisfies cs p stn m
        end ->
        match exprD_ptr uvars vars pe with
          | Some p =>
            match 
              applyD (@exprD _ funcs uvars vars) (SDomain Predicate) args' _ (SDenotation Predicate)
              with
              | None => False
              | Some pr => 
                match ST.HT.smem_set p v m with
                  | None => False
                  | Some sm' =>
                    ST.satisfies cs pr stn sm'
                end
            end
          | _ => False
        end
      }.

      Definition defaultSymEval_byte (P : ssignature btypes (tvType pcIndex) (tvType stateIndex))
        : SymEval_byte P.
      refine (
        {| sym_read_byte          := fun _ _ _ => None
         ; sym_write_byte         := fun _ _ _ _ => None
         ; sym_read_byte_correct  := _
         ; sym_write_byte_correct := _
         |}); 
      abstract (simpl; intros; congruence).
      Defined.

      Variable sfuncs : list (ssignature btypes (tvType pcIndex) (tvType stateIndex)).

      Variable known : list nat. 
      Variable evals : hlist (fun n : nat => match nth_error sfuncs n with
                                               | None => Empty_set 
                                               | Some ss => SymEval_byte ss
                                             end) known.

      Definition symeval_read_byte (hyps : list (expr btypes)) (p : expr btypes) 
        (s : SHeap btypes (tvType pcIndex) (tvType stateIndex))
        : option (expr btypes) :=
        let hyps := hyps ++ pures s in
        let reader _ seb args := 
          sym_read_byte seb hyps args p
        in
        fold_known _ _  reader (impures s) evals.

      Theorem symeval_read_byte_correct : forall cs stn hyps pe ve s uvars vars (m : B.mem),
        symeval_read_byte hyps pe s = Some ve ->
        AllProvable funcs uvars vars hyps ->
        (exists sm, 
          ST.satisfies cs (sexprD funcs sfuncs uvars vars (sheapD s)) stn sm
          /\ ST.HT.satisfies sm m) ->
        match exprD_ptr uvars vars pe , exprD_byte uvars vars ve with
          | Some p , Some v => 
            B.mem_get m p = Some v
          | _ , _ => False
        end.
      Proof.
        unfold symeval_read_byte. intros.
        eapply fold_known_correct in H.
        do 5 destruct H. destruct H1.
        intuition.

        generalize (sheapD_pures _ _ _ _ _ H); intros.

        eapply sheapD_pull_impure 
          with (funcs := funcs) (sfuncs := sfuncs) (a := uvars) (c := vars0) (cs := cs)
            in H1.
        apply In_split in H3. destruct H3. destruct H3.
        subst. rewrite starred_In in H1.

        rewrite <- heq_star_assoc in H1. rewrite heq_star_comm in H1.
        rewrite H1 in H.
        simpl in H.
        eapply ST.satisfies_star in H. destruct H. destruct H. intuition.
        rewrite H2 in *.
 
        eapply sym_read_byte_correct 
          with (uvars := uvars) (vars := vars0) (cs := cs) (stn := stn) (m := x2)
          in H6.
        2: eapply AllProvable_app; auto.
        destruct (exprD_ptr uvars vars0 pe); auto.
        destruct (exprD_byte uvars vars0 ve); auto.
        eapply ST.HT.satisfies_get. eauto.

        eapply ST.HT.split_smem_get; eauto.
        unfold tvarD.
        match goal with 
          | [ |- context [ applyD ?A ?B ?C ?D ?E ] ] =>
            destruct (applyD A B C D E)
        end; auto.
        eapply ST.satisfies_pure in H. PropXTac.propxFo.
      Qed.

      Definition symeval_write_byte (hyps : list (expr btypes)) (p v : expr btypes) 
        (s : SHeap btypes (tvType pcIndex) (tvType stateIndex))
        : option (SHeap btypes (tvType pcIndex) (tvType stateIndex)) :=
        let hyps := hyps ++ pures s in
        let writer _ seb args := 
          sym_write_byte seb hyps args p v
        in
        match fold_known_update _ _ writer (impures s) evals with
          | None => None
          | Some i' => Some {| impures := i' ; pures := pures s ; other := other s |}
        end.

      Theorem symeval_write_byte_correct : forall cs stn hyps pe ve v s s' uvars vars (m : B.mem),
        symeval_write_byte hyps pe ve s = Some s' ->
        AllProvable funcs uvars vars hyps ->
        exprD_byte uvars vars ve = Some v ->
        (exists sm, 
             ST.satisfies cs (sexprD funcs sfuncs uvars vars (sheapD s)) stn sm
          /\ ST.HT.satisfies sm m) ->
        match exprD_ptr uvars vars pe with
          | Some p =>
            exists sm, 
              ST.satisfies cs (sexprD funcs sfuncs uvars vars (sheapD s')) stn sm
              /\ ST.HT.satisfies sm (B.mem_set m p v)
          | _ => False
        end.
      Proof.
        unfold symeval_write_byte. intros.
        generalize dependent H.
        match goal with
          | [ |- context [ fold_known_update ?A ?B ?C ?D ?E ] ] =>
            case_eq (fold_known_update A B C D E); intros; try congruence
        end.
        eapply fold_known_update_correct in H.
        do 5 destruct H. destruct H2.
        intuition. inversion H3; clear H3; subst. 
        
        eapply fold_args_update_correct in H6.
        repeat match goal with
                 | [ H : exists x, _ |- _ ] => destruct H
               end. intuition; subst.
        generalize (sheapD_pures _ _ _ _ _ H4).
        rewrite sheapD_pull_impure in H4 by eauto.
        rewrite starred_In in H4.
        rewrite <- heq_star_assoc in H4. rewrite heq_star_comm in H4.
        
        simpl in *. rewrite H2 in *.
        intros.

        eapply ST.satisfies_star in H4. do 2 destruct H4. intuition.

        eapply sym_write_byte_correct with (stn := stn) (cs := cs) (m := x2)
          in H3; eauto.

        2: apply AllProvable_app; eauto.

        destruct (exprD_ptr uvars vars0 pe); eauto.
        unfold tvarD in H3.

        generalize dependent H3.
        case_eq (ST.HT.smem_set a v x2); [ intros |
          match goal with 
            | [ |- context [ applyD ?A ?B ?C ?D ?E ] ] =>
              destruct (applyD A B C D E); intros; exfalso; assumption
          end ].
        
        exists (ST.HT.join s0 x3).
        rewrite sheapD_pull_impure by eapply FM.find_add.
        simpl. rewrite FM.remove_add.
        rewrite starred_In.
        simpl. rewrite H2. generalize dependent H8. 
        rewrite <- ST.heq_star_assoc. rewrite ST.heq_star_comm. 
        match goal with
          | [ |- context [ applyD ?A ?B ?C ?D ?E ] ] =>
            destruct (applyD A B C D E); try solve [ intros; intuition ]
        end. 
        generalize dependent H9.
        match goal with
          | [ |- ST.satisfies _ ?Y _ _ -> _ -> ST.satisfies _ (ST.star _ ?X) _ _ /\ _ ] => 
            change X with Y; generalize dependent Y
        end.
        intros.

        generalize (ST.HT.split_set _ _ (proj1 H7) _ _ _ H3).
        split.
        eapply ST.satisfies_star. do 2 eexists. split; eauto. eapply ST.HT.disjoint_split_join; eauto. tauto.

        eapply ST.HT.satisfies_set. eauto. destruct H7; subst. tauto.

        unfold tvarD. generalize dependent H4.
        match goal with
          | [ |- context [ applyD ?A ?B ?C ?D ?E ] ] =>
            destruct (applyD A B C D E); try solve [ intros; intuition ]
        end. intros.
        eapply ST.satisfies_pure in H4. PropXTac.propxFo.
      Qed.
    End ByteAccess.

    (** * Words *)
    Section WordAccess.
      Variable wordIndex : nat.
      Definition wordType : type :=
        {| Impl := W
          ; Eq := fun x y => match weq x y with
                               | left pf => Some pf
                               | _ => None
                             end
        |}.

      Hypothesis word_ptr : wordIndex <> ptrIndex.

      Definition wtypes := 
        updatePosition ptrIndex ptrType (updatePosition wordIndex wordType types').

      Lemma ptrType_get_w : tvarD wtypes (tvType ptrIndex) = B.addr.
        unfold wtypes, tvarD. rewrite updatePosition_eq. reflexivity.
      Defined.

      Definition exprD_ptr_w funcs (uvars vars : env wtypes)
        (e : expr wtypes) : option B.addr :=
        match ptrType_get_w in _ = t return option t with
          | refl_equal => exprD funcs uvars vars e (tvType ptrIndex)
        end.

      Lemma wordType_get_w : tvarD wtypes (tvType wordIndex) = W.
        unfold wtypes, tvarD. rewrite updatePosition_neq; auto;
        rewrite updatePosition_eq; auto. congruence.
      Defined.

      Definition exprD_word funcs (uvars vars : env wtypes)
        (e : expr wtypes) : option W :=
        match wordType_get_w in _ = t return option t with
          | refl_equal => exprD funcs uvars vars e (tvType wordIndex)
        end.

      Variable funcsT : functions wtypes -> functions wtypes.

      Record SymEval_word (Predicate : ssignature wtypes (tvType pcIndex) (tvType stateIndex))
        : Type :=
      { sym_read_word  : 
        forall (hyps args : list (expr wtypes)) (p : expr wtypes), option (expr wtypes)
      ; sym_write_word : 
        forall (hyps args : list (expr wtypes)) (p v : expr wtypes),
        option (list (expr wtypes))
      ; sym_read_word_correct : forall funcs args uvars vars cs hyps pe ve m stn,
        sym_read_word hyps args pe = Some ve ->
        AllProvable (funcsT funcs) uvars vars hyps ->
        match 
          applyD (exprD (funcsT funcs) uvars vars) (SDomain Predicate) args _ (SDenotation Predicate)
          with
          | None => False
          | Some p => ST.satisfies cs p stn m
        end ->
        match 
          exprD_ptr_w (funcsT funcs) uvars vars pe , 
          exprD_word (funcsT funcs) uvars vars ve
          with
          | Some p , Some v =>
            ST.HT.smem_get_word (IL.implode stn) p m = Some v
          | _ , _ => False
        end
      ; sym_write_word_correct : forall funcs args uvars vars cs hyps pe ve v m stn args',
        sym_write_word hyps args pe ve = Some args' ->
        AllProvable (funcsT funcs) uvars vars hyps ->
        exprD_word (funcsT funcs) uvars vars ve = Some v ->
        match
          applyD (@exprD _ (funcsT funcs) uvars vars) (SDomain Predicate) args _ (SDenotation Predicate)
          with
          | None => False
          | Some p => ST.satisfies cs p stn m
        end ->
        match exprD_ptr_w (funcsT funcs) uvars vars pe with
          | Some p =>
            match 
              applyD (@exprD _ (funcsT funcs) uvars vars) (SDomain Predicate) args' _ (SDenotation Predicate)
              with
              | None => False
              | Some pr => 
                match ST.HT.smem_set_word (IL.explode stn) p v m with
                  | None => False
                  | Some sm' => ST.satisfies cs pr stn sm'
                end
            end
          | _ => False
        end
      }.

      Definition defaultSymEval_word (P : ssignature wtypes (tvType pcIndex) (tvType stateIndex))
        : SymEval_word P.
      refine (
        {| sym_read_word          := fun _ _ _ => None
         ; sym_write_word         := fun _ _ _ _ => None
         ; sym_read_word_correct  := _
         ; sym_write_word_correct := _
        |}); 
      abstract (simpl; intros; congruence).
      Defined.

      (** * The full tactic *)
      Variable sfuncs : list (ssignature wtypes (tvType pcIndex) (tvType stateIndex)).

      Variable known : list nat. 
      Variable evals : hlist (fun n : nat => match nth_error sfuncs n with
                                               | None => Empty_set 
                                               | Some ss => SymEval_word ss
                                             end) known.

      Definition symeval_read_word (hyps : list (expr wtypes)) (p : expr wtypes) 
        (s : SHeap wtypes (tvType pcIndex) (tvType stateIndex))
        : option (expr wtypes) :=
        let hyps := hyps ++ pures s in
        let reader ss (seb : SymEval_word ss) args := 
          sym_read_word seb hyps args p
        in
        fold_known _ _ reader (impures s) evals.

      Theorem symeval_read_word_correct : forall hyps pe s ve, 
        symeval_read_word hyps pe s = Some ve ->
        forall funcs cs stn uvars vars m,
        AllProvable (funcsT funcs) uvars vars hyps ->
        (exists sm, 
             ST.satisfies cs (sexprD (funcsT funcs) sfuncs uvars vars (sheapD s)) stn sm
          /\ ST.HT.satisfies sm m) ->
        match 
          exprD_ptr_w (funcsT funcs) uvars vars pe ,
          exprD_word (funcsT funcs) uvars vars ve
          with
          | Some p , Some v => 
            mem_get_word B.addr B.mem B.footprint_w B.mem_get (IL.implode stn) p m = Some v
          | _ , _ => False
        end.
      Proof.
        unfold symeval_read_word. intros.
        eapply fold_known_correct in H.
        do 5 destruct H. destruct H1.
        intuition.

        generalize (sheapD_pures _ _ _ _ _ H); intros.

        eapply sheapD_pull_impure 
          with (sfuncs := sfuncs) (a := uvars) (c := vars0) (cs := cs)
            in H1.
        apply In_split in H3. destruct H3. destruct H3.
        subst. rewrite starred_In in H1.

        rewrite <- heq_star_assoc in H1. rewrite heq_star_comm in H1.
        rewrite H1 in H.
        simpl in H.
        eapply ST.satisfies_star in H. destruct H. destruct H. intuition.
        rewrite H2 in *.
 
        eapply sym_read_word_correct 
          with (uvars := uvars) (vars := vars0) (cs := cs) (stn := stn) (m := x2)
          in H6.
        2: eapply AllProvable_app; eauto.
        destruct (exprD_ptr_w (funcsT funcs) uvars vars0 pe); auto.
        destruct (exprD_word (funcsT funcs) uvars vars0 ve); auto.
        eapply ST.HT.satisfies_get_word. eauto.

        eapply ST.HT.split_smem_get_word; eauto.
        unfold tvarD.
        match goal with 
          | [ |- context [ applyD ?A ?B ?C ?D ?E ] ] =>
            destruct (applyD A B C D E)
        end; auto.
        eapply ST.satisfies_pure in H. PropXTac.propxFo.
      Qed.

      Definition symeval_write_word (hyps : list (expr wtypes)) (p v : expr wtypes) 
        (s : SHeap wtypes (tvType pcIndex) (tvType stateIndex))
        : option (SHeap wtypes (tvType pcIndex) (tvType stateIndex)) :=
        let hyps := hyps ++ pures s in
        let writer _ seb args := 
          sym_write_word seb hyps args p v
        in
        match fold_known_update _ _ writer (impures s) evals with
          | None => None
          | Some i' => Some {| impures := i' ; pures := pures s ; other := other s |}
        end.

      Theorem symeval_write_word_correct : forall funcs hyps pe ve s s',
        symeval_write_word hyps pe ve s = Some s' ->
        forall cs stn uvars vars m v,
        AllProvable (funcsT funcs) uvars vars hyps ->
        exprD_word (funcsT funcs) uvars vars ve = Some v ->
        (exists sm, 
             ST.satisfies cs (sexprD (funcsT funcs) sfuncs uvars vars (sheapD s)) stn sm
          /\ ST.HT.satisfies sm m) ->
        match exprD_ptr_w (funcsT funcs) uvars vars pe with
          | Some p =>
            exists sm, 
                 ST.satisfies cs (sexprD (funcsT funcs) sfuncs uvars vars (sheapD s')) stn sm
              /\ ST.HT.satisfies sm (mem_set_word B.addr B.mem B.footprint_w B.mem_set (IL.explode stn) p v m)
          | _ => False
        end.
      Proof.
        unfold symeval_write_word. intros.
        generalize dependent H.
        match goal with
          | [ |- context [ fold_known_update ?A ?B ?C ?D ?E ] ] =>
            case_eq (fold_known_update A B C D E); intros; try congruence
        end.
        eapply fold_known_update_correct in H.
        do 5 destruct H. destruct H2.
        intuition. inversion H3; clear H3; subst. 
        
        eapply fold_args_update_correct in H6.
        repeat match goal with
                 | [ H : exists x, _ |- _ ] => destruct H
               end. intuition; subst.
        generalize (sheapD_pures _ _ _ _ _ H4).
        rewrite sheapD_pull_impure in H4 by eauto.
        rewrite starred_In in H4.
        rewrite <- heq_star_assoc in H4. rewrite heq_star_comm in H4.
        
        simpl in *. rewrite H2 in *.
        intros.

        eapply ST.satisfies_star in H4. do 2 destruct H4. intuition.

        eapply sym_write_word_correct with (stn := stn) (cs := cs) (m := x2)
          in H3; eauto.

        2: apply AllProvable_app; eauto.

        destruct (exprD_ptr_w (funcsT funcs) uvars vars0 pe); eauto.
        unfold tvarD in H3.

        generalize dependent H3.
        case_eq (ST.HT.smem_set_word (IL.explode stn) a v x2); [ intros |
          match goal with 
            | [ |- context [ applyD ?A ?B ?C ?D ?E ] ] =>
              destruct (applyD A B C D E); intros; exfalso; assumption
          end ].
        
        exists (ST.HT.join s0 x3).
        rewrite sheapD_pull_impure by eapply FM.find_add.
        simpl. rewrite FM.remove_add.
        rewrite starred_In.
        simpl. rewrite H2. generalize dependent H8. 
        rewrite <- ST.heq_star_assoc. rewrite ST.heq_star_comm. 
        match goal with
          | [ |- context [ applyD ?A ?B ?C ?D ?E ] ] =>
            destruct (applyD A B C D E); try solve [ intros; intuition ]
        end. 
        generalize dependent H9.
        match goal with
          | [ |- ST.satisfies _ ?Y _ _ -> _ -> ST.satisfies _ (ST.star _ ?X) _ _ /\ _ ] => 
            change X with Y; generalize dependent Y
        end.
        intros.

        generalize (ST.HT.split_set_word _ _ (proj1 H7) _ _ _ _ H3).
        split.
        eapply ST.satisfies_star. do 2 eexists. split; eauto. eapply ST.HT.disjoint_split_join; eauto. tauto.

        eapply ST.HT.satisfies_set_word. eauto. destruct H7; subst. tauto.

        unfold tvarD. generalize dependent H4.
        match goal with
          | [ |- context [ applyD ?A ?B ?C ?D ?E ] ] =>
            destruct (applyD A B C D E); try solve [ intros; intuition ]
        end. intros.
        eapply ST.satisfies_pure in H4. PropXTac.propxFo.
      Qed.

    End WordAccess.
  End typed.
End Evaluator.
*)
(*
Require Import SepIL SepTac.

Module BedrockEvaluator_ptsto.
  Module E := EvaluatorPlugin (BedrockHeap) (ST).

  

Module BedrockEvaluator.
  Module E := EvaluatorPlugin (BedrockHeap) (ST).
  Module Import SEP := E.SEP.

  Definition pcIndex : nat := 0.
  Definition stateIndex : nat := 1.
  
  Definition addr_type :=
    {| Impl := W
     ; Eq := seq_dec 
     |}.

  Definition word_type :=
    {| Impl := W
     ; Eq := seq_dec 
     |}.

  Definition wtypes := bedrock_types ++ addr_type :: word_type :: nil.

  Definition ptsto32_ssig : ssignature wtypes (tvType pcIndex) (tvType stateIndex).
  refine (
  {| SepExpr.SDomain := tvType 2 :: tvType 3 :: nil
   ; SepExpr.SDenotation := _
   |}).
  refine (ptsto32 _).
  Defined.

  Definition wordIndex := 3.
  Definition ptrIndex := 2.
  Lemma wordIndex_ptrIndex : wordIndex <> ptrIndex.
    intro. inversion H.
  Qed.

  Variable funcs : functions wtypes.

  (** TODO: maybe this should be like unification? 
   ** - in that case the substitution is an effect and needs to be
   **   threaded through the computation (monadically?)
   **)
  Variable expr_equal : forall (hyps : list (expr wtypes)) (tv : tvar) (a b : expr wtypes), bool.

  Definition sym_read_word_ptsto32 (hyps args : list (expr wtypes)) (p : expr wtypes) 
    : option (expr wtypes) :=
    match args with
      | p' :: v' :: nil => 
        if expr_equal hyps (tvType ptrIndex) p p' then Some v' else None
      | _ => None
    end.
  Definition sym_write_word_ptsto32 (hyps args : list (expr wtypes)) (p v : expr wtypes)
    : option (list (expr wtypes)) :=
    match args with
      | p' :: v' :: nil =>
        if expr_equal hyps (tvType ptrIndex) p p' then Some (p :: v :: nil) else None
      | _ => None
    end.

  Variable expr_equal_correct : forall T hyps a b,
    expr_equal hyps T a b = true ->
    forall uvars vars,
    AllProvable funcs uvars vars hyps ->
    exprD funcs uvars vars a T = exprD funcs uvars vars b T.

  Ltac expose :=
    repeat (unfold wordIndex, ptrIndex in *; 
            match goal with 
              | [ H : match applyD _ _ ?A _ _ with
                        | Some _ => _ 
                        | None => False 
                      end |- _ ] =>
              destruct A; simpl in H; try (exfalso; assumption)
              | [ H : match 
                        match exprD ?A ?B ?C ?D ?E with
                          | None => _
                          | Some _ => _
                        end _ _ 
                        with 
                        | None => _
                        | Some _ => _
                      end |- _ ] =>
              generalize dependent H; case_eq (exprD A B C D E); simpl; intros; 
                try (exfalso; assumption)
              | [ H : context [ match expr_equal ?A ?B ?C ?D with
                                  | true => _
                                  | false => _
                                end ] |- _ ] =>
                generalize dependent H; case_eq (expr_equal A B C D); intros; 
                  try (exfalso; congruence)
              | [ H : expr_equal ?A ?B ?C ?D = true 
                , H' : AllProvable _ _ _ ?A |- _ ] =>
                generalize (@expr_equal_correct _ _ _ _ H _ _ H'); clear H; intros
              | [ H : Some _ = Some _ |- _ ] =>
                inversion H; clear H; subst
              | [ H : exprD _ _ _ _ _ = Some _ |- _ ] =>
                rewrite H in *
            end; simpl in * ).

  Lemma sym_read_word_ptsto32_correct : forall args uvars vars cs hyps pe ve m stn,
    sym_read_word_ptsto32 hyps args pe = Some ve ->
    AllProvable funcs uvars vars hyps ->
    match 
      applyD (exprD funcs uvars vars) (SDomain ptsto32_ssig) args _ (SDenotation ptsto32_ssig)
      with
      | None => False
      | Some p => ST.satisfies cs p stn m
    end ->
    match exprD funcs uvars vars pe (tvType ptrIndex) , exprD funcs uvars vars ve (tvType wordIndex) with
      | Some p , Some v =>
        ST.HT.smem_get_word (IL.implode stn) p m = Some v
      | _ , _ => False
    end.
  Proof.
    simpl; intros; expose.
    unfold ST.satisfies in H3. PropXTac.propxFo.
  Qed.

  Lemma sym_write_word_ptsto32_correct : forall args uvars vars cs hyps pe ve v m stn args',
    sym_write_word_ptsto32 hyps args pe ve = Some args' ->
    AllProvable funcs uvars vars hyps ->
    exprD funcs uvars vars ve (tvType wordIndex) = Some v ->
    match
      applyD (@exprD _ funcs uvars vars) (SDomain ptsto32_ssig) args _ (SDenotation ptsto32_ssig)
      with
      | None => False
      | Some p => ST.satisfies cs p stn m
    end ->
    match exprD funcs uvars vars pe (tvType ptrIndex)with
      | Some p =>
        match 
          applyD (@exprD _ funcs uvars vars) (SDomain ptsto32_ssig) args' _ (SDenotation ptsto32_ssig)
          with
          | None => False
          | Some pr => 
            match ST.HT.smem_set_word (IL.explode stn) p v m with
              | None => False
              | Some sm' => ST.satisfies cs pr stn sm'
            end
        end
      | _ => False
    end.
  Proof.
    simpl; intros; expose.

    unfold ST.satisfies in *. PropXTac.propxFo. 
    case_eq (smem_set_word (IL.explode stn) t v m).
    intros. unfold ptsto32. PropXTac.propxFo.
    eapply smem_set_get_word_eq; eauto.
    eapply IL.implode_explode.
    eapply smem_set_get_valid_word; eauto.
  Qed.

  Definition SymEval_ptsto32 : E.SymEval_word wtypes wordIndex_ptrIndex funcs ptsto32_ssig :=
    {| E.sym_read_word := sym_read_word_ptsto32 : list (expr (E.wtypes wtypes ptrIndex wordIndex)) -> _
     ; E.sym_write_word := sym_write_word_ptsto32 
     ; E.sym_read_word_correct := sym_read_word_ptsto32_correct
     ; E.sym_write_word_correct := sym_write_word_ptsto32_correct
     |}.

End BedrockEvaluator.
*)


(** * These are generic search functions *)
(*
Section search_read_write.
  Variable A : Type.
  Variable B : A -> Type.
  Variable types : list type.
  Variable sfuncs : list A.

  Variable T : Type.
  Variable F : forall s, B s -> list (expr types) -> option T.
  Variable F_upd : forall s, B s -> list (expr types) -> option (list (expr types)).

  Section arg.
    Variable ss : A.
    Variable se : B ss.
    
    Fixpoint fold_args (es : list (list (expr types))) : option T :=
      match es with 
        | nil => None
        | a :: b => 
          match F se a with
            | None => fold_args b
            | Some r => Some r
          end
      end.
    
    Theorem fold_args_correct : forall es v,
      fold_args es = Some v ->
      exists k, In k es /\ F se k = Some v.
    Proof.
      clear. induction es.
      simpl; congruence.
      simpl. case_eq (F se a); intros.
      inversion H0. subst. eauto.
      eapply IHes in H0. destruct H0.
      exists x. tauto.
    Qed.

    Fixpoint fold_args_update (es : list (list (expr types))) : option (list (list (expr types))) :=
      match es with 
        | nil => None
        | a :: b => 
          match F_upd se a with
            | None => match fold_args_update b with
                        | None => None
                        | Some b => Some (a :: b)
                      end
            | Some r => Some (r :: b)
          end
      end.
    
    Theorem fold_args_update_correct : forall es es',
      fold_args_update es = Some es' ->
      exists pre, exists post, exists k, exists k',
        es = pre ++ k :: post /\
        F_upd se k = Some k' /\
        es' = pre ++ k' :: post.
    Proof.
      clear. induction es.
      simpl; congruence.
      simpl. case_eq (F_upd se a); intros.
      inversion H0. subst. do 4 eexists; intuition eauto.
      instantiate (2 := nil). reflexivity. reflexivity.

      generalize dependent H0.
      case_eq (fold_args_update es); intros.
      inversion H1; subst. eapply IHes in H0.
      do 4 destruct H0. exists (a :: x). exists x0.
      eexists; eexists; intuition; subst; eauto. reflexivity.

      congruence.
    Qed.
  End arg.

  Variable impures : FM.t (list (list (expr types))).

  Fixpoint fold_known (k : list nat) :
    hlist (fun n : nat => match nth_error sfuncs n return Type with
                            | None => Empty_set 
                            | Some ss => B ss
                          end) k
    -> option T :=
    match k as k 
      return hlist (fun n : nat => match nth_error sfuncs n return Type with
                                     | None => Empty_set 
                                     | Some ss => B ss
                                   end) k
      -> option T
      with
      | nil => fun _ => None
      | a :: b => fun ss =>
        match FM.find a impures with
          | None => fold_known (hlist_tl ss)
          | Some argss =>
            match nth_error sfuncs a as ss
              return match ss return Type with
                       | None => Empty_set 
                       | Some ss => B ss
                     end -> option T
              with
              | Some _ => fun se =>
                match fold_args se argss with
                  | None => fold_known (hlist_tl ss)
                  | Some r => Some r
                end
              | None => fun err => match err with end
            end (hlist_hd ss)
        end
    end.
  
  Theorem fold_known_correct : forall k
    (h : hlist (fun n : nat => match nth_error sfuncs n return Type with
                                 | None => Empty_set 
                                 | Some ss => B ss
                               end) k) v,
    @fold_known k h = Some v ->
    exists n, exists ss,
      exists se :  B ss, exists ls, exists args, 
        nth_error sfuncs n = Some ss 
        /\ FM.find n impures = Some ls 
        /\ In args ls 
        /\ F se args = Some v.
  Proof.
    clear. induction k; simpl.
    congruence.
    intros h v. specialize (IHk (hlist_tl h) v).
    rewrite (hlist_eta _ h) in *.
    generalize dependent (hlist_hd h). simpl.
    case_eq (FM.find a impures); intros; eauto 10.

    assert (exists k, nth_error sfuncs a = Some k).
    generalize y. clear.
    destruct (nth_error sfuncs a); [ eauto | destruct 1 ]. 
    destruct H1.
    generalize dependent y.
    rewrite H1. intro.
    case_eq (fold_args y l); intros; eauto 10.
    inversion H2; subst.
    eapply fold_args_correct in H0. destruct H0; eauto 10.
  Qed.

  Fixpoint fold_known_update (k : list nat) :
    hlist (fun n : nat => match nth_error sfuncs n with
                            | None => Empty_set 
                            | Some ss => B ss
                          end) k
    -> option (FM.t (list (list (expr types)))) :=
    match k as k 
      return hlist (fun n : nat => match nth_error sfuncs n return Type with
                                     | None => Empty_set 
                                     | Some ss => B ss
                                   end) k
      -> option (FM.t (list (list (expr types))))
      with
      | nil => fun _ => None
      | a :: b => fun ss =>
        match FM.find a impures with
          | None => fold_known_update (hlist_tl ss)
          | Some argss =>
            match nth_error sfuncs a as ss
              return match ss return Type with
                       | None => Empty_set 
                       | Some ss => B ss
                     end -> option (FM.t (list (list (expr types))))
              with
              | Some _ => fun se =>
                match fold_args_update se argss with
                  | None => fold_known_update (hlist_tl ss)
                  | Some r => Some (FM.add a r impures) (* this is a replace *)
                end
              | None => fun err => match err with end
            end (hlist_hd ss)
        end
    end.
  
  Theorem fold_known_update_correct : forall k
    (h : hlist (fun n : nat => match nth_error sfuncs n return Type with
                                 | None => Empty_set 
                                 | Some ss => B ss
                               end) k) i',
    @fold_known_update k h = Some i' ->
    exists n, exists ss,
      exists se : B ss, exists ls, exists ls',
        nth_error sfuncs n = Some ss 
        /\ FM.find n impures = Some ls 
        /\ fold_args_update se ls = Some ls'
        /\ i' = FM.add n ls' impures.
  Proof.
    clear. induction k; simpl.
    congruence.
    intros h v. specialize (IHk (hlist_tl h) v).
    rewrite (hlist_eta _ h) in *.
    generalize dependent (hlist_hd h). simpl.
    case_eq (FM.find a impures); intros; eauto 10.

    assert (exists k, nth_error sfuncs a = Some k).
    generalize y. clear.
    destruct (nth_error sfuncs a); [ eauto | destruct 1 ]. 
    destruct H1.
    generalize dependent y.
    rewrite H1. intro.
    case_eq (fold_args_update y l); intros; eauto 10.
    inversion H2; subst.
    eauto 10.
  Qed.

End search_read_write.
*)

(*
(** This depends on [IL.settings] 
 ** - this suggests that a better abstraction is to put the relevant settings into the
 **   memory model...
 **)
Module Type EvaluatorPluginType (B : Heap) (ST : SepTheoryX.SepTheoryXType B).
  Module SEP := SepExpr B ST.

  Parameter MemEvalPred : list type -> Type.

  Parameter smem_read : forall (types : list type),
    @MemEvalPred types ->
    forall (P : ProverT types),
      Facts P -> exprs types -> expr types -> option (expr types).

  Parameter smem_write : forall (types : list type),
    @MemEvalPred types ->
    forall (P : ProverT types), 
      Facts P -> exprs types -> expr types -> expr types -> option (exprs types).

  Parameter Build_MemEvalPred : forall (types : list type)
    (sym_read : forall (P : ProverT types) (facts : Facts P) (args : list (expr types)) (p : expr types),
      option (expr types))
    (sym_write : forall (P : ProverT types) (facts : Facts P) (args : list (expr types)) (p v : expr types),
      option (exprs types)),
    @MemEvalPred types.

  Parameter proj_sym_read : forall ts a b,
    smem_read (types := ts) (Build_MemEvalPred a b) = a.

  Parameter proj_sym_write : forall ts a b,
    smem_write (types := ts) (Build_MemEvalPred a b) = b.

  Parameter MemEvalPred_correct : forall
    (types : list type) 
    (me : MemEvalPred types)
 
    (tvState : tvar)
    (tvPc : tvar)
    (tvPtr : tvar)
    (tvVal : tvar)
      
    (smem_get_value : IL.settings -> tvarD types tvPtr -> ST.HT.smem -> 
      option (tvarD types tvVal))
    (smem_set_value : IL.settings -> tvarD types tvPtr -> tvarD types tvVal
      -> ST.HT.smem -> option ST.HT.smem)

    (Predicate : SEP.ssignature types tvPc tvState),   
    functions types -> Type.

  Parameter sym_read_correct : forall
    (types : list type)
    (me : MemEvalPred types)
    (tvState : tvar)
    (tvPc : tvar)
    (tvPtr : tvar)
    (tvVal : tvar)
      
    (smem_get_value : IL.settings -> tvarD types tvPtr -> ST.HT.smem -> 
      option (tvarD types tvVal))
    (smem_set_value : IL.settings -> tvarD types tvPtr -> tvarD types tvVal
      -> ST.HT.smem -> option ST.HT.smem)
    
    (Predicate : SEP.ssignature types tvPc tvState)
    (funcs : functions types),
    @MemEvalPred_correct types me tvState tvPc tvPtr tvVal smem_get_value smem_set_value Predicate funcs ->
    forall P (PE : ProverT_correct P funcs),
      forall args uvars vars cs facts pe p ve m stn,
      smem_read me P facts args pe = Some ve ->
      Valid PE uvars vars facts ->
      exprD funcs uvars vars pe tvPtr = Some p ->
      match 
        applyD (exprD funcs uvars vars) (SDomain Predicate) args _ (SDenotation Predicate)
        with
        | None => False
        | Some p => ST.satisfies cs p stn m
      end ->
      match exprD funcs uvars vars ve tvVal with
        | Some v =>
          smem_get_value stn p m = Some v
        | _ => False
      end.
  
  Parameter sym_write_correct : forall
    (types : list type)
    (me : MemEvalPred types)
    (tvState : tvar)
    (tvPc : tvar)
    (tvPtr : tvar)
    (tvVal : tvar)
    
    (smem_get_value : IL.settings -> tvarD types tvPtr -> ST.HT.smem -> 
      option (tvarD types tvVal))
    (smem_set_value : IL.settings -> tvarD types tvPtr -> tvarD types tvVal
      -> ST.HT.smem -> option ST.HT.smem)
    
    (Predicate : SEP.ssignature types tvPc tvState)
    (funcs : functions types),
    @MemEvalPred_correct types me tvState tvPc tvPtr tvVal smem_get_value smem_set_value Predicate funcs ->
    forall P (PE : ProverT_correct P funcs),
      forall args uvars vars cs facts pe p ve v m stn args',
      smem_write me P facts args pe ve = Some args' ->
      Valid PE uvars vars facts ->
      exprD funcs uvars vars pe tvPtr = Some p ->
      exprD funcs uvars vars ve tvVal = Some v ->
      match
        applyD (@exprD _ funcs uvars vars) (SDomain Predicate) args _ (SDenotation Predicate)
        with
        | None => False
        | Some p => ST.satisfies cs p stn m
      end ->
      match 
        applyD (@exprD _ funcs uvars vars) (SDomain Predicate) args' _ (SDenotation Predicate)
        with
        | None => False
        | Some pr => 
          match smem_set_value stn p v m with
            | None => False
            | Some sm' => ST.satisfies cs pr stn sm'
          end
      end.

  Parameter Build_MemEvalPred_correct : forall
    (types : list type)
    (me : MemEvalPred types)
    (tvState : tvar)
    (tvPc : tvar)
    (tvPtr : tvar)
    (tvVal : tvar)
    
    (smem_get_value : IL.settings -> tvarD types tvPtr -> ST.HT.smem -> 
      option (tvarD types tvVal))
    (smem_set_value : IL.settings -> tvarD types tvPtr -> tvarD types tvVal
      -> ST.HT.smem -> option ST.HT.smem)
    
    (Predicate : SEP.ssignature types tvPc tvState)
    (funcs : functions types)
        
    (sym_read_correct : forall P (PE : ProverT_correct P funcs),
      forall args uvars vars cs facts pe p ve m stn,
      smem_read me P facts args pe = Some ve ->
      Valid PE uvars vars facts ->
      exprD funcs uvars vars pe tvPtr = Some p ->
      match 
        applyD (exprD funcs uvars vars) (SDomain Predicate) args _ (SDenotation Predicate)
        with
        | None => False
        | Some p => ST.satisfies cs p stn m
      end ->
      match exprD funcs uvars vars ve tvVal with
        | Some v =>
          smem_get_value stn p m = Some v
        | _ => False
      end)
    (sym_write_correct : forall P (PE : ProverT_correct P funcs),
      forall args uvars vars cs facts pe p ve v m stn args',
      smem_write me P facts args pe ve = Some args' ->
      Valid PE uvars vars facts ->
      exprD funcs uvars vars pe tvPtr = Some p ->
      exprD funcs uvars vars ve tvVal = Some v ->
      match
        applyD (@exprD _ funcs uvars vars) (SDomain Predicate) args _ (SDenotation Predicate)
        with
        | None => False
        | Some p => ST.satisfies cs p stn m
      end ->
      match 
        applyD (@exprD _ funcs uvars vars) (SDomain Predicate) args' _ (SDenotation Predicate)
        with
        | None => False
        | Some pr => 
          match smem_set_value stn p v m with
            | None => False
            | Some sm' => ST.satisfies cs pr stn sm'
          end
      end),
    @MemEvalPred_correct types me tvState tvPc tvPtr tvVal smem_get_value smem_set_value Predicate funcs.

End EvaluatorPluginType.
*)