Require Import Semantics.
Require Import Syntax SemanticsExpr.
Require Import Memory IL List.

Section fs.

  Variable fs : W -> option Callee.

  CoInductive Safe : Stmt -> State -> Prop :=
  | Skip : 
      forall v, Safe Syntax.Skip v
  | Seq : 
      forall a b v, 
        Safe a v ->
        (forall v', RunsTo fs a v v' -> Safe b v') -> 
        Safe (Syntax.Seq a b) v
  | If : 
      forall cond t f v, 
        let b := wneb (eval (fst v) cond) $0 in
        b = true /\ Safe t v \/ b = false /\ Safe f v ->
        Safe (Syntax.If cond t f) v
  | While : 
      forall cond body v, 
        let loop := While cond body in
        Safe (Syntax.If cond (Syntax.Seq body loop) Syntax.Skip) v ->
        Safe loop v
  | CallInternal : 
      forall var f args v spec,
        let vs := fst v in
        let heap := snd v in
        fs (eval vs f) = Some (Internal spec) ->
        (forall vs_arg, 
           map (Locals.sel vs_arg) (ArgVars spec) = map (eval vs) args 
           -> Safe (Body spec) (vs_arg, heap)) ->
        Safe (Syntax.Call var f args) v
  | CallForeign : 
      forall var f args v spec pairs,
        let vs := fst v in
        let heap := snd v in
        fs (eval vs f) = Some (Foreign spec) ->
        map (eval vs) args = map fst pairs ->
        Forall (heap_match heap) pairs ->
        PreCond spec (map snd pairs) ->
        Safe (Syntax.Call var f args) v.

End fs.
