Require Import SyntaxModule.
Require Import List.
Require CompileFunc.
Require Import GoodFunc GoodOptimizer.
Require Import GoodModule.

Set Implicit Arguments.

Section TopSection.

  Variable module : GoodModule.

  Require Import CompileFuncImpl.
  Require Import StructuredModule.
  Definition imports : list import := nil.

  Variable optimizer : Optimizer.

  Hypothesis good_optimizer : GoodOptimizer optimizer.

  Require Import NameDecoration.
  Definition mod_name := impl_module_name (Name module).

  Definition compile_func' (f : Func) (good_func : GoodFunc f) := CompileFunc.compile mod_name f good_func good_optimizer.

  Require Import GoodFunction.
  Definition compile_func (f : GoodFunction) := compile_func' f (to_func_good f).

  Definition compiled_funcs := map compile_func (Functions module).

  Require Import Structured.
  Require Import Wrap.
  Lemma good_vcs : forall ls, vcs (makeVcs imports compiled_funcs (map compile_func ls)).
    induction ls; simpl; eauto; destruct a; simpl; unfold CompileFuncSpec.imply; wrap0.
  Qed.

  Definition compile := StructuredModule.bmodule_ imports compiled_funcs.

  Require Import NameVC.
  Lemma module_name_not_in_imports : NameNotInImports mod_name imports.
    unfold NameNotInImports; eauto.
  Qed.

  Lemma no_dup_func_names : NoDupFuncNames compiled_funcs.
    eapply NoDup_NoDupFuncNames.
    unfold compiled_funcs.
    erewrite map_map.
    unfold compile_func.
    unfold compile_func'.
    unfold CompileFunc.compile; simpl.
    destruct module; simpl.
    eauto.
  Qed.

  Theorem compileOk : XCAP.moduleOk compile.
    eapply bmoduleOk.
    eapply module_name_not_in_imports.
    eapply no_dup_func_names.
    eapply good_vcs.
  Qed.

End TopSection.