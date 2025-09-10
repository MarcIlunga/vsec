(* Cryptographic Primitives for E2E Testing *)

(* Test cryptographic types and operations *)
type key.
type plaintext.
type ciphertext.

op encrypt : key -> plaintext -> ciphertext.
op decrypt : key -> ciphertext -> plaintext.

(* Correctness axiom *)
axiom decrypt_encrypt: 
  forall (k : key) (m : plaintext), 
  decrypt k (encrypt k m) = m.

(* Test lemma using crypto axiom *)
lemma encryption_correctness (k : key) (msg : plaintext):
  decrypt k (encrypt k msg) = msg.
proof.
  rewrite decrypt_encrypt.
qed.

(* Test with probabilistic reasoning *)
type distribution.
op uniform : distribution.
op sample : distribution -> plaintext.

(* Test security property structure *)
lemma security_game_structure:
  forall (k : key) (d : distribution),
  exists (m : plaintext), 
  decrypt k (encrypt k (sample d)) = sample d.
proof.
  intro k d.
  exists (sample d).
  rewrite decrypt_encrypt.
qed.

(* Test with computational assumptions *)
axiom computational_assumption:
  forall (k1 k2 : key) (m : plaintext),
  k1 <> k2 => decrypt k1 (encrypt k2 m) <> m.

lemma key_independence (k1 k2 : key) (m : plaintext):
  k1 <> k2 => decrypt k1 (encrypt k2 m) <> m.
proof.
  intro h.
  rewrite computational_assumption.
  exact h.
qed.

(* Test error handling with invalid operations *)
lemma invalid_crypto_operation:
  forall (k : key), decrypt k (encrypt k) = decrypt k.
proof.
  (* This should cause a type error - encrypt needs 2 arguments *)
  admit.
qed.
