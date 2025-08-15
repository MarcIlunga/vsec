(*
Test file for enhanced completion system
This file tests various completion contexts
*)

require import List Real Logic.

(* Test module completions *)
module TestModule = {
  (* Test type completions *)
  type test_type = bool * int.
  
  (* Test operator completions *)
  op test_op (x: int) : bool = 
    x = 0.
}.

(* Test lemma with proof completions *)
lemma test_lemma: forall (x: int), x = x.
proof.
  (* Test tactic completions here *)
  intros x.
  (* Try "apply" followed by space - should suggest lemma completions *)
  apply 
  (* Try typing after "." - should suggest qualified names *)
  TestModule.
qed.

(* Test require completions *)
require 

(* Test import patterns *)
import 