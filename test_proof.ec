require import Int.

lemma simple_proof (x : int) : 
  0 <= x => 0 <= x + 1.
proof.
  intro h.
  by smt().
qed.

lemma test_hypotheses (P Q : int -> bool) (a : int) :
  (forall x, P x => Q x) => P a => Q a.
proof.
  intros H1 H2.
  apply H1.
  exact H2.
qed.