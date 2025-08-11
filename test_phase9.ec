require import AllCore.

lemma test_lemma : forall x, x = x.
proof.
auto.
qed.

module TestModule = {
  proc test_proc() : unit = {
    return();
  }
}.