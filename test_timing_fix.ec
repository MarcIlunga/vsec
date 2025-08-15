lemma test_lemma : forall (x : int), x + 0 = x.
proof.
  move => x.
  ring.
qed.