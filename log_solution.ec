(* logic-examp.ec *)

require import AllCore.

lemma negb_or (a b : bool) :
  !(a \/ b) <=> !a /\ !b.
proof.
split.
- move=> nab.
  split => hyp.
  - apply nab. by left.
  - apply nab. by right.
- move=> [na nb] ab.
  case ab => [a_true | b_true].
  - by apply na.
  - by apply nb.
qed.

lemma foo (x y z : int) :
  !(x < y \/ y < z) <=> ! x < y /\ ! y < z.
proof.
by rewrite negb_or.
qed.

lemma negb_or' (a b : bool) :
  !(a \/ b) <=> !a /\ !b.
proof.
by split; [case | move=> [? ?] []].
qed.