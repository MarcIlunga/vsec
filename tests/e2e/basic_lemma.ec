(* Basic EasyCrypt Lemma for End-to-End Testing *)

(* Simple truth lemma *)
lemma simple_truth: true.
proof. trivial. qed.

(* Basic conjunction *)
lemma basic_conjunction: true /\ true.
proof.
  split.
  trivial.
  trivial.
qed.

(* Simple implication *)
lemma basic_implication: true => true.
proof.
  intro h.
  trivial.
qed.

(* Test with hypothesis *)
lemma with_hypothesis (x : bool): x \/ !x.
proof.
  case x.
  left; trivial.
  right; trivial.
qed.

(* Test error recovery *)
lemma error_recovery: false.
proof.
  (* This should fail and we should be able to handle the error *)
  admit.
qed.
