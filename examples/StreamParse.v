Require Import PreAutoSep Wrap Conditional.

Import DefineStructured.

Set Implicit Arguments.


(** Simple notation for parsing streams of machine words *)

Inductive pattern0 :=
| Const_ (_ : W)
(* Match this exact word. *)
| Var_ (_ : string)
(* Match anything and stash it in this local variable. *).

Definition pattern := list pattern0.
(* Match a prefix of the stream against these individual word patterns. *)

Definition Const w : pattern := Const_ w :: nil.
Definition Var x : pattern := Var_ x :: nil.

Coercion Const : W >-> pattern.
Coercion Var : string >-> pattern.

Fixpoint matches (p : pattern) (ws : list W) : Prop :=
  match p, ws with
    | nil, _ => True
    | Const_ w :: p', w' :: ws' => w = w' /\ matches p' ws'
    | Var_ _ :: p', _ :: ws' => matches p' ws'
    | _, _ => False
  end.

Fixpoint binds (p : pattern) (ws : list W) : list (string * W) :=
  match p, ws with
    | Const_ _ :: p', _ :: ws' => binds p' ws'
    | Var_ s :: p', w :: ws' => (s, w) :: binds p' ws'
    | _, _ => nil
  end.

Section Parse.
  Variable stream : string.
  (* Name of local variable containing an array to treat as the stream of words *)
  Variable size : string.
  (* Name of local variable containing the stream length in words *)
  Variable pos : string.
  (* Name of local variable containing the current stream position in words *)

  Variable p : pattern.
  (* We will try to match a prefix of the stream against this pattern. *)

  Variable imports : LabelMap.t assert.
  Hypothesis H : importsGlobal imports.
  Variable modName : string.

  Variables Then Else : cmd imports modName.
  (* Code to run when a single pattern matches or fails, respectively. *)

  Variable ns : list string.
  (* Local variable names *)

  (* Does the pattern match? *)
  Fixpoint guard (p : pattern) (offset : nat) : bexp :=
    match p with
      | nil =>
        Test Rv Le (variableSlot size ns)
        (* Is there enough space left in the stream? *)
      | Const_ w :: p' =>
        And (guard p' (S offset))
        (Test (LvMem (Indir Rp (4 * offset))) IL.Eq w)
      | Var_ _ :: p' => guard p' (S offset)
    end.

  (* Once we know that the pattern matches, we set the appropriate pattern variables with this function. *)
  Fixpoint reads (p : pattern) (offset : nat) : list instr :=
    match p with
      | nil => nil
      | Const_ _ :: p' => reads p' (S offset)
      | Var_ x :: p' => Assign (variableSlot x ns) (LvMem (Indir Rp (4 * offset))) :: reads p' (S offset)
    end.

  Fixpoint suffix (n : nat) (ws : list W) : list W :=
    match n with
      | O => ws
      | S n' => match ws with
                  | nil => nil
                  | w :: ws' => suffix n' ws'
                end
    end.

  Lemma suffix_remains : forall n ws,
    (n < length ws)%nat
    -> suffix n ws = selN ws n :: suffix (S n) ws.
    induction n; destruct ws; simpl; intuition.
    rewrite IHn; auto.
  Qed.

  Fixpoint patternBound (p : pattern) : Prop :=
    match p with
      | nil => True
      | Const_ _ :: p' => patternBound p'
      | Var_ x :: p' => In x ns /\ patternBound p'
    end.

  Fixpoint okVarName (x : string) (p : pattern) : Prop :=
    match p with
      | nil => True
      | Const_ _ :: p' => okVarName x p'
      | Var_ x' :: p' => if string_dec x x' then False else okVarName x p'
    end.

  Definition ThenPre (pre : assert) : assert :=
    (fun stn_st => let (stn, st) := stn_st in
      Ex st', pre (stn, st')
      /\ (AlX, Al V, Al ws, Al r,
        ![ ^[array ws (sel V stream) * locals ("rp" :: ns) V r (Regs st Sp)] * #0] (stn, st')
        /\ [| sel V size = length ws |]
        ---> [| matches p (suffix (wordToNat (sel V pos)) ws)
          /\ exists st'', Mem st'' = Mem st'
            /\ evalInstrs stn st'' (map (fun p => Assign (variableSlot (fst p) ns) (RvImm (snd p)))
              (binds p (suffix (wordToNat (sel V pos)) ws))
              ++ Binop (variableSlot pos ns) (variableSlot pos ns) Plus (length p)
              :: nil) = Some st |])
      /\ [| Regs st Sp = Regs st' Sp |])%PropX.

  Definition ElsePre (pre : assert) : assert :=
    (fun stn_st => let (stn, st) := stn_st in
      Ex st', pre (stn, st')
      /\ (AlX, Al V, Al ws, Al r,
        ![ ^[array ws (sel V stream) * locals ("rp" :: ns) V r (Regs st Sp)] * #0] (stn, st')
        /\ [| sel V size = length ws |]
        ---> [| ~matches p (suffix (wordToNat (sel V pos)) ws) |])
      /\ [| Regs st Sp = Regs st' Sp /\ Mem st = Mem st' |])%PropX.

  (* Here's the raw parsing command, which we will later wrap with nicer VCs. *)
  Definition Parse1_ : cmd imports modName := fun pre =>
    Seq_ H (Straightline_ _ _ (Binop Rv (variableSlot pos ns) Plus (length p)
      :: Binop Rp 4 Times (variableSlot pos ns)
      :: Binop Rp (variableSlot stream ns) Plus Rp
      :: nil))
    (Cond_ _ H _ (guard p O)
      (Seq_ H
        (Straightline_ _ _ (reads p O
          ++ Binop (variableSlot pos ns) (variableSlot pos ns) Plus (length p)
          :: nil))
        (Seq_ H
          (Structured.Assert_ _ _ (ThenPre pre))
          Then))
      (Seq_ H
        (Structured.Assert_ _ _ (ElsePre pre))
        Else))
    pre.

  Lemma four_plus_variablePosition : forall x ns',
    ~In "rp" ns'
    -> In x ns'
    -> 4 + variablePosition ns' x = variablePosition ("rp" :: ns') x.
    unfold variablePosition at 2; intros.
    destruct (string_dec "rp" x); auto; subst; tauto.
  Qed.

  Ltac prep_locals :=
    unfold variableSlot in *; repeat rewrite four_plus_variablePosition in * by assumption;
      repeat match goal with
               | [ H : In ?X ?ls |- _ ] =>
                 match ls with
                   | "rp" :: _ => fail 1
                   | _ =>
                     match goal with
                       | [ _ : In X ("rp" :: ls) |- _ ] => fail 1
                       | _ => assert (In X ("rp" :: ls)) by (simpl; tauto)
                     end
                 end
             end.

  Hint Rewrite wordToN_nat wordToNat_natToWord_idempotent using assumption : N.
  Require Import Arith.

  Theorem lt_goodSize : forall n m,
    (n < m)%nat
    -> goodSize n
    -> goodSize m
    -> natToW n < natToW m.
    unfold goodSize, natToW, W; generalize 32; intros; nomega.
  Qed.

  Theorem goodSize_weaken : forall n m,
    goodSize n
    -> (m <= n)%nat
    -> goodSize m.
    unfold goodSize; generalize 32; intros; nomega.
  Qed.

  Hint Resolve lt_goodSize goodSize_weaken.
  Hint Extern 1 (_ <= _)%nat => omega.

  Opaque mult.

  Lemma bexpTrue_bound : forall specs stn st ws V r fr,
    interp specs
    (![array ws (sel V stream) * locals ("rp" :: ns) V r (Regs st Sp) * fr] (stn, st))
    -> In size ns
    -> ~In "rp" ns
    -> forall p' offset, bexpTrue (guard p' offset) stn st
      -> Regs st Rv <= sel V size.
    clear H; induction p' as [ | [ ] ]; simpl; intuition eauto.

    prep_locals; evaluate auto_ext; tauto.
  Qed.

  Theorem wle_goodSize : forall n m,
    natToW n <= natToW m
    -> goodSize n
    -> goodSize m
    -> (n <= m)%nat.
    intros.
    destruct (le_lt_dec n m); auto.
    elimtype False.
    apply H0.
    apply Nlt_in.
    autorewrite with N.
    auto.
  Qed.

  Lemma bexpSafe_guard : forall specs stn st ws V r fr,
    interp specs
    (![array ws (sel V stream) * locals ("rp" :: ns) V r (Regs st Sp) * fr] (stn, st))
    -> In size ns
    -> ~In "rp" ns
    -> Regs st Rp = sel V stream ^+ $4 ^* sel V pos
    -> sel V size = $(length ws)
    -> forall p' offset,
      Regs st Rv = $(offset + wordToNat (sel V pos) + length p')
      -> goodSize (offset + wordToNat (sel V pos) + Datatypes.length p')
      -> bexpSafe (guard p' offset) stn st.
    clear H; induction p' as [ | [ ] ]; simpl; intuition.

    prep_locals; evaluate auto_ext.

    apply IHp'.
    rewrite H4; f_equal; omega.
    eauto.

    replace (evalCond (LvMem (Rp + 4 * offset)%loc) IL.Eq w stn st)
      with (evalCond (LvMem (Imm (sel V stream ^+ $4 ^* $(offset + wordToNat (sel V pos))))) IL.Eq w stn st)
        in *.
    assert (goodSize (length ws)) by eauto.
    assert (natToW (offset + wordToNat (sel V pos)) < $(length ws)).
    specialize (bexpTrue_bound _ H H0 H1 _ _ H6).
    rewrite H3, H4.
    intros.
    apply wle_goodSize in H9; auto; eauto.

    prep_locals; evaluate auto_ext.

    unfold evalCond; simpl.
    rewrite H2.
    match goal with
      | [ |- match ReadWord _ _ ?X with None => _ | _ => _ end
        = match ReadWord _ _ ?Y with None => _ | _ => _ end ] => replace Y with X; auto
    end.
    rewrite mult_comm; rewrite natToW_times4.
    rewrite natToW_plus.
    unfold natToW.
    rewrite natToWord_wordToNat.
    W_eq.

    apply IHp'; eauto.
    rewrite H4; f_equal; omega.
  Qed.

  Lemma bexpTrue_matches : forall specs stn st ws V r fr,
    interp specs
    (![array ws (sel V stream) * locals ("rp" :: ns) V r (Regs st Sp) * fr] (stn, st))
    -> In size ns
    -> ~In "rp" ns
    -> Regs st Rp = sel V stream ^+ $4 ^* sel V pos
    -> forall p' offset, bexpTrue (guard p' offset) stn st
      -> Regs st Rv = $(offset + wordToNat (sel V pos) + length p')
      -> (offset + wordToNat (sel V pos) <= length ws)%nat
      -> sel V size = $(length ws)
      -> goodSize (offset + wordToNat (sel V pos) + length p')
      -> matches p' (suffix (offset + wordToNat (sel V pos)) ws).
    clear H; induction p' as [ | [ ] ]; simpl; intuition.

    specialize (bexpTrue_bound _ H H0 H1 _ _ H8).
    rewrite H4; intros.
    replace (evalCond (LvMem (Rp + 4 * offset)%loc) IL.Eq w stn st)
      with (evalCond (LvMem (Imm (sel V stream ^+ $4 ^* $(offset + wordToNat (sel V pos))))) IL.Eq w stn st)
        in *.
    rewrite H6 in H3.
    eapply wle_goodSize in H3.
    rewrite suffix_remains in * by auto.
    assert (natToW (offset + wordToNat (sel V pos)) < natToW (length ws))
      by (apply lt_goodSize; eauto).
    prep_locals; evaluate auto_ext.

    split.
    subst.
    unfold Array.sel.
    rewrite wordToNat_natToWord_idempotent; auto.
    change (goodSize (offset + wordToNat (sel V pos))); eauto.
    change (S (offset + wordToNat (sel V pos))) with (S offset + wordToNat (sel V pos)).
    apply IHp'; auto.
    rewrite H4; f_equal; omega.
    eauto.
    eauto.
    eauto.

    unfold evalCond; simpl.
    rewrite H2.
    match goal with
      | [ |- match ?E with None => _ | _ => _ end = match ?E' with None => _ | _ => _ end ] =>
        replace E with E'; auto
    end.
    f_equal.
    rewrite natToW_plus.
    rewrite mult_comm; rewrite natToW_times4.
    unfold natToW.
    rewrite natToWord_wordToNat.
    W_eq.


    specialize (bexpTrue_bound _ H H0 H1 _ _ H3).    
    rewrite H4; intros.
    rewrite H6 in H8.
    eapply wle_goodSize in H8.
    rewrite suffix_remains in * by auto.
    change (S (offset + wordToNat (sel V pos))) with (S offset + wordToNat (sel V pos)).
    apply IHp'; auto.
    rewrite H4; f_equal; omega.
    eauto.
    eauto.
    eauto.
  Qed.

  Theorem le_goodSize : forall n m,
    (n <= m)%nat
    -> goodSize n
    -> goodSize m
    -> natToW n <= natToW m.
    unfold goodSize, natToW, W; generalize 32; intros; nomega.
  Qed.

  Theorem lt_goodSize' : forall n m,
    natToW n < natToW m
    -> goodSize n
    -> goodSize m
    -> (n < m)%nat.
    unfold goodSize, natToW, W; generalize 32; intros.
    pre_nomega.
    repeat rewrite wordToNat_natToWord_idempotent in H0 by nomega.
    assumption.
  Qed.

  Lemma suffix_none : forall n ls,
    (n >= length ls)%nat
    -> suffix n ls = nil.
    induction n; destruct ls; simpl; intuition.
  Qed.

  Lemma bexpFalse_not_matches : forall specs stn st ws V r fr,
    interp specs
    (![array ws (sel V stream) * locals ("rp" :: ns) V r (Regs st Sp) * fr] (stn, st))
    -> In size ns
    -> ~In "rp" ns
    -> Regs st Rp = sel V stream ^+ $4 ^* sel V pos
    -> sel V size = $(length ws)
    -> forall p' offset, bexpFalse (guard p' offset) stn st
      -> Regs st Rv = $(offset + wordToNat (sel V pos) + length p')
      -> (offset + wordToNat (sel V pos) <= length ws)%nat
      -> goodSize (offset + wordToNat (sel V pos) + length p')
      -> ~matches p' (suffix (offset + wordToNat (sel V pos)) ws).
    clear H; induction p' as [ | [ ] ]; simpl; intuition.

    prep_locals; evaluate auto_ext.
    rewrite H3 in *.
    apply lt_goodSize' in H13.
    omega.
    eauto.
    eauto.


    destruct (le_lt_dec (length ws) (offset + wordToNat (sel V pos))).
    rewrite suffix_none in *; auto.
    rewrite suffix_remains in * by auto.
    assert (natToW (offset + wordToNat (sel V pos)) < natToW (length ws))
      by (apply lt_goodSize; eauto).
    prep_locals; evaluate auto_ext.
    eapply IHp'; eauto.
    rewrite H5; f_equal; omega.

    specialize (bexpTrue_bound _ H H0 H1 _ _ H4).
    rewrite H5; intros.
    destruct (le_lt_dec (length ws) (offset + wordToNat (sel V pos))).
    rewrite suffix_none in *; auto.
    rewrite suffix_remains in * by auto.
    replace (evalCond (LvMem (Rp + 4 * offset)%loc) IL.Eq w stn st)
      with (evalCond (LvMem (Imm (sel V stream ^+ $4 ^* $(offset + wordToNat (sel V pos))))) IL.Eq w stn st)
        in *.
    assert (natToW (offset + wordToNat (sel V pos)) < natToW (length ws))
      by (apply lt_goodSize; eauto).
    prep_locals; evaluate auto_ext.
    subst.
    apply H16.
    unfold Array.sel.
    rewrite wordToNat_natToWord_idempotent; auto.
    change (goodSize (offset + wordToNat (sel V pos))); eauto.

    unfold evalCond; simpl.
    rewrite H2.
    match goal with
      | [ |- match ?E with None => _ | _ => _ end = match ?E' with None => _ | _ => _ end ] =>
        replace E with E'; auto
    end.
    f_equal.
    rewrite natToW_plus.
    rewrite mult_comm; rewrite natToW_times4.
    unfold natToW.
    rewrite natToWord_wordToNat.
    W_eq.

    destruct (le_lt_dec (length ws) (offset + wordToNat (sel V pos))).
    rewrite suffix_none in *; auto.
    rewrite suffix_remains in * by auto.
    intuition; subst.
    eapply IHp'; eauto.
    rewrite H5; f_equal; omega.
  Qed.

  Transparent evalInstrs.

  Lemma evalInstrs_app_fwd : forall stn is2 st' is1 st,
    evalInstrs stn st (is1 ++ is2) = Some st'
    -> exists st'', evalInstrs stn st is1 = Some st''
      /\ evalInstrs stn st'' is2 = Some st'.
    induction is1; simpl; intuition eauto.
    destruct (evalInstr stn st a); eauto; discriminate.
  Qed.

  Opaque evalInstr.

  Lemma evalInstr_evalInstrs : forall stn st i,
    evalInstr stn st i = evalInstrs stn st (i :: nil).
    simpl; intros; destruct (evalInstr stn st i); auto.
  Qed.

  Lemma reads_nocrash : forall specs stn ws r fr,
    ~In "rp" ns
    -> forall p' offset st V, patternBound p'
      -> interp specs (![array ws (sel V stream) * locals ("rp" :: ns) V r (Regs st Sp) * fr] (stn, st))
      -> Regs st Rp = sel V stream ^+ $4 ^* sel V pos
      -> (offset + wordToNat (sel V pos) + length p' <= length ws)%nat
      -> okVarName stream p'
      -> okVarName pos p'
      -> evalInstrs stn st (reads p' offset) = None
      -> False.
    clear H; induction p' as [ | [ ] ]; simpl; intuition.

    eapply IHp'; eauto.
    match goal with
      | [ H : (?U <= ?X)%nat |- (?V <= ?X)%nat ] => replace V with U; auto; omega
    end.

    destruct (string_dec stream s); try tauto.
    destruct (string_dec pos s); try tauto.

    case_eq (evalInstr stn st (Assign (variableSlot s ns) (LvMem (Rp + 4 * offset)%loc))); intros;
      match goal with
        | [ H : _ = _ |- _ ] => rewrite H in *
      end.

    replace (evalInstr stn st (Assign (variableSlot s ns) (LvMem (Rp + 4 * offset)%loc)))
      with (evalInstr stn st (Assign (variableSlot s ns)
        (LvMem (Imm (sel V stream ^+ $4 ^* $(offset + wordToNat (sel V pos))))))) in *.
    generalize dependent H6; prep_locals.
    assert (natToW (offset + wordToNat (sel V pos)) < $(length ws)).
    apply lt_goodSize; eauto.
    prep_locals.
    rewrite evalInstr_evalInstrs in H0.
    evaluate auto_ext.
    intros.
    eapply IHp'.
    eauto.
    instantiate (1 := s0).
    step auto_ext.
    reflexivity.
    repeat rewrite sel_upd_ne by congruence.
    assumption.
    instantiate (1 := S offset).
    repeat rewrite sel_upd_ne by congruence.    
    match goal with
      | [ H : (?U <= ?X)%nat |- (?V <= ?X)%nat ] => replace V with U; auto; omega
    end.
    assumption.
    assumption.
    assumption.
    Transparent evalInstr.
    simpl.
    match goal with
      | [ |- match ?E with None => _ | _ => _ end = match ?E' with None => _ | _ => _ end ] =>
        replace E with E'; auto
    end.
    f_equal.
    rewrite H2.
    rewrite natToW_plus.
    rewrite mult_comm; rewrite natToW_times4.
    unfold natToW.
    rewrite natToWord_wordToNat.
    W_eq.

    replace (evalInstr stn st (Assign (variableSlot s ns) (LvMem (Rp + 4 * offset)%loc)))
      with (evalInstr stn st (Assign (variableSlot s ns)
        (LvMem (Imm (sel V stream ^+ $4 ^* $(offset + wordToNat (sel V pos))))))) in *.
    generalize dependent H6; prep_locals.
    assert (natToW (offset + wordToNat (sel V pos)) < $(length ws)).
    apply lt_goodSize; eauto.
    prep_locals.
    rewrite evalInstr_evalInstrs in H0.
    evaluate auto_ext.

    simpl.
    match goal with
      | [ |- match ?E with None => _ | _ => _ end = match ?E' with None => _ | _ => _ end ] =>
        replace E with E'; auto
    end.
    f_equal.
    rewrite H2.
    rewrite natToW_plus.
    rewrite mult_comm; rewrite natToW_times4.
    unfold natToW.
    rewrite natToWord_wordToNat.
    W_eq.
  Qed.

  Opaque evalInstr.

  Lemma reads_exec' : forall specs stn ws r fr,
    ~In "rp" ns
    -> forall p' offset st st' V, patternBound p'
      -> interp specs (![array ws (sel V stream) * locals ("rp" :: ns) V r (Regs st Sp) * fr] (stn, st))
      -> Regs st Rp = sel V stream ^+ $4 ^* sel V pos
      -> (offset + wordToNat (sel V pos) + length p' <= length ws)%nat
      -> okVarName stream p'
      -> okVarName pos p'
      -> evalInstrs stn st (reads p' offset) = Some st'
      -> exists V',
        interp specs (![array ws (sel V stream) * locals ("rp" :: ns) V' r (Regs st Sp) * fr] (stn, st'))
        /\ Regs st' Sp = Regs st Sp.
    clear H; induction p' as [ | [ ] ]; simpl; intuition.

    injection H6; intros; subst.
    eauto.

    eapply IHp'; eauto.
    match goal with
      | [ H : (?U <= ?X)%nat |- (?V <= ?X)%nat ] => replace V with U; auto; omega
    end.

    destruct (string_dec stream s); try tauto.
    destruct (string_dec pos s); try tauto.

    case_eq (evalInstr stn st (Assign (variableSlot s ns) (LvMem (Rp + 4 * offset)%loc))); intros;
      match goal with
        | [ H : _ = _ |- _ ] => rewrite H in *
      end.

    replace (evalInstr stn st (Assign (variableSlot s ns) (LvMem (Rp + 4 * offset)%loc)))
      with (evalInstr stn st (Assign (variableSlot s ns)
        (LvMem (Imm (sel V stream ^+ $4 ^* $(offset + wordToNat (sel V pos))))))) in *.
    generalize dependent H6; prep_locals.
    assert (natToW (offset + wordToNat (sel V pos)) < $(length ws)).
    apply lt_goodSize; eauto.
    prep_locals.
    rewrite evalInstr_evalInstrs in H0.
    evaluate auto_ext.
    intros.
    eapply (IHp' _ _ _ (upd V s (Array.sel ws (offset + wordToNat (sel V pos))))) in H13.
    rewrite <- H1.
    rewrite sel_upd_ne in H13 by congruence.
    assumption.
    eauto.
    step auto_ext.
    reflexivity.
    rewrite H10.
    repeat rewrite sel_upd_ne by congruence.
    W_eq.
    repeat rewrite sel_upd_ne by congruence.
    match goal with
      | [ H : (?U <= ?X)%nat |- (?V <= ?X)%nat ] => replace V with U; auto; omega
    end.
    assumption.
    assumption.
    Transparent evalInstr.
    simpl.
    match goal with
      | [ |- match ?E with None => _ | _ => _ end = match ?E' with None => _ | _ => _ end ] =>
        replace E with E'; auto
    end.
    f_equal.
    rewrite H2.
    rewrite natToW_plus.
    rewrite mult_comm; rewrite natToW_times4.
    unfold natToW.
    rewrite natToWord_wordToNat.
    W_eq.

    replace (evalInstr stn st (Assign (variableSlot s ns) (LvMem (Rp + 4 * offset)%loc)))
      with (evalInstr stn st (Assign (variableSlot s ns)
        (LvMem (Imm (sel V stream ^+ $4 ^* $(offset + wordToNat (sel V pos))))))) in *.
    generalize dependent H6; prep_locals.
    assert (natToW (offset + wordToNat (sel V pos)) < $(length ws)).
    apply lt_goodSize; eauto.
    prep_locals.
    rewrite evalInstr_evalInstrs in H0.
    evaluate auto_ext.

    simpl.
    match goal with
      | [ |- match ?E with None => _ | _ => _ end = match ?E' with None => _ | _ => _ end ] =>
        replace E with E'; auto
    end.
    f_equal.
    rewrite H2.
    rewrite natToW_plus.
    rewrite mult_comm; rewrite natToW_times4.
    unfold natToW.
    rewrite natToWord_wordToNat.
    W_eq.
  Qed.

  Lemma reads_exec : forall stn st p' offset st',
    evalInstrs stn st (reads p' offset) = Some st'
    -> ~In "rp" ns
    -> forall specs ws r fr V, patternBound p'
      -> interp specs (![array ws (sel V stream) * locals ("rp" :: ns) V r (Regs st Sp) * fr] (stn, st))
      -> Regs st Rp = sel V stream ^+ $4 ^* sel V pos
      -> (offset + wordToNat (sel V pos) + length p' <= length ws)%nat
      -> okVarName stream p'
      -> okVarName pos p'

      -> exists V',
        interp specs (![array ws (sel V stream) * locals ("rp" :: ns) V' r (Regs st Sp) * fr] (stn, st'))
        /\ Regs st' Sp = Regs st Sp.
    eauto using reads_exec'.
  Qed.

  Lemma evalInstrs_app_fwd_None : forall stn is2 is1 st,
    evalInstrs stn st (is1 ++ is2) = None
    -> evalInstrs stn st is1 = None
    \/ (exists st', evalInstrs stn st is1 = Some st' /\ evalInstrs stn st' is2 = None).
    induction is1; simpl; intuition eauto.
    destruct (evalInstr stn st a); eauto.
  Qed.

  Fixpoint scratchOnly (is : list instr) : Prop :=
    match is with
      | nil => True
      | Assign (LvReg r) _ :: is' => r <> Sp /\ scratchOnly is'
      | Binop (LvReg r) _ _ _ :: is' => r <> Sp /\ scratchOnly is'
      | _ => False
    end.

  Ltac matcher := repeat match goal with
                           | [ _ : context[match ?E with None => _ | _ => _ end] |- _ ] =>
                             match E with
                               | context[match _ with None => _ | _ => _ end] => fail 1
                               | _ => destruct E; try discriminate
                             end
                           | [ |- context[match ?E with None => _ | _ => _ end] ] =>
                             match E with
                               | context[match _ with None => _ | _ => _ end] => fail 1
                               | _ => destruct E; try discriminate
                             end
                         end.

  Theorem scratchOnlySp : forall stn st' is st,
    scratchOnly is
    -> evalInstrs stn st is = Some st'
    -> Regs st' Sp = Regs st Sp.
    induction is as [ | [ [ ] | [ ] ] ]; simpl; intuition; matcher;
      erewrite IHis by eassumption; apply rupd_ne; auto.
  Qed.

  Theorem scratchOnlyMem : forall stn st' is st,
    scratchOnly is
    -> evalInstrs stn st is = Some st'
    -> Mem st' = Mem st.
    induction is as [ | [ [ ] | [ ] ] ]; simpl; intuition; matcher;
      erewrite IHis by eassumption; reflexivity.
  Qed.

  Theorem sepFormula_Mem : forall specs stn st st' P,
    interp specs (![P] (stn, st))
    -> Mem st' = Mem st
    -> interp specs (![P] (stn, st')).
    rewrite sepFormula_eq; unfold sepFormula_def; simpl; intros; congruence.
  Qed.

  Opaque evalInstrs.

  Fixpoint arrayImplies (f : nat -> option W) (ws : list W) (offset : nat) : Prop :=
    match ws with
      | nil => True
      | w :: ws' => f offset = Some w /\ arrayImplies f ws' (4 + offset)
    end.

  Lemma implies_inj_and : forall pc state (specs : codeSpec pc state) G P Q,
    valid specs G [| P |]%PropX
    -> valid specs G [| Q |]%PropX
    -> valid specs G [| P /\ Q |]%PropX.
    intros.
    eapply Imply_E; [ | eassumption ].
    apply Imply_I.
    eapply Imply_E; [ | eapply valid_weaken; try apply H0; hnf; simpl; tauto ].
    apply Imply_I.
    eapply Inj_E; [ apply Env; simpl; eauto | intro ].
    eapply Inj_E; [ apply Env; simpl; left; eauto | intro ].
    apply Inj_I; tauto.
  Qed.

  Lemma arrayImplies_weaken : forall f f',
    (forall n v, f n = Some v -> f' n = Some v)
    -> forall ws offset,
      arrayImplies f ws offset
      -> arrayImplies f' ws offset.
    induction ws; simpl; intuition.
  Qed.

  Lemma inj_imply : forall pc state (specs : codeSpec pc state) (P Q : Prop),
    (P -> Q)
    -> interp specs ([| P |] ---> [| Q |])%PropX.
    intros; apply Imply_I; eapply Inj_E; [ apply Env; simpl; eauto | ];
      intro; apply Inj_I; tauto.
  Qed.

  Lemma ptsto32m'_implies : forall specs stn p ws offset m,
    interp specs (ptsto32m' _ p offset ws stn m --->
      [| arrayImplies (fun n => smem_get_word (implode stn) (p ^+ $(n)) m) ws offset |])%PropX.
    induction ws; simpl; intuition.
    apply Imply_I; apply Inj_I; constructor.
    unfold starB, star; apply Imply_I.
    eapply Exists_E; [ apply Env; simpl; eauto | cbv beta; intro ].
    eapply Exists_E; [ apply Env; simpl; left; eauto | cbv beta; intro ].
    apply implies_inj_and.
    unfold ptsto32.
    eapply Inj_E; [ eapply And_E1; apply Env; simpl; eauto | intro ].
    eapply Inj_E; [ eapply And_E1; eapply And_E2; apply Env; simpl; eauto | intro ].
    apply Inj_I.
    eapply split_smem_get_word; eauto.
    tauto.
    eapply Inj_E; [ eapply And_E1; apply Env; simpl; eauto | intro ].
    eapply Imply_E; [ apply interp_weaken; apply inj_imply;
      apply (arrayImplies_weaken (fun n => smem_get_word (implode stn) (p0 ^+ $ (n)) B0)) | ].
    intros; eapply split_smem_get_word; eauto.
    eapply Imply_E.
    eauto.
    eapply And_E2; eapply And_E2; apply Env; simpl; eauto.
  Qed.

  Lemma ptsto32m_implies : forall specs stn m p ws offset,
    interp specs (ptsto32m _ p offset ws stn m --->
      [| arrayImplies (fun n => smem_get_word (implode stn) (p ^+ $(n)) m) ws offset |])%PropX.
    intros; eapply Imply_trans; apply ptsto32m'_implies || apply ptsto32m'_in.
  Qed.

  Lemma array_implies : forall specs stn m ws p,
    interp specs (array ws p stn m --->
      [| arrayImplies (fun n => smem_get_word (implode stn) (p ^+ $(n)) m) ws 0 |])%PropX.
    intros; apply ptsto32m_implies.
  Qed.

  Lemma arrayImplies_equal : forall stn p m m1 m2 m1' m2',
    split m m1 m2
    -> split m m1' m2'
    -> forall ws ws' offset,
      arrayImplies (fun n => smem_get_word (implode stn) (p ^+ $(n)) m1) ws offset
      -> arrayImplies (fun n => smem_get_word (implode stn) (p ^+ $(n)) m1') ws' offset
      -> length ws' = length ws
      -> ws' = ws.
    induction ws; destruct ws'; simpl; intuition.
    f_equal; eauto.
    eapply split_smem_get_word in H0; [ | eauto ].
    eapply split_smem_get_word in H1; [ | eauto ].
    congruence.
  Qed.

  Lemma array_equals : forall specs stn st ws p fr ws' fr',
    interp specs (![array ws p * fr] (stn, st))
    -> interp specs (![array ws' p * fr'] (stn, st) --->
      [| length ws' = length ws -> ws' = ws |])%PropX.
    rewrite sepFormula_eq; unfold sepFormula_def, starB, star; simpl; intros.
    propxFo.
    eapply Imply_sound in H0; [ | apply array_implies ]; propxFo.
    apply Imply_I.
    eapply Exists_E; [ apply Env; simpl; eauto | cbv beta; intro ].
    eapply Exists_E; [ apply Env; simpl; left; eauto | cbv beta; intro ].
    eapply Inj_E; [ eapply And_E1; apply Env; simpl; eauto | cbv beta; intro ].
    eapply Imply_E.
    eapply Imply_trans'.
    apply interp_weaken; apply array_implies.
    apply Imply_I.
    eapply Inj_E; [ apply Env; simpl; eauto | cbv beta; intro ].
    apply Inj_I; intro.
    eauto using arrayImplies_equal.
    eapply And_E1; eapply And_E2; apply Env; simpl; eauto.
  Qed.

  Lemma imply_and : forall pc state (specs : codeSpec pc state) (P : Prop) Q R,
    (P -> interp specs (Q ---> R)%PropX)
    -> interp specs (Q /\ [| P |] ---> R)%PropX.
    intros; apply Imply_I.
    eapply Inj_E; [ eapply And_E2; apply Env; simpl; eauto | ]; intuition.
    eapply Imply_E; eauto.
    eapply And_E1; apply Env; simpl; eauto.
  Qed.

  Lemma toArray_sel : forall x V V' ns',
    In x ns'
    -> toArray ns' V' = toArray ns' V
    -> sel V' x = sel V x.
    unfold toArray; induction ns'; simpl; intuition.
    subst.
    injection H1; intros.
    assumption.
  Qed.

  Lemma unify_V : forall specs stn st ws V r sp fr ws' V' r' fr',
    interp specs (![array ws (sel V stream) * locals ("rp" :: ns) V r sp * fr] (stn, st))
    -> sel V size = length ws
    -> sel V' size = length ws'
    -> interp specs (![array ws' (sel V' stream) * locals ("rp" :: ns) V' r' sp * fr'] (stn, st)
       ---> [| forall x, In x ns -> sel V' x = sel V x |])%PropX.
    clear H; intros.
    assert (Hlocals : exists FR, interp specs (![array (toArray ("rp" :: ns) V) sp * FR] (stn, st)))
      by (eexists; unfold locals in H; step auto_ext); destruct Hlocals as [ FR Hlocals ].
    assert (Hlocals' : exists FR', himp specs
      (array ws' (sel V' stream) * locals ("rp" :: ns) V' r' sp * fr')%Sep
      (array (toArray ("rp" :: ns) V') sp * FR')%Sep)
      by (eexists; unfold locals; step auto_ext); destruct Hlocals' as [ FR' Hlocals' ].
    eapply Imply_trans; try (rewrite sepFormula_eq; apply Hlocals').
    simpl.
    replace ((array (V' "rp" :: toArray ns V') sp * FR')%Sep stn (memoryIn (Mem st)))
      with (![array (V' "rp" :: toArray ns V') sp * FR'] (stn, st))%PropX
        by (rewrite sepFormula_eq; reflexivity).
    eapply Imply_trans.
    eapply array_equals; eauto.
    simpl; repeat rewrite length_toArray in *; apply inj_imply; intuition.
    injection H3; clear H3; intros.
    eauto using toArray_sel.
  Qed.

  Lemma unify_ws : forall specs stn st ws V r sp fr ws' V' r' fr' streamV,
    interp specs (![array ws streamV * locals ("rp" :: ns) V r sp * fr] (stn, st))
    -> length ws' = length ws
    -> interp specs (![array ws' streamV * locals ("rp" :: ns) V' r' sp * fr'] (stn, st)
       ---> [| ws' = ws |])%PropX.
    clear H; intros.
    assert (Hlocals : interp specs (![array ws streamV * (locals ("rp" :: ns) V r sp * fr)] (stn, st)))
       by step auto_ext.
    assert (Hlocals' : himp specs
      (array ws' streamV * locals ("rp" :: ns) V' r' sp * fr')%Sep
      (array ws' streamV * (locals ("rp" :: ns) V' r' sp * fr'))%Sep)
      by step auto_ext.
    eapply Imply_trans; try (rewrite sepFormula_eq; apply Hlocals').
    simpl.
    replace ((array ws' streamV * (locals ("rp" :: ns) V' r' sp * fr'))%Sep stn
      (memoryIn (Mem st)))
      with (![array ws' streamV * (locals ("rp" :: ns) V' r' sp * fr')] (stn, st))%PropX
        by (rewrite sepFormula_eq; reflexivity).
    eapply Imply_trans.
    eapply array_equals; eauto.
    apply inj_imply; intuition.
  Qed.

  Transparent mult.

  Lemma smem_read_correctx'' : forall cs base stn ws offset i m,
    (i < length ws)%nat
    -> interp cs (ptsto32m' _ base (offset * 4) ws stn m
      ---> [| smem_get_word (implode stn) (base ^+ $((offset + i) * 4)) m = Some (selN ws i) |])%PropX.
    induction ws.

    simpl length.
    intros.
    elimtype False.
    nomega.

    simpl length.
    unfold ptsto32m'.
    fold ptsto32m'.
    intros.
    destruct i; simpl selN.
    replace (offset + 0) with offset by omega.
    unfold starB, star.
    apply Imply_I.
    eapply Exists_E; [ apply Env; simpl; eauto | cbv beta; intro ].
    eapply Exists_E; [ apply Env; simpl; left; eauto | cbv beta; intro ].
    unfold ptsto32.
    eapply Inj_E; [ eapply And_E1; apply Env; simpl; eauto | intro ].
    eapply Inj_E; [ eapply And_E1; eapply And_E2; apply Env; simpl; eauto | intro ].
    apply Inj_I.
    eapply split_smem_get_word; eauto.
    tauto.

    unfold starB, star.
    apply Imply_I.
    eapply Exists_E; [ apply Env; simpl; eauto | cbv beta; intro ].
    eapply Exists_E; [ apply Env; simpl; left; eauto | cbv beta; intro ].
    replace (4 + offset * 4) with (S offset * 4) by omega.
    replace (offset + S i) with (S offset + i) by omega.
    eapply Imply_E.
    eapply Imply_trans'.
    apply interp_weaken; apply IHws.
    instantiate (1 := i); omega.
    instantiate (1 := B0).
    eapply Inj_E; [ eapply And_E1; apply Env; simpl; eauto | intro ].
    apply interp_weaken; apply inj_imply.
    instantiate (1 := S offset).
    intros.
    eapply split_smem_get_word; eauto.
    simpl.
    do 2 eapply And_E2; apply Env; simpl; eauto.
  Qed.

  Lemma array_boundx' : forall cs base stn ws m i,
    (0 < i < length ws)%nat
    -> base ^+ $(i * 4) = base
    -> interp cs (ptsto32m' _ base 0 ws stn m ---> [| False |])%PropX.
    destruct ws; simpl length; intros.

    elimtype False; omega.

    propxFo.
    destruct i; try omega.
    simpl in H1.
    unfold starB, star.
    apply Imply_I.
    eapply Exists_E; [ apply Env; simpl; eauto | cbv beta; intro ].
    eapply Exists_E; [ apply Env; simpl; left; eauto | cbv beta; intro ].
    generalize (@smem_read_correctx'' cs base stn ws 1 i B0).
    simpl.
    rewrite H1.
    intro Hlem.
    assert (i < length ws)%nat by omega; intuition.
    eapply Inj_E.
    unfold ptsto32.
    eapply And_E1; eapply And_E2; apply Env; simpl; eauto.
    rewrite wplus_comm.
    rewrite wplus_unit.
    intuition.
    eapply Inj_E; [ eapply And_E1; apply Env; simpl; eauto | intro ].
    eapply Inj_E.
    eapply Imply_E.
    eauto.
    do 2 eapply And_E2; apply Env; simpl; eauto.
    intro.
    apply Inj_I.
    destruct H5.
    eapply smem_get_word_disjoint; eauto.
  Qed.

  Lemma array_boundx : forall cs ws base stn m,
    interp cs (array ws base stn m ---> [| length ws < pow2 32 |]%nat)%PropX.
    intros.
    destruct (lt_dec (length ws) (pow2 32)); auto.
    apply Imply_I; apply Inj_I; auto.
    eapply Imply_trans with [| False |]%PropX; [ | apply inj_imply; tauto ].
    eapply Imply_trans; try apply ptsto32m'_in.
    apply array_boundx' with (pow2 30).
    split.
    unfold pow2; omega.
    specialize (@pow2_monotone 30 32).
    omega.
    change (pow2 30 * 4) with (pow2 30 * pow2 2).
    rewrite pow2_mult.
    simpl plus.
    clear.
    rewrite wplus_alt.
    unfold wplusN, wordBinN.
    rewrite natToWord_pow2.
    rewrite roundTrip_0.
    rewrite plus_0_r.
    apply natToWord_wordToNat.
  Qed.

  Theorem containsArray_boundx' : forall cs P stn ls,
    containsArray P ls
    -> forall st, interp cs (P stn st ---> [|length ls < pow2 32|]%nat)%PropX.
    induction 1; intros.
    eapply array_boundx; eauto.

    unfold SEP.ST.star.
    apply Imply_I.
    eapply Exists_E; [ apply Env; simpl; eauto | cbv beta; intro ].
    eapply Exists_E; [ apply Env; simpl; left; eauto | cbv beta; intro ].
    eapply Imply_E; eauto.
    eapply And_E1; eapply And_E2; apply Env; simpl; eauto.

    unfold SEP.ST.star.
    apply Imply_I.
    eapply Exists_E; [ apply Env; simpl; eauto | cbv beta; intro ].
    eapply Exists_E; [ apply Env; simpl; left; eauto | cbv beta; intro ].
    eapply Imply_E; eauto.
    do 2 eapply And_E2; apply Env; simpl; eauto.

    rewrite upd_length in *; eauto.
  Qed.

  Theorem containsArray_boundx : forall cs P stn ls st,
    containsArray P ls
    -> interp cs (![P] (stn, st) ---> [| length ls < pow2 32 |]%nat)%PropX.
    rewrite sepFormula_eq; intros; unfold sepFormula_def, fst, snd;
      auto using containsArray_boundx'.
  Qed.

  Hint Resolve containsArray_boundx.

  Theorem containsArray_goodSizex' : forall cs P stn ls st,
    containsArray P ls
    -> interp cs (P stn st ---> [| goodSize (length ls) |])%PropX.
    intros; unfold goodSize.
    eapply Imply_trans.
    eapply containsArray_boundx'; eauto.
    apply inj_imply; intro.
    apply Nlt_in.
    rewrite Npow2_nat.
    rewrite Nat2N.id.
    assumption.
  Qed.

  Theorem containsArray_goodSizex : forall cs P stn ls st,
    containsArray P ls
    -> interp cs (![P] (stn, st) ---> [| goodSize (length ls) |])%PropX.
    intros; unfold goodSize.
    eapply Imply_trans.
    eapply containsArray_boundx; eauto.
    apply inj_imply; intro.
    apply Nlt_in.
    rewrite Npow2_nat.
    rewrite Nat2N.id.
    assumption.
  Qed.

  Hint Resolve containsArray_goodSizex.

  Theorem unify : forall specs stn st ws V r sp fr ws' V' r' fr',
    interp specs (![array ws (sel V stream) * locals ("rp" :: ns) V r sp * fr] (stn, st))
    -> sel V size = length ws
    -> In stream ns
    -> In size ns
    -> In pos ns
    -> interp specs (![array ws' (sel V' stream) * locals ("rp" :: ns) V' r' sp * fr'] (stn, st)
       /\ [| sel V' size = length ws' |]
       ---> [| ws' = ws /\ sel V' stream = sel V stream /\ sel V' size = sel V size /\ sel V' pos = sel V pos |])%PropX.
    intros.
    apply Imply_I.
    eapply Inj_E; [ eapply And_E2; apply Env; simpl; eauto | ]; intro.
    eapply Inj_E.
    eapply Imply_E.
    apply interp_weaken; eapply unify_V; eauto.
    eapply And_E1; apply Env; simpl; eauto.
    intro.
    apply Inj_E with (goodSize (length ws')).
    rewrite sepFormula_eq; unfold sepFormula_def, starB, star.
    eapply Exists_E; [ eapply And_E1; apply Env; simpl; eauto | cbv beta; intro ].
    eapply Exists_E; [ apply Env; simpl; left; eauto | cbv beta; intro ].
    eapply Exists_E; [ eapply And_E1; eapply And_E2; apply Env; simpl; left; eauto | cbv beta; intro ].
    eapply Exists_E; [ apply Env; simpl; left; eauto | cbv beta; intro ].
    eapply Imply_E.
    apply interp_weaken; apply containsArray_goodSizex'.
    Focus 2.
    eapply And_E1; eapply And_E2; apply Env; simpl; eauto.
    eauto.
    intro.
    repeat rewrite H6 in * by assumption.
    eapply Inj_E.
    eapply Imply_E.
    apply interp_weaken; eapply unify_ws.
    eassumption.
    2: eapply And_E1; apply Env; simpl; eauto.
    apply natToW_inj; congruence || eauto.
    intro.
    apply Inj_I; intuition.
  Qed.

  Fixpoint spless (is : list instr) : Prop :=
    match is with
      | nil => True
      | Assign (LvReg r) _ :: is' => r <> Sp /\ spless is'
      | Binop (LvReg r) _ _ _ :: is' => r <> Sp /\ spless is'
      | _ :: is' => spless is'
    end.

  Transparent evalInstrs.

  Theorem splessSp : forall stn st' is st,
    spless is
    -> evalInstrs stn st is = Some st'
    -> Regs st' Sp = Regs st Sp.
    induction is as [ | [ [ ] | [ ] ] ]; simpl; intuition; matcher;
      erewrite IHis by eassumption; simpl; try rewrite rupd_ne by auto; auto.
  Qed.

  Theorem splessReads : forall p' offset,
    spless (reads p' offset).
    induction p' as [ | [ ] ]; simpl; intuition.
  Qed.

  Hint Resolve splessReads.

  Opaque evalInstr mult.

  Lemma simplify_reads : forall st' ws r fr stn specs p' offset st V,
    interp specs (![array ws (sel V stream) * locals ("rp" :: ns) V r (Regs st Sp) * fr] (stn, st))
    -> evalInstrs stn st (reads p' offset) = Some st'
    -> (offset + wordToNat (sel V pos) + length p' <= length ws)%nat
    -> patternBound p'
    -> ~In "rp" ns
    -> Regs st Rp = sel V stream ^+ $4 ^* sel V pos
    -> okVarName stream p'
    -> okVarName pos p'
    -> goodSize (offset + wordToNat (sel V pos) + length p')
    -> evalInstrs stn st (map (fun p0 =>
      Assign
      (LvMem (Sp + S (S (S (S (variablePosition ns (fst p0))))))%loc)
      (RvImm (snd p0))) (binds p' (suffix (offset + wordToNat (sel V pos)) ws))) = Some st'.
    clear H; induction p' as [ | [ ] ]; simpl; intuition;
      rewrite suffix_remains by auto;
        change (S (offset + wordToNat (sel V pos))) with (S offset + wordToNat (sel V pos)); eauto; simpl.

    match goal with
      | [ _ : match ?E with None => _ | _ => _ end = _ |- _ ] => case_eq E; intros
    end; match goal with
           | [ H : _ = _ |- _ ] => rewrite H in *
         end; try discriminate.

    destruct (string_dec stream s); try tauto.
    destruct (string_dec pos s); try tauto.
    assert (evalInstrs stn st (Assign (variableSlot s ns) (LvMem (Rp + 4 * offset)%loc) :: nil) = Some s0)
      by (simpl; rewrite H2; reflexivity).
    clear H2.
    replace (evalInstrs stn st
      (Assign (variableSlot s ns)
        (LvMem (Rp + 4 * offset)%loc) :: nil))
      with (evalInstrs stn st
         (Assign (variableSlot s ns)
            (LvMem (Imm (sel V stream ^+ $4 ^* $(offset + wordToNat (sel V pos))))) :: nil)) in H10.
    assert (natToW (offset + wordToNat (sel V pos)) < $(length ws)) by (apply lt_goodSize; eauto).
    prep_locals.
    generalize dependent H0; evaluate auto_ext; intro.
    case_eq (evalInstrs stn s0 (Assign Rv (variableSlot s ns) :: nil)); intros; prep_locals; evaluate auto_ext.
    rewrite sel_upd_eq in H17 by auto.
    unfold evalInstrs in H10, H15.
    repeat (match goal with
              | [ _ : match ?E with None => _ | _ => _ end = _ |- _ ] => case_eq E; intros
            end; match goal with
                   | [ H : _ = _ |- _ ] => rewrite H in *
                 end; try discriminate).
    unfold variablePosition in H19, H20; fold variablePosition in H19, H20.
    destruct (string_dec "rp" s); try congruence.
    simpl in *.
    replace (evalInstr stn st
      (Assign (LvMem (Sp + S (S (S (S (variablePosition ns s)))))%loc)
        (selN ws (offset + wordToNat (sel V pos))))) with (Some s3).
    change (match ws with
              | nil => nil
              | _ :: ws' => suffix (offset + wordToNat (sel V pos)) ws'
            end) with (suffix (S offset + wordToNat (sel V pos)) ws).
    replace (sel V pos) with (sel (upd V s (Array.sel ws (offset + wordToNat (sel V pos)))) pos).
    injection H10; clear H10; intros; subst.
    injection H15; clear H15; intros; subst.
    eapply IHp'.
    rewrite sel_upd_ne by auto.
    apply sepFormula_Mem with s1.
    step auto_ext.
    assert (evalInstrs stn s0
      (Assign Rv (LvMem (Sp + S (S (S (S (variablePosition ns s)))))%loc) :: nil) =
      Some s1).
    simpl; rewrite H19; reflexivity.
    symmetry; eapply scratchOnlyMem; [ | eassumption ].
    simpl; intuition congruence.
    assumption.
    rewrite sel_upd_ne; auto.
    assumption.
    assumption.
    repeat rewrite sel_upd_ne by auto; assumption.
    assumption.
    assumption.
    repeat rewrite sel_upd_ne by auto; eauto.
    repeat rewrite sel_upd_ne by auto; reflexivity.
    rewrite <- H20.
    
    injection H15; clear H15; intros; subst.
    injection H10; clear H10; intros; subst.
    assert (evalInstrs stn s0
      (Assign Rv (LvMem (Sp + S (S (S (S (variablePosition ns s)))))%loc) :: nil) =
      Some s1) by (simpl; rewrite H19; reflexivity).
    eapply sepFormula_Mem in H18.
    2: symmetry; eapply scratchOnlyMem; eauto; simpl; intuition.
    change (S (S (S (S (variablePosition ns s))))) with (4 + variablePosition ns s) in *.
    prep_locals.
    evaluate auto_ext.
    rewrite sel_upd_eq in H22 by auto.
    unfold Array.sel in H22.
    unfold natToW in H22; rewrite wordToNat_natToWord_idempotent in H22.
    generalize H19 H20 H22; clear; intros.
    Transparent evalInstr.

    Lemma evalAssign_rhs : forall stn st lv rv rv',
      evalRvalue stn st rv = evalRvalue stn st rv'
      -> evalInstr stn st (Assign lv rv) = evalInstr stn st (Assign lv rv').
      simpl; intros.
      rewrite H0; reflexivity.
    Qed.

    apply evalAssign_rhs.
    simpl.
    unfold evalInstr, evalRvalue, evalLvalue, evalLoc in *.

    match goal with
      | [ _ : context[match ?E with None => _ | _ => _ end] |- _ ] =>
        match E with
          | context[match _ with None => _ | _ => _ end] => fail 1
          | _ => destruct E; try discriminate
        end
    end.
    match goal with
      | [ _ : context[match ?E with None => _ | _ => _ end] |- _ ] =>
        match E with
          | context[match _ with None => _ | _ => _ end] => fail 1
          | _ => case_eq E; intros; match goal with
                                      | [ H : _ = _ |- _ ] => rewrite H in *
                                    end; try discriminate
        end
    end.
    injection H20; clear H20; intros; subst; simpl Regs in *; simpl Mem in *.
    match goal with
      | [ _ : context[match ?E with None => _ | _ => _ end] |- _ ] =>
        match E with
          | context[match _ with None => _ | _ => _ end] => fail 1
          | _ => case_eq E; intros; match goal with
                                      | [ H : _ = _ |- _ ] => rewrite H in *
                                    end; try discriminate
        end
    end.
    injection H19; clear H19; intros; subst; simpl Mem in *; simpl Regs in *.
    eapply ReadWriteEq in H.
    rewrite H in H0.
    rewrite <- H22.
    unfold rupd; simpl.
    assumption.

    change (goodSize (offset + wordToNat (sel V pos))); eauto.

    generalize H4; clear; intros.
    simpl.
    rewrite H4.
    match goal with
      | [ |- match match ?E1 with None => _ | _ => _ end with None => _ | _ => _ end
        = match match ?E2 with None => _ | _ => _ end with None => _ | _ => _ end ] =>
      replace E2 with E1; auto
    end.
    f_equal.
    rewrite natToW_plus.
    rewrite mult_comm; rewrite natToW_times4.
    unfold natToW; rewrite natToWord_wordToNat.
    W_eq.
  Qed.

  Opaque evalInstrs.

  Theorem spless_app : forall is1 is2,
    spless is1
    -> spless is2
    -> spless (is1 ++ is2).
    induction is1 as [ | [ ] ]; simpl; intuition;
      destruct l; intuition.
  Qed.

  Lemma Rv_preserve : forall rv posV len,
    rv = posV ^+ $(len)
    -> rv = natToW (0 + wordToNat posV + len).
    simpl; intros; subst.
    rewrite natToW_plus.
    f_equal.
    symmetry; apply natToWord_wordToNat.
  Qed.

  Lemma guard_says_safe : forall stn st specs V ws r fr,
    bexpTrue (guard p 0) stn st
    -> Regs st Rv = sel V pos ^+ $(length p)
    -> interp specs (![array ws (sel V stream) * locals ("rp" :: ns) V r (Regs st Sp) * fr] (stn, st))
    -> In size ns
    -> ~In "rp" ns
    -> sel V size = $(length ws)
    -> goodSize (wordToNat (sel V pos) + Datatypes.length p)
    -> (0 + wordToNat (sel V pos) + length p <= length ws)%nat.
    simpl; intros.
    apply wle_goodSize.
    rewrite natToW_plus.
    unfold natToW; rewrite natToWord_wordToNat.
    rewrite <- H1.
    rewrite <- H5.
    eapply bexpTrue_bound; eauto.
    eauto.
    eauto.
  Qed.

  Ltac clear_fancy := try clear H;
    repeat match goal with
             | [ H : vcs _ |- _ ] => clear H
           end.

  Ltac wrap :=
    intros;
      repeat match goal with
               | [ H : vcs nil |- _ ] => clear H
               | [ H : vcs (_ :: _) |- _ ] => inversion H; clear H; intros; subst
               | [ H : vcs (_ ++ _) |- _ ] => specialize (vcs_app_bwd1 _ _ H);
                 specialize (vcs_app_bwd2 _ _ H); clear H; intros
             end; simpl;
      repeat match goal with
               | [ |- vcs nil ] => constructor
               | [ |- vcs (_ :: _) ] => constructor
               | [ |- vcs (_ ++ _) ] => apply vcs_app_fwd
             end; propxFo;
    try match goal with
          | [ H : forall stn : settings, _, H' : interp _ _ |- _ ] =>
            specialize (H _ _ _ H')
        end; post; prep_locals; auto; clear_fancy.

  Opaque variablePosition.

  Hint Extern 2 (interp ?specs2 (![ _ ] (?stn2, ?st2))) =>
    match goal with
      | [ _ : interp ?specs1 (![ _ ] (?stn1, ?st1)) |- _ ] =>
        solve [ equate specs1 specs2; equate stn1 stn2; equate st1 st2; step auto_ext ]
    end.

  Hint Resolve Rv_preserve bexpSafe_guard guard_says_safe evalInstrs_app sepFormula_Mem
    bexpFalse_not_matches simplify_reads.
  Hint Extern 1 (Mem _ = Mem _) =>
    eapply scratchOnlyMem; [ | eassumption ];
      simpl; intuition congruence.
  Hint Extern 1 (Mem _ = Mem _) =>
    symmetry; eapply scratchOnlyMem; [ | eassumption ];
      simpl; intuition congruence.
  Hint Immediate sym_eq.


  Definition Parse1 : cmd imports modName.
    refine (Wrap _ H _ Parse1_
      (fun pre =>
        In stream ns
        :: In size ns
        :: In pos ns
        :: (~In "rp" ns)
        :: patternBound p
        :: okVarName stream p
        :: okVarName pos p
        :: (forall stn st specs,
          interp specs (pre (stn, st))
          -> interp specs (ExX, Ex V, Ex ws, Ex r,
            ![ ^[array ws (sel V stream) * locals ("rp" :: ns) V r (Regs st Sp)] * #0] (stn, st)
            /\ [| sel V size = length ws
              /\ goodSize (wordToNat (sel V pos) + length p)
              /\ (wordToNat (sel V pos) <= length ws)%nat |]))%PropX
        :: VerifCond (Then (ThenPre pre))
        ++ VerifCond (Else (ElsePre pre)))
      _); abstract (wrap;
        try match goal with
              | [ H : context[reads] |- _ ] => generalize dependent H
            end; evaluate auto_ext; intros; eauto;
        repeat match goal with
                 | [ H : evalInstrs _ _ (_ ++ _) = None |- _ ] =>
                   apply evalInstrs_app_fwd_None in H; destruct H as [ | [ ? [ ? ] ] ]; intuition
                 | [ H : evalInstrs _ _ (_ ++ _) = Some _ |- _ ] =>
                   apply evalInstrs_app_fwd in H; destruct H as [ ? [ ] ]
                 | [ H : evalInstrs _ _ (reads _ _) = Some _ |- _ ] =>
                   edestruct (reads_exec _ _ H) as [V' [ ] ]; eauto; evaluate auto_ext
               end;
        try match goal with
              | [ |- exists x, _ /\ _ ] => eexists; split; [ solve [ eauto ] | split; intros ];
                try (autorewrite with sepFormula; simpl; eapply Imply_trans; [
                  eapply unify; eauto
                  | apply inj_imply; intuition; subst; simpl in * ] )
              | _ => solve [ eapply reads_nocrash; eauto ]
            end;
        repeat match goal with
                 | _ => solve [ eauto ]
                 | [ H : _ = _ |- _ ] => rewrite H in *
                 | [ |- context[suffix ?N _] ] =>
                   match N with
                     | 0 + _ => fail 1
                     | _ =>
                       change N with (0 + N)
                   end
                 | [ H : matches ?a (suffix ?b ?c) |- False ] =>
                   assert (~matches a (suffix (0 + b) c)); try tauto; clear H
                 | [ _ : evalInstrs _ ?x (reads _ _) = Some _ |- _ ] => exists x; split; eauto
                 | _ => solve [ eapply bexpTrue_matches; eauto ]
               end).
  Defined.

End Parse.
