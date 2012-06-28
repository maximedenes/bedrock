Require Import Ascii Bool String List.
Require Import Word Memory Expr SepExpr SymEval SepIL Env Prover SymEval IL SymIL.
Require Import sep.Array.

Set Implicit Arguments.

Definition vals := string -> W.

Definition toArray (ns : list string) (vs : vals) : list W := map vs ns.

Definition locals (ns : list string) (vs : vals) (p : W) : HProp :=
  ([| NoDup ns |] * array (toArray ns vs) p)%Sep.

Definition ascii_eq (a1 a2 : ascii) : bool :=
  let (b1, c1, d1, e1, f1, g1, h1, i1) := a1 in
  let (b2, c2, d2, e2, f2, g2, h2, i2) := a2 in
    eqb b1 b2 && eqb c1 c2 && eqb d1 d2 && eqb e1 e2
    && eqb f1 f2 && eqb g1 g2 && eqb h1 h2 && eqb i1 i2.

Lemma ascii_eq_true : forall a,
  ascii_eq a a = true.
  destruct a; simpl; intuition.
  repeat rewrite eqb_reflx; reflexivity.
Qed.

Lemma ascii_eq_false : forall a b,
  a <> b -> ascii_eq a b = false.
  destruct b, a; simpl; intuition.
  match goal with
    | [ |- ?E = _ ] => case_eq E
  end; intuition.
    repeat match goal with
             | [ H : _ |- _ ] => apply andb_prop in H; destruct H
             | [ H : _ |- _ ] => apply eqb_prop in H
           end; congruence.
Qed.

Fixpoint string_eq (s1 s2 : string) : bool :=
  match s1, s2 with
    | EmptyString, EmptyString => true
    | String a1 s1', String a2 s2' => ascii_eq a1 a2 && string_eq s1' s2'
    | _, _ => false
  end.

Theorem string_eq_true : forall s,
  string_eq s s = true.
  induction s; simpl; intuition; rewrite ascii_eq_true; assumption.
Qed.

Theorem string_eq_false : forall s1 s2,
  s1 <> s2 -> string_eq s1 s2 = false.
  induction s1; destruct s2; simpl; intuition.
  match goal with
    | [ |- ?E = _ ] => case_eq E
  end; intuition.
  repeat match goal with
           | [ H : _ |- _ ] => apply andb_prop in H; destruct H
           | [ H : _ |- _ ] => apply eqb_prop in H
         end.
  destruct (ascii_dec a a0); subst.
  destruct (string_dec s1 s2); subst.
  tauto.
  apply IHs1 in n; congruence.
  apply ascii_eq_false in n; congruence.
Qed.

Theorem string_eq_correct : forall s1 s2,
  string_eq s1 s2 = true -> s1 = s2.
  intros; destruct (string_dec s1 s2); subst; auto.
  apply string_eq_false in n; congruence.
Qed.

Definition sel (vs : vals) (nm : string) : W := vs nm.
Definition upd (vs : vals) (nm : string) (v : W) : vals := fun nm' =>
  if string_eq nm' nm then v else vs nm'.

Definition bedrock_type_string : type :=
  {| Expr.Impl := string
   ; Expr.Eqb := string_eq
   ; Expr.Eqb_correct := string_eq_correct |}.

Definition bedrock_type_listString : type :=
  {| Expr.Impl := list string
   ; Expr.Eqb := (fun _ _ => false)
   ; Expr.Eqb_correct := @ILEnv.all_false_compare _ |}.

Definition bedrock_type_vals : type :=
  {| Expr.Impl := vals
   ; Expr.Eqb := (fun _ _ => false)
   ; Expr.Eqb_correct := @ILEnv.all_false_compare _ |}.

Definition types_r : Env.Repr Expr.type :=
  Eval cbv beta iota zeta delta [ Env.listOptToRepr ] in 
    let lst := 
      Some ILEnv.bedrock_type_W ::
      Some ILEnv.bedrock_type_setting_X_state ::
      None ::
      None ::
      None ::
      Some ILEnv.bedrock_type_nat ::
      None ::
      Some bedrock_type_string ::
      Some bedrock_type_listString ::
      Some bedrock_type_vals ::
      nil
    in Env.listOptToRepr lst EmptySet_type.

Local Notation "'pcT'" := (tvType 0).
Local Notation "'stT'" := (tvType 1).
Local Notation "'wordT'" := (tvType 0).
Local Notation "'natT'" := (tvType 5).
Local Notation "'stringT'" := (tvType 7).
Local Notation "'listStringT'" := (tvType 8).
Local Notation "'valsT'" := (tvType 9).

Local Notation "'wplusF'" := 0.
Local Notation "'wmultF'" := 2.
Local Notation "'natToWF'" := 6.
Local Notation "'nilF'" := 10.
Local Notation "'consF'" := 11.
Local Notation "'selF'" := 12.
Local Notation "'updF'" := 13.

Section parametric.
  Variable types' : list type.
  Definition types := repr types_r types'.
  Variable Prover : ProverT types.

  Definition nil_r : signature types.
    refine {| Domain := nil; Range := listStringT |}.
    exact (@nil _).
  Defined.

  Definition cons_r : signature types.
    refine {| Domain := stringT :: listStringT :: nil; Range := listStringT |}.
    exact (@cons _).
  Defined.

  Definition sel_r : signature types.
    refine {| Domain := valsT :: stringT :: nil; Range := wordT |}.
    exact sel.
  Defined.

  Definition upd_r : signature types.
    refine {| Domain := valsT :: stringT :: wordT :: nil; Range := valsT |}.
    exact upd.
  Defined.

  Definition funcs_r : Env.Repr (signature types) :=
    Eval cbv beta iota zeta delta [ Env.listOptToRepr ] in 
      let lst := 
        Some (ILEnv.wplus_r types) ::
        None ::
        Some (ILEnv.wmult_r types) ::
        None ::
        None ::
        None ::
        Some (ILEnv.natToW_r types) ::
        None ::
        None ::
        None ::
        Some nil_r ::
        Some cons_r ::
        Some sel_r ::
        Some upd_r ::
        nil
      in Env.listOptToRepr lst (Default_signature _).

  Definition deref (e : expr types) : option (expr types * nat) :=
    match e with
      | Func wplusF (base :: offset :: nil) =>
        match offset with
          | Func natToWF (Const t k :: nil) =>
            match t return tvarD types t -> _ with
              | natT => fun k => match div4 k with
                                   | None => None
                                   | Some k' => Some (base, k')
                                 end
              | _ => fun _ => None
            end k
          | _ => None
        end
      | _ => None
    end.

  Fixpoint listIn (e : expr types) : option (list string) :=
    match e with
      | Func nilF nil => Some nil
      | Func consF (Const tp s :: t :: nil) =>
        match tp return tvarD types tp -> option (list string) with
          | stringT => fun s => match listIn t with
                                  | None => None
                                  | Some t => Some (s :: t)
                                end
          | _ => fun _ => None
        end s
      | _ => None
    end.

  Fixpoint sym_sel (vs : expr types) (nm : string) : expr types :=
    match vs with
      | Func updF (vs' :: Const tp nm' :: v :: nil) =>
        match tp return tvarD types tp -> expr types with
          | stringT => fun nm' =>
            if string_eq nm' nm
              then v
              else sym_sel vs' nm
          | _ => fun _ => Func selF (vs :: Const (types := types) (t := stringT) nm :: nil)
        end nm'
      | _ => Func selF (vs :: Const (types := types) (t := stringT) nm :: nil)
    end.

  Definition sym_read (summ : Prover.(Facts)) (args : list (expr types)) (p : expr types)
    : option (expr types) :=
    match args with
      | ns :: vs :: p' :: nil =>
        match deref p, listIn ns with
          | Some (base, offset), Some ns =>
            if Prover.(Prove) summ (Equal wordT p' base)
              then match nth_error ns offset with
                     | None => None
                     | Some nm => Some (sym_sel vs nm)
                   end
              else None
          | _, _ => None
        end
      | _ => None
    end.

  Definition sym_write (summ : Prover.(Facts)) (args : list (expr types)) (p v : expr types)
    : option (list (expr types)) :=
    match args with
      | ns :: vs :: p' :: nil =>
        match deref p, listIn ns with
          | Some (base, offset), Some ns' =>
            if Prover.(Prove) summ (Equal wordT p' base)
              then match nth_error ns' offset with
                     | None => None
                     | Some nm => Some (ns
                       :: Func updF (vs :: Const (types := types) (t := stringT) nm :: v :: nil)
                       :: p' :: nil)
                   end
              else None
          | _, _ => None
        end
      | _ => None
    end.
End parametric.

Definition MemEval types' : @MEVAL.PredEval.MemEvalPred (types types').
  eapply MEVAL.PredEval.Build_MemEvalPred.
  eapply sym_read.
  eapply sym_write.
Defined.

Section correctness.
  Variable types' : list type.
  Definition types0 := types types'.

  Definition ssig : SEP.predicate types0 pcT stT.
    refine (SEP.PSig _ _ _ (listStringT :: valsT :: wordT :: nil) _).
    exact locals.
  Defined.

  Definition ssig_r : Env.Repr (SEP.predicate types0 pcT stT) :=
    Eval cbv beta iota zeta delta [ Env.listOptToRepr ] in 
      let lst := 
        None :: None :: Some ssig :: nil
      in Env.listOptToRepr lst (SEP.Default_predicate _ _ _).

  Variable funcs' : functions types0.
  Definition funcs := Env.repr (funcs_r _) funcs'.

  Variable Prover : ProverT types0.
  Variable Prover_correct : ProverT_correct Prover funcs.

  Ltac deconstruct := repeat deconstruct' idtac.

  Lemma deref_correct : forall uvars vars e w base offset,
    exprD funcs uvars vars e wordT = Some w
    -> deref e = Some (base, offset)
    -> exists wb,
      exprD funcs uvars vars base wordT = Some wb
      /\ w = wb ^+ $(offset * 4).
    destruct e; simpl deref; intuition; try discriminate.
    deconstruct.
    simpl exprD in *.
    match goal with
      | [ _ : context[div4 ?N] |- _ ] => specialize (div4_correct N); destruct (div4 N)
    end; try discriminate.
    deconstruct.
    specialize (H2 _ (refl_equal _)); subst.
    repeat (esplit || eassumption).
    repeat f_equal.
    unfold natToW.
    f_equal.
    omega.
  Qed.

  Lemma listIn_correct : forall uvars vars e ns, listIn e = Some ns
    -> exprD funcs uvars vars e listStringT = Some ns.
    induction e; simpl; intuition; try discriminate.
    repeat match type of H with
             | Forall _ (_ :: _ :: nil) => inversion H; clear H; subst
             | _ => deconstruct' idtac
           end.
    inversion H4; clear H4; subst.
    clear H5.
    deconstruct.
    simpl in *.
    erewrite H2; reflexivity.
  Qed.

  Lemma sym_sel_correct : forall uvars vars nm (vs : expr types0) vsv,
    exprD funcs uvars vars vs valsT = Some vsv
    -> exprD funcs uvars vars (sym_sel vs nm) wordT = Some (sel vsv nm).
    induction vs; simpl; intros; try discriminate.

    destruct (equiv_dec t valsT); congruence.

    rewrite H; reflexivity.

    rewrite H; reflexivity.

    Ltac t := simpl in *; try discriminate; try (deconstruct;
      match goal with
        | [ _ : Range (match ?E with nil => _ | _ => _ end) === _ |- _ ] =>
          destruct E; simpl in *; try discriminate;
            match goal with
              | [ H : Range ?X === _ |- _ ] => destruct X; simpl in *; hnf in H; subst
            end;
            match goal with
              | [ H : _ = _ |- _ ] => rewrite H; reflexivity
            end
      end).
    simpl in *.
    do 14 (destruct f; t).

    Focus 2.
    deconstruct.
    destruct s; simpl in *.
    hnf in e; subst.
    rewrite H0; reflexivity.

    destruct l; simpl in *; try discriminate.
    destruct l; simpl in *; try discriminate.
    rewrite H0; reflexivity.
    destruct e0; simpl in *; try (rewrite H0; reflexivity).
    do 2 (destruct l; simpl in *; try (rewrite H0; reflexivity)).
    destruct t; simpl in *; try (rewrite H0; reflexivity).
    do 8 (destruct n; simpl in *; try (rewrite H0; reflexivity)).
    inversion H; clear H; subst.
    inversion H4; clear H4; subst.
    inversion H5; clear H5; subst.
    clear H6.
    destruct (string_dec t0 nm); subst.
    rewrite string_eq_true.
    deconstruct.
    unfold sel, upd.
    rewrite string_eq_true; reflexivity.

    rewrite string_eq_false by assumption.
    deconstruct.
    erewrite H3 by reflexivity.
    f_equal; unfold sel, upd.
    rewrite string_eq_false; auto.
  Qed.

  Theorem sym_read_correct : forall args uvars vars cs summ pe p ve m stn,
    sym_read Prover summ args pe = Some ve ->
    Valid Prover_correct uvars vars summ ->
    exprD funcs uvars vars pe wordT = Some p ->
    match 
      applyD (exprD funcs uvars vars) (SEP.SDomain ssig) args _ (SEP.SDenotation ssig)
      with
      | None => False
      | Some p => ST.satisfies cs p stn m
    end ->
    match exprD funcs uvars vars ve wordT with
      | Some v =>
        ST.HT.smem_get_word (IL.implode stn) p m = Some v
      | _ => False
    end.
  Proof.
    simpl; intuition.
    do 4 (destruct args; simpl in *; intuition; try discriminate).
    generalize (deref_correct uvars vars pe); destr idtac (deref pe); intro Hderef.
    destruct p0.
    generalize (listIn_correct uvars vars e); destr idtac (listIn e); intro HlistIn.
    specialize (HlistIn _ (refl_equal _)).
    rewrite HlistIn in *.

    repeat match goal with
             | [ H : Valid _ _ _ _, _ : context[Prove Prover ?summ ?goal] |- _ ] =>
               match goal with
                 | [ _ : context[ValidProp _ _ _ goal] |- _ ] => fail 1
                 | _ => specialize (Prove_correct Prover_correct summ H (goal := goal)); intro
               end
           end; unfold ValidProp in *.
    unfold types0 in *.
    match type of H with
      | (if ?E then _ else _) = _ => destruct E
    end; intuition; try discriminate.
    simpl in H4.
    case_eq (nth_error l n); [ intros ? Heq | intro Heq ]; rewrite Heq in *; try discriminate.
    injection H; clear H; intros; subst.
    generalize (sym_sel_correct uvars vars s e0); intro Hsym_sel.
    destruct (exprD funcs uvars vars e0 valsT); try tauto.
    specialize (Hsym_sel _ (refl_equal _)).
    rewrite Hsym_sel.
    specialize (Hderef _ _ _ H1 (refl_equal _)).
    destruct Hderef as [ ? [ ] ].
    subst.
    case_eq (exprD funcs uvars vars e1 wordT); [ intros ? Heq' | intro Heq' ]; rewrite Heq' in *; try tauto.
    rewrite H in H4.
    specialize (H4 (ex_intro _ _ (refl_equal _))).
    hnf in H4; simpl in H4.
    rewrite Heq' in H4.
    rewrite H in H4.
    subst.
    Require Import PropXTac.
    apply simplify_fwd in H2.
    destruct H2 as [ ? [ ? [ ? [ ] ] ] ].
    simpl simplify in *.
    destruct H3.
    apply simplify_bwd in H4.
    generalize (split_semp _ _ _ H2 H5); intro; subst.
    specialize (smem_read_correct' _ _ _ _ (i := natToW n) H4); intro Hsmem.
    rewrite natToW_times4.
    rewrite wmult_comm.
    unfold natToW in *.
    rewrite Hsmem.
    f_equal.

    Lemma array_selN : forall nm vs ns n,
      nth_error ns n = Some nm
      -> Array.selN (toArray ns vs) n = sel vs nm.
      induction ns; destruct n; simpl; intuition; try discriminate.
      injection H; clear H; intros; subst; reflexivity.
    Qed.

    Require Import NArith Nomega.

    unfold Array.sel.
    apply array_selN.
    apply array_bound in H4.
    rewrite wordToNat_natToWord_idempotent; auto.
    apply nth_error_Some_length in Heq.

    Lemma length_toArray : forall ns vs,
      length (toArray ns vs) = length ns.
      induction ns; simpl; intuition.
    Qed.

    rewrite length_toArray in *.
    apply Nlt_in.
    rewrite Nat2N.id.
    rewrite Npow2_nat.
    omega.

    rewrite length_toArray.
    apply Nlt_in.
    repeat rewrite wordToN_nat.
    repeat rewrite Nat2N.id.
    apply array_bound in H4.
    rewrite length_toArray in *.
    repeat rewrite wordToNat_natToWord_idempotent.
    eapply nth_error_Some_length; eauto.
    apply Nlt_in.
    rewrite Nat2N.id.
    rewrite Npow2_nat.
    omega.
    apply Nlt_in.
    rewrite Nat2N.id.
    rewrite Npow2_nat.
    apply nth_error_Some_length in Heq.
    omega.
  Qed.

  Theorem sym_write_correct : forall args uvars vars cs summ pe p ve v m stn args',
    sym_write Prover summ args pe ve = Some args' ->
    Valid Prover_correct uvars vars summ ->
    exprD funcs uvars vars pe wordT = Some p ->
    exprD funcs uvars vars ve wordT = Some v ->
    match
      applyD (@exprD _ funcs uvars vars) (SEP.SDomain ssig) args _ (SEP.SDenotation ssig)
      with
      | None => False
      | Some p => ST.satisfies cs p stn m
    end ->
    match 
      applyD (@exprD _ funcs uvars vars) (SEP.SDomain ssig) args' _ (SEP.SDenotation ssig)
      with
      | None => False
      | Some pr => 
        match ST.HT.smem_set_word (IL.explode stn) p v m with
          | None => False
          | Some sm' => ST.satisfies cs pr stn sm'
        end
    end.
  Proof.
    simpl; intuition.
    do 4 (destruct args; simpl in *; intuition; try discriminate).
    generalize (deref_correct uvars vars pe); destr idtac (deref pe); intro Hderef.
    destruct p0.
    specialize (Hderef _ _ _ H1 (refl_equal _)).
    destruct Hderef as [ ? [ ] ]; subst.
    generalize (listIn_correct uvars vars e); destr idtac (listIn e); intro HlistIn.
    specialize (HlistIn _ (refl_equal _)).
    rewrite HlistIn in *.

    repeat match goal with
             | [ H : Valid _ _ _ _, _ : context[Prove Prover ?summ ?goal] |- _ ] =>
               match goal with
                 | [ _ : context[ValidProp _ _ _ goal] |- _ ] => fail 1
                 | _ => specialize (Prove_correct Prover_correct summ H (goal := goal)); intro
               end
           end; unfold ValidProp in *.
    unfold types0 in *.
    match type of H with
      | (if ?E then _ else _) = _ => destruct E
    end; intuition; try discriminate.
    simpl in H6.
    case_eq (nth_error l n); [ intros ? Heq | intro Heq ]; rewrite Heq in *; try discriminate.
    rewrite H4 in *.
    injection H; clear H; intros; subst.
    unfold applyD.
    rewrite HlistIn.
    simpl exprD.
    destruct (exprD funcs uvars vars e0 valsT); try tauto.
    rewrite H2.
    unfold Provable in H6.
    simpl in H6.
    rewrite H4 in H6.
    destruct (exprD funcs uvars vars e1 wordT); try tauto.
    specialize (H6 (ex_intro _ _ (refl_equal _))); subst.
    apply simplify_fwd in H3.
    destruct H3 as [ ? [ ? [ ? [ ] ] ] ].
    simpl simplify in *.
    destruct H3.
    apply simplify_bwd in H5.
    eapply smem_write_correct' in H5.
    destruct H5 as [ ? [ ] ].
    rewrite natToW_times4.
    rewrite wmult_comm.
    generalize (split_semp _ _ _ H H6); intro; subst.
    rewrite H5.
    unfold locals.
    apply simplify_bwd.
    exists smem_emp.
    exists x2.
    simpl; intuition.
    apply split_a_semp_a.
    reflexivity.
    apply simplify_fwd.

    Lemma toArray_irrel : forall vs v nm ns,
      ~In nm ns
      -> toArray ns (upd vs nm v) = toArray ns vs.
      induction ns; simpl; intuition.
      f_equal; auto.
      unfold upd.
      rewrite string_eq_false; auto.
    Qed.

    Lemma nth_error_In : forall A (x : A) ls n,
      nth_error ls n = Some x
      -> In x ls.
      induction ls; destruct n; simpl; intuition; try discriminate; eauto.
      injection H; intros; subst; auto.
    Qed.

    Lemma array_updN : forall vs nm v ns,
      NoDup ns
      -> forall n, nth_error ns n = Some nm
        -> Array.updN (toArray ns vs) n v
        = toArray ns (upd vs nm v).
      induction 1; destruct n; simpl; intuition.
      injection H1; clear H1; intros; subst.
      rewrite toArray_irrel by assumption.
      unfold upd; rewrite string_eq_true; reflexivity.
      rewrite IHNoDup; f_equal; auto.
      unfold upd; rewrite string_eq_false; auto.
      intro; subst.
      apply H.
      eapply nth_error_In; eauto.
    Qed.

    unfold Array.upd in H7.
    rewrite wordToNat_natToWord_idempotent in H7.
    erewrite array_updN in H7; eauto.
    apply nth_error_Some_length in Heq.
    apply array_bound in H7.
    Require Import Arrays.
    rewrite updN_length in H7.
    rewrite length_toArray in H7.
    apply Nlt_in.
    rewrite Nat2N.id.
    rewrite Npow2_nat.
    omega.

    rewrite length_toArray.
    apply Nlt_in.
    repeat rewrite wordToN_nat.
    repeat rewrite Nat2N.id.
    apply array_bound in H5.
    rewrite length_toArray in *.
    repeat rewrite wordToNat_natToWord_idempotent.
    eapply nth_error_Some_length; eauto.
    apply Nlt_in.
    rewrite Nat2N.id.
    rewrite Npow2_nat.
    omega.
    apply Nlt_in.
    rewrite Nat2N.id.
    rewrite Npow2_nat.
    apply nth_error_Some_length in Heq.
    omega.
  Qed.

End correctness.

Definition MemEvaluator types' : MEVAL.MemEvaluator (types types') (tvType 0) (tvType 1) :=
  Eval cbv beta iota zeta delta [ MEVAL.PredEval.MemEvalPred_to_MemEvaluator ] in 
    @MEVAL.PredEval.MemEvalPred_to_MemEvaluator _ (tvType 0) (tvType 1) (MemEval types') 2.

Theorem MemEvaluator_correct types' funcs' preds'
  : @MEVAL.MemEvaluator_correct (Env.repr types_r types') (tvType 0) (tvType 1) 
  (MemEvaluator (Env.repr types_r types')) (funcs funcs') (Env.repr (ssig_r _) preds')
  (IL.settings * IL.state) (tvType 0) (tvType 0)
  (@IL_mem_satisfies (types types')) (@IL_ReadWord (types types')) (@IL_WriteWord (types types')).
Proof.
  intros. eapply (@MemPredEval_To_MemEvaluator_correct (types types')); simpl; intros.
  eapply sym_read_correct; eauto.
  eapply sym_write_correct; eauto.
  reflexivity.
Qed.

Definition pack : MEVAL.MemEvaluatorPackage types_r (tvType 0) (tvType 1) (tvType 0) (tvType 0)
  IL_mem_satisfies IL_ReadWord IL_WriteWord :=

  @MEVAL.Build_MemEvaluatorPackage types_r (tvType 0) (tvType 1) (tvType 0) (tvType 0) 
  IL_mem_satisfies IL_ReadWord IL_WriteWord
  types_r
  funcs_r
  (fun ts => Env.listOptToRepr (None :: None :: Some (ssig ts) :: nil)
    (SEP.Default_predicate (Env.repr types_r ts)
      (tvType 0) (tvType 1)))
  (fun ts => MemEvaluator _)
  (fun ts fs ps => MemEvaluator_correct _ _).