(* =====================================================
   EasyCrypt Query Commands Test File
   ===================================================== *)

(* Test 1: Basic type queries *)
(* Try: Ctrl+Shift+Q -> "print bool" *)
(* Try: Place cursor on "bool" -> Ctrl+Alt+Q -> select "print" *)
require import Bool.

(* Test 2: Operator queries *)
(* Try: Ctrl+Shift+Q -> "print Int.( + )" *)
(* Try: Ctrl+Shift+Q -> "check int" *)
require import Int.

(* Test 3: Search functionality *)
(* Try: Ctrl+Shift+Q -> "search eq" *)
(* Try: Ctrl+Shift+Q -> "search bool" *)

(* Test 4: Locate symbols *)
(* Try: Ctrl+Shift+Q -> "locate bool" *)
(* Try: Ctrl+Shift+Q -> "locate Int.( + )" *)

(* Test 5: Custom definitions *)
op my_custom_op (x : bool) : bool = x.

axiom my_axiom: forall x, my_custom_op x = x.

(* Try: Place cursor on "my_custom_op" -> Ctrl+Alt+Q -> select "print" *)
(* Try: Place cursor on "my_axiom" -> Ctrl+Alt+Q -> select "print" *)
(* Try: Ctrl+Shift+Q -> "check my_custom_op" *)
(* Try: Ctrl+Shift+Q -> "locate my_custom_op" *)

(* Test 6: Right-click context menu *)
(* Right-click on any symbol below and select "Query Symbol Under Cursor" *)
lemma test_lemma: forall (x : bool), x \/ !x.
proof.
  move=> x.
  (* Try right-click on "x" and query it *)
  case x.
    by left.
    by right.
qed.

(* =====================================================
   Instructions for Testing:
   
   1. Open this file in VS Code with the VsEc extension
   2. Press Ctrl+Shift+Q to open query command input
   3. Type queries like: "print bool", "search eq", etc.
   4. Place cursor on any symbol and press Ctrl+Alt+Q
   5. Right-click any symbol -> "Query Symbol Under Cursor"
   6. Check the VsEc output channel for results
   ===================================================== *)

