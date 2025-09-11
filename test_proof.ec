require import AllCore.

lemma test_simple_proof (a : int) : a >= 0 => a + 1 > 0.
proof.
  intros H.
  by apply addrC.
qed.