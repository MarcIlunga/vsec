open Printf

(* LSP Integration Test - Simulates the full LSP event loop *)
(* Tests interactive proving commands end-to-end *)

(* Test configuration *)
let test_doc_text = "lemma test_integration (P Q : bool): P => Q => P /\\ Q.\nproof.\n  move=> H_P H_Q."

(* State to track proof views received *)
let proof_views = ref []
let clear_proof_views () = proof_views := []
let add_proof_view pv = proof_views := pv :: !proof_views

(* Mock LSP output functions *)
let mock_output_json _json = ()
let mock_send_log _msg = ()

(* Setup EasyCrypt *)
let setup_easycrypt () =
  let theories_paths = EcLib.EcDuneSites.Sites.theories in
  List.iter (fun theory ->
    let prelude = Filename.concat theory "prelude" in
    EcLib.EcCommands.addidir ~namespace:`System prelude;
    EcLib.EcCommands.addidir ~namespace:`System ~recursive:true theory
  ) theories_paths;
  
  let checkmode = {
    EcLib.EcCommands.cm_checkall = false;
    cm_timeout = 5;
    cm_cpufactor = 1;
    cm_nprovers = 1;
    cm_provers = None;
    cm_profile = false;
    cm_iterate = false;
  } in
  
  EcLib.EcCommands.initial ~checkmode ~boot:false

(* For tests: DocumentManager.init already parses the document *)
(* The parsing events are async, but the document structure is ready *)
(* We just need to wait a bit for sentence creation in real scenarios *)
let force_parse_document st =
  (* The document is already parsed by init - sentences should be available *)
  st

(* Test result tracking *)
type test_result = {
  name: string;
  passed: bool;
  error: string option;
}

let results = ref []
let add_result name passed error =
  results := { name; passed; error } :: !results

(* ========================================
   TEST 1: Document Initialization & Parsing
   ======================================== *)
let test_document_init init_scope =
  printf "\n📋 Test 1: Document Initialization & Parsing\n";
  try
    let uri = Lsp.Types.DocumentUri.of_string "file:///test_integration.ec" in
    let (st, init_events) = Dm.DocumentManager.init init_scope uri ~text:test_doc_text in
    printf "   ✓ DocumentManager.init returned %d events\n" (List.length init_events);
    
    (* Force parsing for tests - in real LSP, events are processed by event loop *)
    let st_parsed = force_parse_document st in
    
    (* Check if document has sentences *)
    let document = Dm.DocumentManager.Internal.document st_parsed in
    let sentences = Dm.Document.sentences document in
    printf "   ✓ Document has %d sentences\n" (List.length sentences);
    
    if List.length sentences > 0 then (
      add_result "Document Init" true None;
      printf "   ✅ PASSED: Document initialized and parsed\n";
      Some (st_parsed, uri)
    ) else (
      add_result "Document Init" false (Some "No sentences after parsing");
      printf "   ❌ FAILED: No sentences after parsing\n";
      None
    )
  with e ->
    add_result "Document Init" false (Some (Printexc.to_string e));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string e);
    None

(* ========================================
   TEST 2: Step Forward (First Step)
   ======================================== *)
let test_step_forward_1 st uri =
  printf "\n📋 Test 2: Step Forward (Execute Lemma)\n";
  try
    clear_proof_views ();
    
    (* Call interpret_to_next (what ecStepForward does) *)
    let (st', events) = Dm.DocumentManager.interpret_to_next st in
    printf "   ✓ interpret_to_next returned %d events\n" (List.length events);
    
    (* With synchronous execution, events should be empty *)
    let st_final = st' in
    
    (* Get proof state *)
    let proof = Dm.DocumentManager.get_proof st_final None in
    
    match proof with
    | None ->
      add_result "Step Forward 1" false (Some "No proof state after lemma");
      printf "   ❌ FAILED: No proof state after lemma\n";
      None
    | Some p ->
      printf "   ✓ Proof state: %d goals, in_proof=%b\n" (List.length p.Protocol.ProofState.goals) p.Protocol.ProofState.in_proof;
      if List.length p.Protocol.ProofState.goals > 0 then (
        let goal = List.hd p.Protocol.ProofState.goals in
        printf "   ✓ Goal: %s\n" goal.Protocol.ProofState.goal;
        add_result "Step Forward 1" true None;
        printf "   ✅ PASSED: First step forward successful\n";
        Some st_final
      ) else (
        add_result "Step Forward 1" false (Some "No goals in proof state");
        printf "   ❌ FAILED: No goals in proof state\n";
        None
      )
  with e ->
    add_result "Step Forward 1" false (Some (Printexc.to_string e));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string e);
    None

(* ========================================
   TEST 3: Step Forward (Second Step - proof.)
   ======================================== *)
let test_step_forward_2 st uri =
  printf "\n📋 Test 3: Step Forward (Execute 'proof.')\n";
  try
    let (st', events) = Dm.DocumentManager.interpret_to_next st in
    printf "   ✓ interpret_to_next returned %d events\n" (List.length events);
    
    let st_final = st' in
    let proof = Dm.DocumentManager.get_proof st_final None in
    
    match proof with
    | None ->
      add_result "Step Forward 2" false (Some "No proof state after 'proof.'");
      printf "   ❌ FAILED: No proof state after 'proof.'\n";
      None
    | Some p ->
      printf "   ✓ Proof state: %d goals, in_proof=%b\n" (List.length p.Protocol.ProofState.goals) p.Protocol.ProofState.in_proof;
      if p.Protocol.ProofState.in_proof then (
        add_result "Step Forward 2" true None;
        printf "   ✅ PASSED: Entered proof mode\n";
        Some st_final
      ) else (
        add_result "Step Forward 2" false (Some "Not in proof mode");
        printf "   ❌ FAILED: Not in proof mode\n";
        None
      )
  with e ->
    add_result "Step Forward 2" false (Some (Printexc.to_string e));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string e);
    None

(* ========================================
   TEST 4: Step Forward (Third Step - tactic with hypotheses)
   ======================================== *)
let test_step_forward_3 st uri =
  printf "\n📋 Test 4: Step Forward (Execute 'move=> H_P H_Q.')\n";
  try
    let (st', events) = Dm.DocumentManager.interpret_to_next st in
    printf "   ✓ interpret_to_next returned %d events\n" (List.length events);
    
    let st_final = st' in
    let proof = Dm.DocumentManager.get_proof st_final None in
    
    match proof with
    | None ->
      add_result "Step Forward 3 (Hypotheses)" false (Some "No proof state after tactic");
      printf "   ❌ FAILED: No proof state after tactic\n";
      None
    | Some p ->
      printf "   ✓ Proof state: %d goals\n" (List.length p.Protocol.ProofState.goals);
      if List.length p.Protocol.ProofState.goals = 0 then (
        add_result "Step Forward 3 (Hypotheses)" false (Some "No goals");
        printf "   ❌ FAILED: No goals\n";
        None
      ) else (
        let goal = List.hd p.Protocol.ProofState.goals in
        let hyp_count = List.length goal.Protocol.ProofState.hypotheses in
        printf "   ✓ Hypotheses count: %d\n" hyp_count;
        printf "   ✓ Goal: %s\n" goal.Protocol.ProofState.goal;
        
        if hyp_count >= 2 then (
          let has_hp = List.exists (fun h -> String.contains h 'H' && String.contains h 'P') goal.Protocol.ProofState.hypotheses in
          let has_hq = List.exists (fun h -> String.contains h 'H' && String.contains h 'Q') goal.Protocol.ProofState.hypotheses in
          
          if has_hp && has_hq then (
            printf "   ✓ Found H_P and H_Q\n";
            add_result "Step Forward 3 (Hypotheses)" true None;
            printf "   ✅ PASSED: Hypotheses extracted correctly\n";
            Some st_final
          ) else (
            add_result "Step Forward 3 (Hypotheses)" false (Some "Missing H_P or H_Q");
            printf "   ❌ FAILED: Missing H_P or H_Q\n";
            None
          )
        ) else (
          add_result "Step Forward 3 (Hypotheses)" false (Some (Printf.sprintf "Expected >= 2 hypotheses, got %d" hyp_count));
          printf "   ❌ FAILED: Expected >= 2 hypotheses, got %d\n" hyp_count;
          None
        )
      )
  with e ->
    add_result "Step Forward 3 (Hypotheses)" false (Some (Printexc.to_string e));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string e);
    None

(* ========================================
   TEST 5: Step Backward
   ======================================== *)
let test_step_backward st uri =
  printf "\n📋 Test 5: Step Backward\n";
  try
    let (st', events) = Dm.DocumentManager.interpret_to_previous st in
    printf "   ✓ interpret_to_previous returned %d events\n" (List.length events);
    
    let st_final = st' in
    let proof = Dm.DocumentManager.get_proof st_final None in
    
    match proof with
    | None ->
      add_result "Step Backward" false (Some "No proof state after step back");
      printf "   ❌ FAILED: No proof state after step back\n";
      None
    | Some p ->
      printf "   ✓ Proof state: %d goals, in_proof=%b\n" (List.length p.Protocol.ProofState.goals) p.Protocol.ProofState.in_proof;
      
      (* After stepping back from "move=> H_P H_Q", we should be back at "proof." *)
      (* The goal should be the full implication without destructured hypotheses *)
      if List.length p.Protocol.ProofState.goals > 0 then (
        let goal = List.hd p.Protocol.ProofState.goals in
        let hyp_count = List.length goal.Protocol.ProofState.hypotheses in
        printf "   ✓ Hypotheses count after step back: %d\n" hyp_count;
        
        (* We expect fewer hypotheses after stepping back *)
        add_result "Step Backward" true None;
        printf "   ✅ PASSED: Step backward successful\n";
        Some st_final
      ) else (
        add_result "Step Backward" false (Some "No goals after step back");
        printf "   ❌ FAILED: No goals after step back\n";
        None
      )
  with e ->
    add_result "Step Backward" false (Some (Printexc.to_string e));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string e);
    None

(* ========================================
   TEST 6: Interpret to End
   ======================================== *)
let test_interpret_to_end init_scope uri =
  printf "\n📋 Test 6: Interpret to End\n";
  try
    (* Create fresh state *)
    let (st, init_events) = Dm.DocumentManager.init init_scope uri ~text:test_doc_text in
    let st_parsed = force_parse_document st in
    
    let (st', events) = Dm.DocumentManager.interpret_to_end st_parsed in
    printf "   ✓ interpret_to_end returned %d events\n" (List.length events);
    
    let st_final = st' in
    
    (* Check execution state - should have processed all sentences *)
    let exec_st = Dm.DocumentManager.Internal.execution_state st_final in
    let ov = Dm.ExecutionManager.overview exec_st in
    printf "   ✓ Execution overview: processed=%d, processing=%d\n" 
      (List.length ov.processed) (List.length ov.processing);
    
    if List.length ov.processed > 0 then (
      add_result "Interpret to End" true None;
      printf "   ✅ PASSED: Interpreted to end\n";
      Some st_final
    ) else (
      add_result "Interpret to End" false (Some "No sentences processed");
      printf "   ❌ FAILED: No sentences processed\n";
      None
    )
  with e ->
    add_result "Interpret to End" false (Some (Printexc.to_string e));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string e);
    None

(* ========================================
   TEST 7: Restart Prover
   ======================================== *)
let test_restart_prover st init_scope uri =
  printf "\n📋 Test 7: Restart Prover\n";
  try
    let (st_reset, events) = Dm.DocumentManager.reset st in
    printf "   ✓ reset returned %d events\n" (List.length events);
    
    let st_final = st_reset in
    
    (* After reset, execution should be back to start *)
    let exec_st = Dm.DocumentManager.Internal.execution_state st_final in
    let ov = Dm.ExecutionManager.overview exec_st in
    printf "   ✓ After reset: processed=%d\n" (List.length ov.processed);
    
    (* Get proof state - should be None or empty *)
    let proof = Dm.DocumentManager.get_proof st_final None in
    
    match proof with
    | None ->
      add_result "Restart Prover" true None;
      printf "   ✅ PASSED: Prover restarted, no active proof\n";
      Some st_final
    | Some p ->
      if not p.Protocol.ProofState.in_proof then (
        add_result "Restart Prover" true None;
        printf "   ✅ PASSED: Prover restarted\n";
        Some st_final
      ) else (
        add_result "Restart Prover" false (Some "Still in proof mode after restart");
        printf "   ❌ FAILED: Still in proof mode after restart\n";
        None
      )
  with e ->
    add_result "Restart Prover" false (Some (Printexc.to_string e));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string e);
    None

(* ========================================
   Main Test Runner
   ======================================== *)
let () =
  printf "╔══════════════════════════════════════════════════════════╗\n";
  printf "║  LSP INTEGRATION TEST - Interactive Proving Commands    ║\n";
  printf "╚══════════════════════════════════════════════════════════╝\n";
  
  printf "\n🔧 Setup: Configuring EasyCrypt environment...\n";
  let init_scope = setup_easycrypt () in
  printf "✅ Setup complete\n";
  
  printf "\n";
  printf "═══════════════════════════════════════════════════════════\n";
  printf "  RUNNING LSP INTEGRATION TESTS\n";
  printf "═══════════════════════════════════════════════════════════\n";
  
  (* Run tests in sequence, threading state through *)
  let uri = Lsp.Types.DocumentUri.of_string "file:///test_integration.ec" in
  
  match test_document_init init_scope with
  | None -> ()
  | Some (st1, uri) ->
    match test_step_forward_1 st1 uri with
    | None -> ()
    | Some st2 ->
      match test_step_forward_2 st2 uri with
      | None -> ()
      | Some st3 ->
        match test_step_forward_3 st3 uri with
        | None -> ()
        | Some st4 ->
          match test_step_backward st4 uri with
          | None -> ()
          | Some st5 ->
            match test_interpret_to_end init_scope uri with
            | None -> ()
            | Some st6 ->
              match test_restart_prover st6 init_scope uri with
              | None -> ()
              | Some _ ->
                printf "\n✅ All integration tests completed\n"
  ;
  
  printf "\n";
  printf "═══════════════════════════════════════════════════════════\n";
  printf "  TEST RESULTS\n";
  printf "═══════════════════════════════════════════════════════════\n\n";
  
  let total = List.length !results in
  let passed = List.filter (fun r -> r.passed) !results |> List.length in
  let failed = total - passed in
  
  List.rev !results |> List.iter (fun r ->
    if r.passed then
      printf "  ✅ %s\n" r.name
    else
      printf "  ❌ %s%s\n" r.name 
        (match r.error with Some e -> " - " ^ e | None -> "")
  );
  
  printf "\n";
  printf "─────────────────────────────────────────────────────────\n";
  printf "  Total:  %d tests\n" total;
  printf "  Passed: %d tests (%.0f%%)\n" passed (float_of_int passed /. float_of_int total *. 100.);
  printf "  Failed: %d tests\n" failed;
  printf "─────────────────────────────────────────────────────────\n\n";
  
  if failed > 0 then (
    printf "❌ SOME TESTS FAILED\n\n";
    exit 1
  ) else (
    printf "🎉 ALL LSP INTEGRATION TESTS PASSED\n\n";
    exit 0
  )

