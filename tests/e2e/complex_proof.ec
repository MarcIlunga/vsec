(* Complex EasyCrypt Proof for End-to-End Testing *)

(* Test module system *)
module TestModule.
  op test_op : bool = true.
  
  lemma module_lemma: test_op.
  proof. trivial. qed.
end TestModule.

(* Test with multiple steps and tactics *)
lemma complex_multi_step: 
  forall (x y : bool), (x /\ y) => (y /\ x).
proof.
  intro x y.
  intro h.
  elim h => hx hy.
  split.
  exact hy.
  exact hx.
qed.

(* Test with case analysis *)
lemma case_analysis (b : bool): b \/ !b.
proof.
  case b.
  left; trivial.
  right; trivial.
qed.

(* Test with rewriting *)
axiom test_axiom: forall (x : bool), x = x.

lemma rewrite_test (x : bool): x = x.
proof.
  rewrite test_axiom.
qed.

(* Test with induction-like structure *)
type nat = [ Zero | Succ of nat ].

op add : nat -> nat -> nat.
axiom add_zero: forall n, add Zero n = n.
axiom add_succ: forall n m, add (Succ n) m = Succ (add n m).

lemma add_comm_zero (n : nat): add n Zero = add Zero n.
proof.
  rewrite add_zero.
  (* This would require more complex induction in real EasyCrypt *)
  admit.
qed.

(* Test error scenarios for robust testing *)
lemma intentional_error: false.
proof.
  (* This should generate an error that our system should handle *)
  invalid_tactic_name.
qed.
