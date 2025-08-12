(** Test file for EasyCrypt Interactive Proving *)

lemma test_simple_proof : forall x, x = x.
proof.
  intros x.
  apply eq_refl.
qed.

lemma test_logic : forall P Q, P /\ Q => Q /\ P.
proof.
  intros P Q h.
  split.
  - apply (proj2 h).
  - apply (proj1 h).
qed.

lemma test_arithmetic : forall n, n + 0 = n.
proof.
  intros n.
  apply add_zero_r.
qed.