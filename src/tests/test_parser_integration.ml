(* Test EasyCrypt parser integration *)
open Dm
module D = Document.Internal

let%test_unit "parse_empty_document" =
  (* Test parsing an empty document *)
  let text = "" in
  let raw_doc = RawDocument.create text in
  let stream = Stream.of_string text in
  let init_scope = EcLib.EcScope.empty in
  let sentences, errors = D.parse_more init_scope stream raw_doc in
  assert (sentences = []);
  assert (errors = [])

let%test_unit "parse_single_theory" =
  (* Test parsing a simple theory declaration *)
  let text = "theory Test. end Test." in
  let raw_doc = RawDocument.create text in
  let stream = Stream.of_string text in
  let init_scope = EcLib.EcScope.empty in
  let sentences, errors = D.parse_more init_scope stream raw_doc in
  (* Should parse successfully *)
  assert (List.length errors = 0);
  (* Should have at least one sentence *)
  assert (List.length sentences > 0)

let%test_unit "parse_with_syntax_error" =
  (* Test parsing with a syntax error *)
  let text = "theory Test" in (* Missing period *)
  let raw_doc = RawDocument.create text in
  let stream = Stream.of_string text in
  let init_scope = EcLib.EcScope.empty in
  let sentences, errors = D.parse_more init_scope stream raw_doc in
  (* Should have parse errors *)
  assert (List.length errors > 0)

let%test_unit "parse_multiple_declarations" =
  (* Test parsing multiple declarations *)
  let text = "require import AllCore.\nop myop : int.\nlemma test : true." in
  let raw_doc = RawDocument.create text in
  let stream = Stream.of_string text in
  let init_scope = EcLib.EcScope.empty in
  let sentences, errors = D.parse_more init_scope stream raw_doc in
  (* Should parse multiple sentences *)
  assert (List.length sentences >= 3)

let%test "token_classification_keywords" =
  (* Test keyword token classification *)
  let open EcLib.EcParser in
  D.classify_token LEMMA = `Keyword &&
  D.classify_token THEORY = `Keyword &&
  D.classify_token MODULE = `Keyword

let%test "token_classification_identifiers" =
  (* Test identifier token classification *)
  let open EcLib.EcParser in
  D.classify_token (LIDENT "foo") = `Identifier &&
  D.classify_token (UIDENT "Bar") = `Identifier

let%test "token_classification_operators" =
  (* Test operator token classification *)
  let open EcLib.EcParser in
  D.classify_token PLUS = `Operator &&
  D.classify_token EQ = `Operator &&
  D.classify_token IMPL = `Operator

let%test "token_classification_delimiters" =
  (* Test delimiter token classification *)
  let open EcLib.EcParser in
  D.classify_token LPAREN = `Delimiter &&
  D.classify_token COMMA = `Delimiter &&
  D.classify_token SEMICOLON = `Delimiter

let%test_unit "parse_unicode_identifiers" =
  (* Test parsing with unicode characters *)
  let text = "op α : int." in
  let raw_doc = RawDocument.create text in
  let stream = Stream.of_string text in
  let init_scope = EcLib.EcScope.empty in
  let sentences, errors = D.parse_more init_scope stream raw_doc in
  (* Should handle unicode gracefully (either parse or error appropriately) *)
  assert (List.length sentences + List.length errors > 0)

let%test_unit "parse_large_input" =
  (* Test parsing performance with larger input *)
  let text = String.concat "\n" [
    "theory LargeTest.";
    String.concat "\n" (List.init 100 (fun i -> Printf.sprintf "op op%d : int." i));
    "end LargeTest."
  ] in
  let raw_doc = RawDocument.create text in
  let stream = Stream.of_string text in
  let init_scope = EcLib.EcScope.empty in
  let sentences, errors = D.parse_more init_scope stream raw_doc in
  (* Should parse without stack overflow or hanging *)
  assert (List.length sentences > 0 || List.length errors > 0)

let%test_unit "parse_comment_handling" =
  (* Test that comments are handled (even if just skipped) *)
  let text = "(* This is a comment *)\nlemma test : true." in
  let raw_doc = RawDocument.create text in
  let stream = Stream.of_string text in
  let init_scope = EcLib.EcScope.empty in
  let sentences, errors = D.parse_more init_scope stream raw_doc in
  (* Should parse the lemma after the comment *)
  assert (List.length sentences > 0 || List.length errors > 0)

let%test_unit "parse_error_recovery" =
  (* Test error recovery - parser should continue after errors *)
  let text = "op bad syntax.\nop good : int." in
  let raw_doc = RawDocument.create text in
  let stream = Stream.of_string text in
  let init_scope = EcLib.EcScope.empty in
  let sentences, errors = D.parse_more init_scope stream raw_doc in
  (* Should attempt to parse both declarations *)
  assert (List.length sentences + List.length errors >= 2)

let%test "global_classification" =
  (* Test classification of different global types *)
  let make_global desc = 
    { EcLib.EcParsetree.gl_action = EcLib.EcLocation.mk_loc EcLib.EcLocation.dummy desc;
      gl_debug = None } in
  
  let open EcLib.EcParsetree in
  (* Theories and modules are side effects *)
  D.classify_global (make_global (Gtheory (None, []))) = Scheduler.VtSideff &&
  D.classify_global (make_global (Gmodule { me_name = mk_loc dummy ([], "M"); 
                                                    me_sig = mk_loc dummy ME_Alias;
                                                    me_params = [] })) = Scheduler.VtSideff &&
  (* Lemmas start proofs *)
  D.classify_global (make_global (Glemma [])) = Scheduler.VtStartProof &&
  (* Queries *)
  D.classify_global (make_global (Gprint (Pr_any (mk_loc dummy ([], "x"))))) = Scheduler.VtQuery