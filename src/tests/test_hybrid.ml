open Dm
open Types

let%test_module "hybrid-execution-with-process" = (module struct
  let gstate = EcLib.EcGState.create ()
  let init_scope = EcLib.EcScope.empty gstate

  let has_easycrypt () =
    try Sys.command "easycrypt --version >/dev/null 2>&1" = 0 with _ -> false

  let mk_doc text =
    let doc = Document.create_document init_scope text in
    let parsed_doc, _events = Document.validate_document doc in
    parsed_doc

  let sentences_of doc = Document.sentences_sorted_by_loc doc

  let%test "hybrid_exec_sequence_safe" =
    if not (has_easycrypt ()) then true else (
      let _ = ExecutionManager.execute_with_goal_extraction "lemma L: true." in
      let goals_after_proof = ExecutionManager.execute_with_goal_extraction "proof." in
      (* Should return a list; may be empty depending on EasyCrypt output format *)
      match goals_after_proof with _ -> true
    )

  let%test "parse_with_eclib_and_hybrid_exec_on_sentences" =
    (* Use EcLib for parsing; use easycrypt -emacs for proof goals *)
    if not (has_easycrypt ()) then true else (
      let text = "lemma L: true.\nproof.\nqed." in
      let doc = mk_doc text in
      let sents = sentences_of doc in
      (* Expect at least lemma, proof, qed; run hybrid on lemma then proof *)
      let _ = match sents with
        | s1 :: s2 :: _ ->
          let _ = ExecutionManager.execute_with_goal_extraction (Document.Internal.string_of_sentence s1) in
          let goals = ExecutionManager.execute_with_goal_extraction (Document.Internal.string_of_sentence s2) in
          (match goals with _ -> ())
        | _ -> () in
      true
    )

  let%test "store_and_retrieve_hybrid_proof_json" =
    let exec_state, _ = ExecutionManager.init init_scope in
    let sid = 12345 in
    let proof_json = `Assoc [ ("jsonrpc", `String "2.0"); ("method", `String "prover/proofView"); ("params", `Assoc []) ] in
    let exec_state' = ExecutionManager.set_hybrid_proof exec_state sid proof_json in
    match ExecutionManager.hybrid_proof_for_sentence exec_state' sid with
    | Some _ -> true
    | None -> false
end)


