
lemma simple_test: true.
proof.
  trivial.
qed.

lemma complex_test: forall (x: bool), x = x.
proof.
  intros x.
  (* We should be able to extract the goal here *)
