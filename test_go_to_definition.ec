(*
Test file for Go to Definition functionality
This file contains various EasyCrypt definitions to test navigation
*)

require import List Real Logic.

(* Test type definitions *)
type test_type = bool * int.
type user_record = { 
  name : string;
  age : int;
}.

(* Test operator definitions *)
op test_op (x: int) : bool = 
    x = 0.
    
op complex_op (r: user_record) : int =
    r.age.

(* Test predicate definitions *)
pred is_adult (r: user_record) : bool = 
    r.age >= 18.

(* Test module definitions *)
module TestModule = {
  type internal_type = int.
  
  op helper_op (x: internal_type) : bool = x > 0.
  
  pred module_pred (x: int) : bool = helper_op x.
}.

(* Test lemma definitions *)
lemma test_lemma: forall (x: int), x = x.
proof.
  intros x.
  trivial.
qed.

theorem important_theorem: 
  forall (r: user_record), is_adult r => r.age >= 18.
proof.
  intros r H.
  unfold is_adult in H.
  exact H.
qed.

(* Test axiom definitions *)
axiom test_axiom: forall (x: int), x >= 0 \/ x < 0.

(* Test usage patterns - these should navigate to definitions above *)
lemma usage_example: 
  forall (r: user_record), 
  test_op (complex_op r) = true => 
  is_adult r => 
  important_theorem.
proof.
  intros r H_test H_adult.
  (* Click on any symbol here to test navigation *)
  apply important_theorem.
  exact H_adult.
qed.