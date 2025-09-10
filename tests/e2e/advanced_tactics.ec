(* Advanced Tactics and Proof Techniques for E2E Testing *)

(* Test with quantifier manipulation *)
lemma quantifier_manipulation:
  (forall x, P x) => (exists x, P x).
proof.
  intro h.
  (* This tests existential introduction *)
  exists witness.
  apply h.
qed.

(* Test with proof by contradiction *)
lemma proof_by_contradiction (P : bool):
  !!P => P.
proof.
  intro h.
  (* Test classical reasoning *)
  by_contra hnp.
  apply h.
  exact hnp.
qed.

(* Test with case splitting and subgoals *)
lemma complex_case_split (x y z : bool):
  (x \/ y) /\ z => (x /\ z) \/ (y /\ z).
proof.
  intro h.
  elim h => hxy hz.
  case hxy.
  (* Case 1: x is true *)
  intro hx.
  left.
  split.
  exact hx.
  exact hz.
  (* Case 2: y is true *)
  intro hy.
  right.
  split.
  exact hy.
  exact hz.
qed.

(* Test with inductive reasoning patterns *)
type list = [ Nil | Cons of int * list ].

op length : list -> int.
axiom length_nil: length Nil = 0.
axiom length_cons: forall x xs, length (Cons x xs) = 1 + length xs.

lemma length_non_negative (l : list):
  0 <= length l.
proof.
  (* This would require structural induction in full EasyCrypt *)
  elim l.
  (* Base case: Nil *)
  rewrite length_nil.
  trivial.
  (* Inductive case: Cons *)
  intro x xs ih.
  rewrite length_cons.
  (* Use inductive hypothesis *)
  smt(ih).
qed.

(* Test with higher-order logic *)
op map : ('a -> 'b) -> 'a list -> 'b list.
axiom map_nil: forall f, map f Nil = Nil.
axiom map_cons: forall f x xs, map f (Cons x xs) = Cons (f x) (map f xs).

lemma map_length (f : int -> int) (l : list):
  length (map f l) = length l.
proof.
  elim l.
  (* Base case *)
  rewrite map_nil length_nil.
  trivial.
  (* Inductive case *)
  intro x xs ih.
  rewrite map_cons !length_cons.
  rewrite ih.
qed.

(* Test with SMT solver integration *)
lemma arithmetic_reasoning (x y z : int):
  x + y = z => y + x = z.
proof.
  intro h.
  smt(h).
qed.

(* Test with multiple proof strategies *)
lemma multiple_strategies (P Q R : bool):
  (P => Q) => (Q => R) => (P => R).
proof.
  intro h1 h2 hp.
  apply h2.
  apply h1.
  exact hp.
qed.

(* Test error recovery with incomplete proofs *)
lemma incomplete_proof_test:
  forall (x : int), x = x + 0.
proof.
  intro x.
  (* Missing the actual proof step - should be handled gracefully *)
  (* smt(). *)
  admit.
qed.