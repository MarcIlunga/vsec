require import AllCore Int.

(* Simple test theorem *)
lemma test_simple : forall (x : int), x + 0 = x.
proof.
  by smt().
qed.

(* Another simple test *)  
lemma test_basic : 1 + 1 = 2.
proof.
  by trivial.
qed.