(* Interactive Development Scenarios for E2E Testing *)

(* Test incremental proof development *)
lemma incremental_proof (P Q R : bool):
  P /\ Q /\ R => R /\ Q /\ P.
proof.
  intro h.
  (* Step 1: Extract components *)
  elim h => hp hqr.
  elim hqr => hq hr.
  (* Step 2: Reconstruct in different order *)
  split.
  exact hr.
  split.
  exact hq.
  exact hp.
qed.

(* Test with intermediate definitions *)
op intermediate_def (x y : int) : int = x + y + 1.

lemma test_intermediate (a b : int):
  intermediate_def a b = a + b + 1.
proof.
  (* Test unfolding definitions *)
  rewrite /intermediate_def.
qed.

(* Test with local definitions in proof *)
lemma local_definitions (x y : int):
  x + y = y + x.
proof.
  (* This tests local reasoning *)
  have h: x + y = y + x by smt().
  exact h.
qed.

(* Test with proof state inspection *)
lemma proof_state_test (P Q : bool):
  P => Q => P /\ Q.
proof.
  intro hp.
  intro hq.
  (* At this point, we should see hp : P and hq : Q in context *)
  split.
  (* Goal 1: P *)
  exact hp.
  (* Goal 2: Q *)
  exact hq.
qed.

(* Test with goal transformation *)
lemma goal_transformation (x y z : int):
  x = y => y = z => x = z.
proof.
  intro h1 h2.
  (* Transform goal using transitivity *)
  rewrite h1.
  exact h2.
qed.

(* Test with hypothesis management *)
lemma hypothesis_management (P Q R S : bool):
  (P => Q) => (R => S) => P /\ R => Q /\ S.
proof.
  intro h1 h2 h3.
  elim h3 => hp hr.
  split.
  (* Use first implication *)
  apply h1.
  exact hp.
  (* Use second implication *)
  apply h2.
  exact hr.
qed.

(* Test with proof search and automation *)
lemma automation_test (x y : int):
  x + 0 = x /\ 0 + y = y.
proof.
  (* Test automatic proof search *)
  split; smt().
qed.

(* Test with partial proof and TODO markers *)
lemma partial_proof_with_todos (P Q R : bool):
  (P \/ Q) /\ R => (P /\ R) \/ (Q /\ R).
proof.
  intro h.
  elim h => hpq hr.
  case hpq.
  (* TODO: Complete case P *)
  intro hp.
  left.
  split.
  exact hp.
  exact hr.
  (* TODO: Complete case Q *)
  intro hq.
  right.
  split.
  exact hq.
  exact hr.
qed.

(* Test with proof refactoring scenarios *)
lemma refactoring_test (a b c : int):
  a + b + c = c + b + a.
proof.
  (* Original approach *)
  (* smt(). *)
  (* Refactored approach with explicit steps *)
  have h1: a + b + c = (a + b) + c by smt().
  have h2: (a + b) + c = c + (a + b) by smt().
  have h3: c + (a + b) = c + (b + a) by smt().
  have h4: c + (b + a) = c + b + a by smt().
  rewrite h1 h2 h3 h4.
qed.

(* Test error scenarios during interactive development *)
lemma interactive_error_test:
  forall (x : int), x > 0 => x + 1 > 1.
proof.
  intro x h.
  (* This might fail if SMT solver is not available *)
  smt(h).
  (* Fallback manual proof *)
  (* admit. *)
qed.
