(* logic-examp.ec *)
require import AllCore.

module Func1 = {
  proc add_1 (x:int) : int = { return x+1; }
  proc add_2 (x: int) : int = { x <- x + 2; return x; }
}.

lemma triple1: hoare [ Func1.add_1 : x = 1 ==> res = 2].

proof.
  proc.
  skip.
  trivial.
qed.

lemma triple2: hoare [ Func1.add_2 : x = 1 ==> res = 3 ].

proof.
  proc.
  skip.
  subst.
qued.