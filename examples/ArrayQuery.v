Require Import PreAutoSep Wrap Conditional.

Import DefineStructured.

Set Implicit Arguments.


(** Test expressions over arrays *)

Inductive exp :=
| Const (w : W)
(* Literal word value *)
| Index
(* Position in the array *)
| Value
(* Content of array cell *)
| Var (x : string)
(* Injected value of Bedrock local variable *).

Inductive condition :=
| Test (e1 : exp) (t : test) (e2 : exp)
(* Basic comparison *)
| Not (c1 : condition)
| And (c1 c2 : condition)
| Or (c1 c2 : condition)
(* Boolean operators *).

Coercion Const : W >-> exp.
Coercion Var : string >-> exp.

Notation "x = y" := (Test x IL.Eq y) : ArrayQuery_scope.
Notation "x <> y" := (Test x IL.Ne y) : ArrayQuery_scope.
Notation "x < y" := (Test x IL.Lt y) : ArrayQuery_scope.
Notation "x <= y" := (Test x IL.Le y) : ArrayQuery_scope.
Notation "x > y" := (Test y IL.Lt x) : ArrayQuery_scope.
Notation "x >= y" := (Test y IL.Le x) : ArrayQuery_scope.

Notation "!" := Not : ArrayQuery_scope.
Infix "&&" := And : ArrayQuery_scope.
Infix "||" := Or : ArrayQuery_scope.

Delimit Scope ArrayQuery_scope with ArrayQuery.

Definition eval (vs : vals) (index value : W) (e : exp) : W :=
  match e with
    | Const w => w
    | Index => index
    | Value => value
    | Var x => sel vs x
  end.

Fixpoint satisfies (vs : vals) (index value : W) (c : condition) : Prop :=
  match c with
    | Test e1 t e2 => (evalTest t) (eval vs index value e1) (eval vs index value e2) = true
    | Not c1 => ~satisfies vs index value c1
    | And c1 c2 => satisfies vs index value c1 /\ satisfies vs index value c2
    | Or c1 c2 => satisfies vs index value c1 \/ satisfies vs index value c2
  end.

Section Query.
  Variable arr : string.
  (* Name of local variable containing an array to query *)
  Variable size : string.
  (* Name of local variable containing the array length in words *)
  Variable index : string.
  (* Name of local variable that, inside the loop, is assigned the current array index *)
  Variable value : string.
  (* Name of local variable that, inside the loop, is assigned the current array cell value *)

  Variable c : condition.
  (* We will loop over only those indices satisfying this condition. *)

  Variable imports : LabelMap.t assert.
  Hypothesis H : importsGlobal imports.
  Variable modName : string.

  Variable invPre : list W -> vals -> qspec.
  (* Precondition part of loop invariant, parameterized over part of array visited already *)

  Variable invPost : list W -> vals -> W -> qspec.
  (* Postcondition part of loop invariant, parameterized over whole array *)

  Variables Body : cmd imports modName.
  (* Code to run on each matching array index *)

  Variable ns : list string.
  (* Local variable names *)
  Variable res : nat.
  (* Reserved stack slots *)

  Definition loopInvariant : assert :=
    st ~> ExX, Ex wsPre, Ex vs, qspecOut (invPre wsPre (sel vs)) (fun PR =>
      Ex ws, ![ ^[locals ("rp" :: ns) vs res st#Sp * array ws (sel vs arr) * PR] * #0 ] st
      /\ [| sel vs size = length ws /\ sel vs index = length wsPre |]
      /\ Ex wsPost, [| ws = wsPre ++ wsPost |]
      /\ sel vs "rp" @@ (st' ~>
        [| st'#Sp = st#Sp |]
        /\ Ex vs', qspecOut (invPost ws (sel vs) st'#Rv) (fun PO =>
          ![ ^[locals ("rp" :: ns) vs' res st#Sp * array ws (sel vs arr) * PO] * #1 ] st'))).

  Definition bodyPre : assert :=
    st ~> Ex wsPre, ExX, Ex vs, qspecOut (invPre wsPre (sel vs)) (fun PR =>
      Ex ws, ![ ^[locals ("rp" :: ns) vs res st#Sp * array ws (sel vs arr) * PR] * #0 ] st
      /\ [| sel vs size = length ws /\ sel vs index = length wsPre
        /\ satisfies vs (sel vs index) (sel vs value) c |]
      /\ Ex wsPost, [| ws = wsPre ++ sel vs value :: wsPost |]
      /\ sel vs "rp" @@ (st' ~>
        [| st'#Sp = st#Sp |]
        /\ Ex vs', qspecOut (invPost ws (sel vs) st'#Rv) (fun PO =>
          ![ ^[locals ("rp" :: ns) vs' res st#Sp * array ws (sel vs arr) * PO] * #1 ] st'))).

  Definition expBound (e : exp) : Prop :=
    match e with
      | Const _ => True
      | Index => True
      | Value => True
      | Var x => In x ns /\ x <> value /\ x <> index
    end.

  Fixpoint conditionBound (c : condition) : Prop :=
    match c with
      | Test e1 _ e2 => expBound e1 /\ expBound e2
      | Not c1 => conditionBound c1
      | And c1 c2 => conditionBound c1 /\ conditionBound c2
      | Or c1 c2 => conditionBound c1 /\ conditionBound c2
    end.

  Definition expOut (e : exp) : rvalue :=
    match e with
      | Const w => w
      | Index => variableSlot index ns
      | Value => variableSlot value ns
      | Var x => variableSlot x ns
    end.

  Fixpoint conditionOut (c : condition) : bexp :=
    match c with
      | Test e1 t e2 => Conditional.Test (expOut e1) t (expOut e2)
      | Not c1 => Conditional.Not (conditionOut c1)
      | And c1 c2 => Conditional.And (conditionOut c1) (conditionOut c2)
      | Or c1 c2 => Conditional.Or (conditionOut c1) (conditionOut c2)
    end.

  Fixpoint indexEquals (c : condition) : option string :=
    match c with
      | Test Index IL.Eq (Var s) => Some s
      | Test _ _ _ => None
      | Not _ => None
      | And c1 c2 => match indexEquals c1 with
                       | None => indexEquals c2
                       | v => v
                     end
      | Or _ _ => None
    end.

  (* Here's the raw command, which we will later wrap with nicer VCs. *)
  Definition Query_ : cmd imports modName :=
    match indexEquals c with
      | None =>
        Seq_ H
        (Straightline_ _ _ (Assign (variableSlot index ns) 0 :: nil))
        (Structured.While_ H loopInvariant (variableSlot index ns) IL.Lt (variableSlot size ns)
          (Seq_ H
            (Straightline_ _ _ (
              Binop Rv 4 Times (variableSlot index ns)
              :: Binop Rv (variableSlot arr ns) Plus Rv
              :: Assign (variableSlot value ns) (LvMem (Reg Rv))
              :: nil))
            (Seq_ H
              (Cond_ _ H _ (conditionOut c)
                (Seq_ H
                  (Structured.Assert_ _ _ bodyPre)
                  Body)
                (Skip_ _ _))
              (Straightline_ _ _ (Binop (variableSlot index ns) (variableSlot index ns) Plus 1 :: nil)))))
      | Some b =>
        Structured.If_ H (variableSlot b ns) IL.Lt (variableSlot size ns)
        (Seq_ H
          (Straightline_ _ _ (
            Binop Rv 4 Times (variableSlot b ns)
            :: Binop Rv (variableSlot arr ns) Plus Rv
            :: Assign (variableSlot value ns) (LvMem (Reg Rv))
            :: Assign (variableSlot index ns) (variableSlot b ns)
            :: nil))
          (Cond_ _ H _ (conditionOut c)
            (Seq_ H
              (Structured.Assert_ _ _ bodyPre)
              Body)
            (Skip_ _ _)))
        (Skip_ _ _)
    end.

  Ltac wrap := wrap0; post; wrap1.

  Hint Resolve simplify_fwd.

  Lemma subst_qspecOut_fwd : forall pc state (specs : codeSpec pc state) A v qs (k : _ -> propX _ _ (A :: nil)),
    interp specs (subst (qspecOut qs k) v)
    -> interp specs (qspecOut qs (fun x => subst (k x) v)).
    induction qs; propxFo; eauto.
  Qed.

  Lemma subst_qspecOut_bwd : forall pc state (specs : codeSpec pc state) A v qs (k : _ -> propX _ _ (A :: nil)),
    interp specs (qspecOut qs (fun x => subst (k x) v))
    -> interp specs (subst (qspecOut qs k) v).
    induction qs; propxFo; eauto.
  Qed.

  Fixpoint domain (qs : qspec) : Type :=
    match qs with
      | Programming.Body _ => unit
      | Quant _ f => sigT (fun x => domain (f x))
    end.

  Fixpoint qspecOut' (qs : qspec) : domain qs -> HProp :=
    match qs with
      | Programming.Body P => fun _ => P
      | Quant _ f => fun d => qspecOut' (f (projT1 d)) (projT2 d)
    end.

  Lemma qspecOut_fwd : forall (specs : codeSpec W (settings * state)) qs k,
    interp specs (qspecOut qs k)
    -> exists v : domain qs, interp specs (k (qspecOut' qs v)).
    induction qs; simpl; propxFo.
    exists tt; auto.
    apply H0 in H1; destruct H1.
    exists (existT _ x x0); eauto.
  Qed.

  Lemma qspecOut_bwd : forall (specs : codeSpec W (settings * state)) qs k v,
    interp specs (k (qspecOut' qs v))
    -> interp specs (qspecOut qs k).
    induction qs; simpl; propxFo; eauto.
  Qed.

  Lemma must_be_nil : forall (ind sz : W) (ws1 ws2 : list W),
    sz <= ind
    -> ind = length ws1
    -> sz = length (ws1 ++ ws2)
    -> goodSize (length (ws1 ++ ws2))
    -> ws2 = nil.
    intros; subst; rewrite app_length in *;
      match goal with
        | [ H : _ |- _ ] => eapply wle_goodSize in H; eauto
      end; destruct ws2; simpl in *; auto; omega.
  Qed.

  Hint Extern 1 (_ = _) => eapply must_be_nil; solve [ eauto ].

  Lemma length_app_nil : forall (w : W) A (ls : list A),
    w = length (ls ++ nil)
    -> w = length ls.
    intros; rewrite app_length in *; simpl in *; subst; auto.
  Qed.

  Hint Immediate length_app_nil.

  Hint Extern 1 (interp _ (_ ---> _)%PropX) => apply Imply_refl.

  Theorem double_sel : forall V x,
    sel (sel V) x = sel V x.
    reflexivity.
  Qed.

  Hint Rewrite double_sel sel_upd_eq sel_upd_ne using congruence : Locals.

  Ltac locals := intros; autorewrite with Locals; reflexivity.

  Hint Rewrite app_length natToW_plus DepList.pf_list_simpl : sepFormula.

  Lemma goodSize_middle : forall (pre : list W) mid post,
    goodSize (length (pre ++ mid :: post))
    -> goodSize (length pre).
    intros; autorewrite with sepFormula in *; simpl in *; eauto.
  Qed.

  Hint Extern 1 (goodSize (length _)) => eapply goodSize_middle;
    eapply containsArray_goodSize; [ eassumption | eauto ].

  Hint Rewrite sel_middle using solve [ eauto ] : sepFormula.

  Lemma condition_safe : forall specs V fr stn st,
    interp specs (![locals ("rp" :: ns) V res (Regs st Sp) * fr] (stn, st))
    -> In index ns
    -> In value ns
    -> ~In "rp" ns
    -> forall c', conditionBound c'
      -> bexpSafe (conditionOut c') stn st.
    clear_fancy; induction c'; simpl; intuition;
      match goal with
        | [ _ : evalCond (expOut ?e1) _ (expOut ?e2) _ _ = None |- _ ] =>
          destruct e1; destruct e2; (simpl in *; intuition idtac; prep_locals; evaluate auto_ext)
      end.
  Qed.

  Hint Resolve condition_safe.

  Hint Extern 1 (weqb _ _ = true) => apply weqb_true_iff.

  Lemma wneb_true : forall w1 w2,
    w1 <> w2
    -> wneb w1 w2 = true.
    unfold wneb; intros; destruct (weq w1 w2); auto.
  Qed.

  Lemma wltb_true : forall w1 w2,
    w1 < w2
    -> wltb w1 w2 = true.
    unfold wltb; intros; destruct (wlt_dec w1 w2); auto.
  Qed.

  Lemma wleb_true : forall w1 w2,
    w1 <= w2
    -> wleb w1 w2 = true.
    unfold wleb; intros; destruct (weq w1 w2); destruct (wlt_dec w1 w2); auto.
    elimtype False; apply n.
    assert (wordToNat w1 = wordToNat w2) by nomega.
    apply (f_equal (fun w => natToWord 32 w)) in H1.
    repeat rewrite natToWord_wordToNat in H1.
    assumption.
  Qed.

  Hint Resolve wneb_true wltb_true wleb_true.

  Lemma bool_one : forall b,
    b = true
    -> b = false
    -> False.
    intros; congruence.
  Qed.

  Lemma weqb_false : forall w1 w2,
    w1 <> w2
    -> weqb w1 w2 = false.
    unfold weqb; intros; generalize (weqb_true_iff w1 w2); destruct (Word.weqb w1 w2); intuition.
  Qed.

  Lemma wneb_false : forall w1 w2,
    w1 = w2
    -> wneb w1 w2 = false.
    unfold wneb; intros; destruct (weq w1 w2); intuition.
  Qed.

  Lemma wltb_false : forall w1 w2,
    w2 <= w1
    -> wltb w1 w2 = false.
    unfold wltb; intros; destruct (wlt_dec w1 w2); intuition.
  Qed.

  Lemma wleb_false : forall w1 w2,
    w2 < w1
    -> wleb w1 w2 = false.
    unfold wleb; intros; destruct (weq w1 w2); destruct (wlt_dec w1 w2); intuition; nomega.
  Qed.

  Hint Resolve weqb_false wneb_false wltb_false wleb_false.

  Lemma condition_satisfies' : forall specs V fr stn st,
    interp specs (![locals ("rp" :: ns) V res (Regs st Sp) * fr] (stn, st))
    -> In index ns
    -> In value ns
    -> ~In "rp" ns
    -> forall c', conditionBound c'
      -> (bexpTrue (conditionOut c') stn st -> satisfies V (sel V index) (sel V value) c')
      /\ (bexpFalse (conditionOut c') stn st -> ~satisfies V (sel V index) (sel V value) c').
    clear_fancy; induction c'; simpl; intuition;
      try (eapply bool_one; [ eassumption | ]);
        match goal with
          | [ _ : evalCond (expOut ?e1) ?t (expOut ?e2) _ _ = _ |- _ ] =>
            destruct e1; destruct t; destruct e2;
              (simpl in *; intuition idtac; prep_locals; evaluate auto_ext; auto)
        end.
  Qed.

  Lemma condition_satisfies : forall specs V fr stn st ind val,
    interp specs (![locals ("rp" :: ns) V res (Regs st Sp) * fr] (stn, st))
    -> In index ns
    -> In value ns
    -> ~In "rp" ns
    -> sel V index = ind
    -> sel V value = val
    -> forall c', conditionBound c'
      -> bexpTrue (conditionOut c') stn st
      -> satisfies V ind val c'.
    intros; subst; edestruct condition_satisfies'; eauto.
  Qed.

  Lemma condition_not_satisfies : forall specs V fr stn st ind val,
    interp specs (![locals ("rp" :: ns) V res (Regs st Sp) * fr] (stn, st))
    -> In index ns
    -> In value ns
    -> ~In "rp" ns
    -> sel V index = ind
    -> sel V value = val
    -> forall c', conditionBound c'
      -> bexpFalse (conditionOut c') stn st
      -> ~satisfies V ind val c'.
    intros; subst; edestruct condition_satisfies'; eauto.
  Qed.

  Fixpoint noMatches (V : vals) (ws : list W) (index : nat) : Prop :=
    match ws with
      | nil => True
      | w :: ws' => ~satisfies V index w c /\ noMatches V ws' (index + 1)
    end.

  Hint Rewrite app_nil_r : sepFormula.

  Lemma invPre_skip : (forall specs stn st V ws this v fr,
    ~satisfies V (length ws) this c
    -> interp specs (![qspecOut' (invPre ws (sel V)) v * fr] (stn, st))
    -> exists v', interp specs (![qspecOut' (invPre (ws ++ this :: nil) (sel V)) v' * fr] (stn, st)))
  -> forall specs V fr stn st ws' ws v,
    interp specs (![qspecOut' (invPre ws V) v * fr] (stn, st))
    -> noMatches V ws' (length ws)
    -> exists v', interp specs (![qspecOut' (invPre (ws ++ ws') V) v' * fr] (stn, st)).
    induction ws'; simpl; intuition; autorewrite with sepFormula; eauto.

    eapply H0 in H3; [ | eauto ].
    post.
    apply IHws' in H2; [ | post; auto ].
    autorewrite with sepFormula in *; auto.
  Qed.

  Hint Resolve natToW_inj.

  Ltac indexEquals :=
    repeat match goal with
             | [ _ : match ?E with None => _ | _ => _ end = _ |- _ ] => destruct E; try discriminate
             | [ _ : match ?E with Const _ => _ | _ => _ end = _ |- _ ] => destruct E; try discriminate
             | [ _ : match ?E with IL.Eq => _ | _ => _ end = _ |- _ ] => destruct E; try discriminate
             | [ H : Some _ = Some _ |- _ ] => injection H; clear H; intros; subst; simpl in *
             | [ H : weqb _ _ = true |- _ ] => apply weqb_true_iff in H
           end.

  Lemma indexEquals_correct : forall k V (len : nat) val c',
    indexEquals c' = Some k
    -> satisfies V len val c'
    -> goodSize len
    -> (forall len' val', goodSize len' -> len <> len' -> ~satisfies V len' val' c').
    induction c'; simpl; intuition; indexEquals; intuition (subst; eauto);
      match goal with
        | [ H : _ -> False |- _ ] => apply H; apply natToW_inj; auto; congruence
      end.
  Qed.

  Lemma notSatisfies_noMatches' : forall V ws index,
    (forall (index' : nat) val, goodSize index' -> satisfies V index' val c
      -> (index <= index' < index + length ws)%nat -> False)
    -> goodSize (index + length ws)
    -> noMatches V ws index.
    induction ws; simpl; intuition eauto.
    eapply IHws; intros.
    eauto.
    Require Import Arith.
    rewrite <- plus_assoc.
    auto.
  Qed.

  Lemma notSatisfies_noMatches : forall V ws index,
    (forall (index' : nat) val, goodSize index' -> (index <= index' < index + length ws)%nat
      -> ~satisfies V index' val c)
    -> goodSize (index + length ws)
    -> noMatches V ws index.
    intuition; eapply notSatisfies_noMatches'; eauto.
  Qed.

  Lemma goodSize_middle' : forall (ls1 : list W) x ls2,
    goodSize (length (ls1 ++ x :: ls2))
    -> goodSize (length (ls1 ++ x :: nil) + length ls2).
    intros; autorewrite with sepFormula in *; simpl in *; rewrite <- plus_assoc; auto.
  Qed.

  Hint Resolve goodSize_middle'.

  Hint Extern 1 (~(@eq nat _ _)) => omega.

  Lemma indexEquals_bound : forall x c',
    indexEquals c' = Some x
    -> conditionBound c'
    -> In x ns.
    induction c'; simpl; intuition; indexEquals; tauto.
  Qed.

  Lemma indexEquals_correct' : forall k V c',
    indexEquals c' = Some k
    -> (forall len' val', goodSize len' -> sel V k <> len' -> ~satisfies V len' val' c').
    induction c'; simpl; intuition; indexEquals; intuition (subst; eauto).
  Qed.
  

  Ltac depropx H := apply simplify_fwd in H; simpl in H;
    repeat match goal with
             | [ H : Logic.ex ?P |- _ ] => destruct H;
               try match goal with
                     | [ H : Logic.ex P |- _ ] => clear H
                   end
             | [ H : _ /\ _ |- _ ] => destruct H
           end.

  Ltac begin0 :=
    match goal with
      | [ x : (settings * state)%type |- _ ] => destruct x; unfold fst, snd in *
      | [ H : forall x y z, _, H' : interp _ _ |- _ ] =>
        specialize (H _ _ _ H')
      | [ H : interp _ _ |- _ ] =>
        (apply subst_qspecOut_fwd in H; simpl in H)
        || (apply qspecOut_fwd in H; simpl in H; autorewrite with sepFormula in H; simpl in H; destruct H)
      | [ H : interp _ (Ex x, _) |- _ ] => depropx H
      | [ H : interp _ (ExX, _) |- _ ] => depropx H
      | [ H : simplify _ _ _ |- _ ] =>
        (apply simplify_bwd in H || (apply simplify_bwd' in H; unfold Substs in H);
          simpl in H; autorewrite with sepFormula in H; simpl in H)
    end.

  Ltac locals_rewrite :=
    repeat match goal with
             | [ H : _ = _ |- _ ] => rewrite H
             | [ |- context[sel (upd ?V ?x ?v) ?y] ] =>
               rewrite (@sel_upd_ne V x v y) by congruence
             | [ |- context[sel (upd ?V ?x ?v) ?y] ] =>
               rewrite (@sel_upd_eq V x v y) by congruence
           end.

  Ltac finish0 := eauto; progress (try rewrite app_nil_r in *; descend; autorewrite with sepFormula;
    repeat match goal with
             | [ H : _ = _ |- _ ] => rewrite H
             | [ |- specs (sel (upd _ ?x _) ?y) = Some _ ] => assert (y <> x) by congruence
             | [ |- appcontext[invPost _ ?V] ] => (has_evar V; fail 2) ||
               match goal with
                 | [ |- appcontext[invPost _ ?V'] ] =>
                   match V' with
                     | V => fail 1
                     | _ => match goal with
                              | [ H : forall (_ : list W) (V : vals), _ |- _ ] => rewrite (H _ V V') by locals
                            end
                   end
               end
           end;
    try match goal with
          | [ |- satisfies _ _ _ _ ] => eapply condition_satisfies; solve [ finish0 ]
          | [ |- interp _ (subst _ _) ] => apply subst_qspecOut_bwd; eapply qspecOut_bwd; propxFo
          | _ => step auto_ext
        end).

  Ltac begin := repeat begin0;
    try match goal with
          | [ _ : bexpFalse _ _ _, H : evalInstrs _ _ (Binop _ _ Plus _ :: nil) = Some _ |- _ ] =>
            generalize dependent H
        end;
    evaluate auto_ext; intros; subst;
      try match goal with
            | [ _ : sel _ size = natToW (length (_ ++ ?ws)) |- _ ] => assert (ws = nil) by auto; subst
            | [ v : domain (invPre nil (sel ?V)), H : forall ws : list W, _ |- _ ] =>
              generalize dependent v; rewrite (H nil (sel V) (sel (upd V index 0))) by locals;
                intros; eexists; exists nil
            | [ v : domain (invPre (?x ++ ?l :: nil) (sel ?V)), H : forall ws : list W, _ |- _ ] =>
              generalize dependent v; rewrite (H (x ++ l :: nil) (sel V) (sel (upd V index (sel V index ^+ $1))))
                by locals; intros; eexists; exists (x ++ l :: nil)
            | [ _ : bexpTrue _ _ _, v : domain (invPre ?l (sel ?V)), H : forall ws : list W, _,
                _ : _ = natToW (length (?wPre ++ ?wPost)) |- _ ] =>
              generalize dependent v; rewrite (H _ _ (upd V value (Array.sel (wPre ++ wPost)
                (sel V index)))) by locals; intros;
              destruct wPost; [ rewrite app_nil_r in *;
                repeat match goal with
                         | [ H : _ = _ |- _ ] => rewrite H in *
                       end; nomega
                | ];
              match goal with
                | [ H : context[v] |- _ ] => generalize v H
              end; locals_rewrite; rewrite sel_middle by eauto; intro v'; intros; do 3 eexists;
              apply simplify_fwd'; unfold Substs; apply subst_qspecOut_bwd; apply qspecOut_bwd with v'
            | [ Hf : bexpFalse (conditionOut c) _ _, _ : evalInstrs _ _ (Binop _ _ Plus _ :: nil) = Some _,
                v : domain (invPre ?l (sel ?V)), H : forall ws : list W, _,
                _ : context[Array.sel (?wPre ++ ?wPost) ?u], _ : _ = natToW (length ?L) |- _ ] =>
              let Hf' := fresh in
              match goal with
                | [ _ : context[locals _ ?V' _ _] |- _ ] =>
                  assert (Hf' : ~satisfies V' (length L) (sel V' value) c)
                    by (eapply condition_not_satisfies; finish0)
              end; clear Hf; rename Hf' into Hf;
              generalize dependent v; rewrite (H _ _ (upd V value (Array.sel (wPre ++ wPost) u))) by locals;
                intros;
                  match goal with
                    | [ H' : forall specs : codeSpec _ _, _ |- _ ] =>
                      change (forall specs stn st V ws this v fr,
                        ~satisfies V (Datatypes.length ws) this c
                        -> interp specs (![qspecOut' (invPre ws V) v * fr] (stn, st))
                        -> exists v', interp specs (![qspecOut' (invPre (ws ++ this :: nil) V) v' * fr] (stn, st))) in H';
                      eapply H' in Hf; [ |
                        match goal with
                          | [ |- context[qspecOut' _ ?v'] ] => equate v v'
                        end; eauto ]
                  end; rewrite (H _ _ (upd
                    (upd V value (Array.sel (wPre ++ wPost) u)) index
                    (sel (upd V value (Array.sel (wPre ++ wPost) u)) index ^+ $1)))
                  in Hf by locals;
                  intros; eexists;
                    exists (wPre ++ Array.sel (wPre ++ wPost) u :: nil);
                      exists (upd (upd V value (Array.sel (wPre ++ wPost) u)) index
                        (sel (upd V value (Array.sel (wPre ++ wPost) u))
                          index ^+ $1));
                      destruct wPost; [ rewrite app_nil_r in *;
                        repeat match goal with
                                 | [ H : _ = _ |- _ ] => rewrite H in *
                               end; nomega
                        | ];
                      repeat match goal with
                               | [ H : interp _ _ |- _ ] => clear H
                             end; destruct Hf as [v']; evaluate auto_ext;
                      apply simplify_fwd'; unfold Substs; apply subst_qspecOut_bwd;
                        generalize dependent v'; locals_rewrite; intros; apply qspecOut_bwd with v'
          end.

  Ltac finish := repeat finish0.

  Ltac t := begin; finish.

  Definition Query : cmd imports modName.
    refine (Wrap _ H _ Query_
      (fun _ st => Ex ws, ExX, Ex V, qspecOut (invPre ws (sel V)) (fun PR =>
        ![ ^[locals ("rp" :: ns) V res st#Sp * array ws (sel V arr) * PR] * #0 ] st
        /\ [| sel V size = length ws |]
        /\ sel V "rp" @@ (st' ~>
          [| st'#Sp = st#Sp |]
          /\ Ex V', qspecOut (invPost ws (sel V) st'#Rv) (fun PO =>
            ![ ^[locals ("rp" :: ns) V' res st#Sp * array ws (sel V arr) * PO] * #1 ] st'))))%PropX
      (fun pre =>
        (* Basic hygiene requirements *)
        In arr ns
        :: In size ns
        :: In index ns
        :: In value ns
        :: (~In "rp" ns)
        :: (~(index = arr))
        :: (~(size = index))
        :: (~(value = index))
        :: (~(value = size))
        :: (~(value = arr))
        :: conditionBound c

        (* Invariants are independent of values of some variables. *)
        :: (forall ws V V',
          (forall x, x <> index -> x <> value -> sel V x = sel V' x)
          -> invPre ws V = invPre ws V')
        :: (forall ws V V',
          (forall x, x <> index -> x <> value -> sel V x = sel V' x)
          -> invPost ws V = invPost ws V')

        (* Precondition implies loop invariant. *)
        :: (forall specs stn st, interp specs (pre (stn, st))
          -> interp specs (ExX, Ex V, qspecOut (invPre nil (sel V)) (fun PR =>
            Ex ws, ![ ^[locals ("rp" :: ns) V res (Regs st Sp) * array ws (sel V arr) * PR] * #0 ] (stn, st)
            /\ [| sel V size = length ws |]
            /\ sel V "rp" @@ (st' ~>
              [| st'#Sp = Regs st Sp |]
              /\ Ex V', qspecOut (invPost ws (sel V) st'#Rv) (fun PO =>
                ![ ^[locals ("rp" :: ns) V' res (Regs st Sp) * array ws (sel V arr) * PO] * #1 ] st'))))%PropX)

        (* Loop invariant is preserved on no-op, when the current cell isn't a match. *)
        :: (forall specs stn st V ws this v fr,
          ~satisfies V (length ws) this c
          -> interp specs (![qspecOut' (invPre ws (sel V)) v * fr] (stn, st))
          -> exists v', interp specs (![qspecOut' (invPre (ws ++ this :: nil) (sel V)) v' * fr] (stn, st)))

        (* Postcondition implies loop invariant. *)
        :: (forall specs stn st, interp specs (Postcondition (Body bodyPre) (stn, st))
          -> interp specs (ExX, Ex wsPre, Ex this, Ex V,
            qspecOut (invPre (wsPre ++ this :: nil) (sel V)) (fun PR =>
              Ex ws, ![ ^[locals ("rp" :: ns) V res (Regs st Sp) * array ws (sel V arr) * PR] * #0 ] (stn, st)
              /\ [| sel V size = length ws /\ sel V index = length wsPre /\ satisfies V (length wsPre) this c |]
              /\ Ex wsPost, [| ws = wsPre ++ this :: wsPost |]
              /\ sel V "rp" @@ (st' ~>
                [| st'#Sp = Regs st Sp |]
                /\ Ex V', qspecOut (invPost ws (sel V) st'#Rv) (fun PO =>
                  ![ ^[locals ("rp" :: ns) V' res (Regs st Sp) * array ws (sel V arr) * PO] * #1 ] st'))))%PropX)

        (* Conditions of body are satisfied. *)
        :: VerifCond (Body bodyPre))
      _ _); (unfold Query_; case_eq (indexEquals c); intros).

    wrap.

    begin.
    edestruct invPre_skip.
    assumption.
    instantiate (4 := x3).
    eauto.
    eapply notSatisfies_noMatches; [ | eauto 6 ];
      autorewrite with sepFormula; simpl; intros; eapply indexEquals_correct; (cbv beta; eauto).
    generalize x4 H.
    autorewrite with sepFormula; intros.
    finish.
    
    Focus 2.
    specialize (indexEquals_bound _ H0 H14); intro Hs.
    prep_locals.
    begin.
    autorewrite with Locals in *.
    edestruct invPre_skip.
    assumption.
    instantiate (4 := x1); eauto.
    simpl.
    eapply notSatisfies_noMatches; [ | simpl; eauto ].
    simpl; intros.
    eapply indexEquals_correct'.
    eauto.
    eauto.
    rewrite H21 in H29.
    change (sel (sel x0) s) with (sel x0 s).
    intro.
    apply H29.
    rewrite H27.
    apply lt_goodSize; eauto.
    finish0.
    finish0.
    finish0.
    finish0.

    Lemma indexEquals_value : forall x c',
      indexEquals c' = Some x
      -> conditionBound c'
      -> x <> value.
      induction c'; simpl; intuition; indexEquals; tauto.
    Qed.

    match goal with
      | [ H : indexEquals _ = Some _, H' : conditionBound _ |- _ ] =>
        specialize (indexEquals_bound _ H H'); specialize (indexEquals_value _ H H');
          intros; prep_locals
    end.
    begin.
    edestruct invPre_skip.
    assumption.
    instantiate (4 := x2); eauto.
    simpl.
    instantiate (1 := x3).
    admit.
    generalize dependent x5.
    simpl.
    rewrite (H15 _ _ (sel (upd (upd x1 value (Array.sel x3 (sel x1 s))) index
      (sel (upd x1 value (Array.sel x3 (sel x1 s))) s)))) by locals.
    intros.
    finish0.
    finish0.
    instantiate (2 := x5).
    finish0.
    finish0.
    finish0.
    finish0.
    finish0.
    finish0.


    wrap; t.


    Ltac enrich := match goal with
                     | [ H : indexEquals _ = Some _, H' : conditionBound _ |- _ ] =>
                       specialize (indexEquals_bound _ H H'); specialize (indexEquals_value _ H H');
                         intros; prep_locals
                   end.
    wrap; try enrich.

    t.
    t.
    t.
    
    begin.
    edestruct invPre_skip.
    assumption.
    instantiate (4 := x2); eauto.
    simpl.
    instantiate (1 := firstn (wordToNat (sel x1 s)) x3).
    eapply notSatisfies_noMatches; simpl; rewrite firstn_length; rewrite min_l; intros.
    eapply indexEquals_correct'.
    eauto.
    eauto.
    rewrite H27 in H33.
    change (sel (sel x1) s) with (sel x1 s).
    intro.
    rewrite H36 in *.
    unfold natToW in H35; rewrite wordToNat_natToWord_idempotent in H35 by assumption.
    omega.
    rewrite H27 in *.
    pre_nomega.
    unfold natToW in H33; rewrite wordToNat_natToWord_idempotent in H33.
    omega.
    change (goodSize (length x3)); eauto.
    Focus 2.
    rewrite H27 in *.
    pre_nomega.
    unfold natToW in H33; rewrite wordToNat_natToWord_idempotent in H33.
    omega.
    change (goodSize (length x3)); eauto.
    eauto.

    generalize dependent x5; simpl;
      rewrite (H14 _ _ (sel (upd (upd x1 value (Array.sel x3 (sel x1 s))) index
        (sel (upd x1 value (Array.sel x3 (sel x1 s))) s)))) by locals; intros.
    finish0.
    finish0.
    fold (@firstn W).
    instantiate (2 := x5).
    finish0.
    finish0.
    finish0.
    finish0.
    rewrite firstn_length; rewrite min_l.
    unfold natToW; rewrite natToWord_wordToNat; reflexivity.
    rewrite H27 in *.
    pre_nomega.
    unfold natToW in H33; rewrite wordToNat_natToWord_idempotent in H33.
    omega.
    change (goodSize (length x3)); eauto.
    autorewrite with Locals.
    etransitivity.
    symmetry; apply (firstn_skipn (wordToNat (sel x1 s))).
    f_equal.

    Hint Rewrite roundTrip_0 : N.

    Lemma skipn_breakout : forall ws n,
      (n < length ws)%nat
      -> skipn n ws = Array.selN ws n :: tl (skipn n ws).
      induction ws; destruct n; simpl; intuition.
    Qed.

    rewrite skipn_breakout.
    eauto.
    rewrite H27 in *.
    pre_nomega.
    unfold natToW in H33; rewrite wordToNat_natToWord_idempotent in H33.
    omega.
    change (goodSize (length x3)); eauto.
    finish0.
    finish0.


    wrap; t.
  Defined.

End Query.

Definition ForArray (arr size index value : string) (c : condition) invPre invPost (Body : chunk) : chunk :=
  fun ns res => Structured nil (fun _ _ H => Query arr size index value c H invPre invPost
    (toCmd Body _ H ns res) ns res).

Notation "[ 'After' ws 'Approaching' full 'PRE' [ V ] pre 'POST' [ R ] post ] 'For' index 'Holding' value 'in' arr 'Size' size 'Where' c { Body }" :=
  (ForArray arr size index value c%ArrayQuery (fun ws V => pre%qspec%Sep)
    (fun full V R => post%qspec%Sep) Body)
  (no associativity, at level 95, index at level 0, value at level 0, arr at level 0, size at level 0,
    c at level 0) : SP_scope.

Ltac for0 := try solve [ intuition (try congruence);
  repeat match goal with
           | [ H : forall x : string, _ |- _ ] => rewrite H by congruence
         end; reflexivity ].
