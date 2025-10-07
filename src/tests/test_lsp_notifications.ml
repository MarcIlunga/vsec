open Printf

let () =
  printf "🧪 Testing LSP Notification Handling\n";
  printf "=====================================\n\n";
  
  (* Configure load path *)
  let theories_paths = EcLib.EcDuneSites.Sites.theories in
  List.iter (fun theory ->
    let prelude = Filename.concat theory "prelude" in
    EcLib.EcCommands.addidir ~namespace:`System prelude;
    EcLib.EcCommands.addidir ~namespace:`System ~recursive:true theory
  ) theories_paths;
  printf "✅ Configured %d theory paths\n" (List.length theories_paths);
  
  (* Initialize EasyCrypt *)
  let checkmode = {
    EcLib.EcCommands.cm_checkall = false;
    cm_timeout = 5;
    cm_cpufactor = 1;
    cm_nprovers = 1;
    cm_provers = None;
    cm_profile = false;
    cm_iterate = false;
  } in
  
  let init_scope = EcLib.EcCommands.initial ~checkmode ~boot:false in
  printf "✅ Initial scope created\n";
  
  (* Test 1: Protocol Decoding *)
  printf "\n📋 Test 1: Protocol Decoding\n";
  printf "----------------------------\n";
  
  let test_notification = Jsonrpc.Notification.{
    method_ = "prover/stepForward";
    params = Some (`Assoc [
      ("textDocument", `Assoc [
        ("uri", `String "file:///test.ec");
        ("version", `Int 1)
      ])
    ])
  } in
  
  (match Protocol.ExtProtocol.Notification.Client.of_jsonrpc test_notification with
  | Ok (Protocol.ExtProtocol.Notification.Client.StepForward params) ->
    printf "✅ StepForward notification decoded successfully\n";
    printf "   URI: %s\n" (Lsp.Types.DocumentUri.to_string params.textDocument.uri)
  | Ok other ->
    printf "❌ Wrong notification type: %s\n" (match other with
      | Protocol.ExtProtocol.Notification.Client.InterpretToPoint _ -> "InterpretToPoint"
      | Protocol.ExtProtocol.Notification.Client.InterpretToEnd _ -> "InterpretToEnd"
      | Protocol.ExtProtocol.Notification.Client.StepBackward _ -> "StepBackward"
      | Protocol.ExtProtocol.Notification.Client.RestartProver _ -> "RestartProver"
      | Protocol.ExtProtocol.Notification.Client.Std _ -> "Std")
  | Error e ->
    printf "❌ Protocol decoding failed: %s\n" e);
  
  (* Test 2: Document Manager Integration *)
  printf "\n📋 Test 2: Document Manager Integration\n";
  printf "--------------------------------------\n";
  
  let test_doc_text = "lemma test_hyp (P Q : bool): P => Q => P /\\ Q.\nproof.\n  move=> H_P H_Q.\nqed." in
  let uri = Lsp.Types.DocumentUri.of_string "file:///test.ec" in
  
  (* Create document manager state *)
  let doc_st, events = Dm.DocumentManager.init init_scope uri ~text:test_doc_text in
  printf "✅ Document created with %d events\n" (List.length events);
  
  (* Test 3: Document State Check *)
  printf "\n📋 Test 3: Document State Check\n";
  printf "-------------------------------\n";
  
  let sentences = Dm.Document.sentences doc_st.document in
  printf "   Sentences in document: %d\n" (List.length sentences);
  List.iteri (fun i sent ->
    printf "   Sentence %d: %s\n" i (String.sub sent.Dm.Document.raw 0 (min 50 (String.length sent.Dm.Document.raw)))
  ) sentences;
  
  (* Test 4: Step Forward Simulation *)
  printf "\n📋 Test 4: Step Forward Simulation\n";
  printf "----------------------------------\n";
  
  (* Simulate step forward by interpreting to next *)
  let (new_st, step_events) = Dm.DocumentManager.interpret_to_next doc_st in
  printf "✅ Step forward executed, %d events generated\n" (List.length step_events);
  
  (* Test 5: Proof State Extraction *)
  printf "\n📋 Test 5: Proof State Extraction\n";
  printf "----------------------------------\n";
  
  (* Extract proof state using current_scope *)
  let proof_state = Dm.DocumentManager.get_proof new_st None in
  (match proof_state with
  | Some proof ->
    printf "✅ Proof state extracted successfully\n";
    printf "   Goals: %d\n" (List.length proof.Protocol.ProofState.goals);
    printf "   In proof: %b\n" proof.Protocol.ProofState.in_proof;
    if proof.Protocol.ProofState.goals <> [] then (
      let goal = List.hd proof.Protocol.ProofState.goals in
      printf "   First goal: %s\n" goal.Protocol.ProofState.goal;
      printf "   Hypotheses: [%s]\n" (String.concat "; " goal.Protocol.ProofState.hypotheses)
    )
  | None ->
    printf "❌ No proof state extracted\n");
  
  (* Test 6: Second Step Forward *)
  printf "\n📋 Test 6: Second Step Forward\n";
  printf "------------------------------\n";
  
  let (final_st, final_events) = Dm.DocumentManager.interpret_to_next new_st in
  printf "✅ Second step forward executed, %d events generated\n" (List.length final_events);
  
  (* Extract final proof state *)
  let final_proof_state = Dm.DocumentManager.get_proof final_st None in
  (match final_proof_state with
  | Some proof ->
    printf "✅ Final proof state extracted\n";
    printf "   Goals: %d\n" (List.length proof.Protocol.ProofState.goals);
    printf "   In proof: %b\n" proof.Protocol.ProofState.in_proof;
    if proof.Protocol.ProofState.goals <> [] then (
      let goal = List.hd proof.Protocol.ProofState.goals in
      printf "   First goal: %s\n" goal.Protocol.ProofState.goal;
      printf "   Hypotheses: [%s]\n" (String.concat "; " goal.Protocol.ProofState.hypotheses);
      
      (* Check if hypotheses are correct *)
      let has_h_p = List.exists (fun h -> String.contains h 'H' && String.contains h 'P') goal.Protocol.ProofState.hypotheses in
      let has_h_q = List.exists (fun h -> String.contains h 'H' && String.contains h 'Q') goal.Protocol.ProofState.hypotheses in
      if has_h_p && has_h_q then
        printf "✅ Hypotheses extraction working correctly!\n"
      else
        printf "❌ Hypotheses extraction failed - missing H_P or H_Q\n"
    )
  | None ->
    printf "❌ No final proof state extracted\n");
  
  printf "\n🎉 LSP Notification Tests Complete\n"
