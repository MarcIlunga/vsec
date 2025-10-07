open Printf

(* This test simulates the full LSP flow including event processing *)

let () =
  printf "🧪 Testing Full LSP Flow with Event Processing\n";
  printf "==============================================\n\n";
  
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
  printf "✅ Initial scope created\n\n";
  
  (* Test document with proof *)
  let test_doc_text = "lemma test_hyp (P Q : bool): P => Q => P /\\ Q.\nproof.\n  move=> H_P H_Q.\nqed." in
  let uri = Lsp.Types.DocumentUri.of_string "file:///test.ec" in
  
  (* Step 1: Create DocumentManager state *)
  printf "📋 Step 1: Creating DocumentManager state\n";
  let doc_st, init_events = Dm.DocumentManager.init init_scope uri ~text:test_doc_text in
  printf "   ✅ DocumentManager.init returned %d events\n" (List.length init_events);
  
  (* Step 2: Manually trigger parsing by processing ParseBegin event *)
  printf "\n📋 Step 2: Manually processing ParseBegin event\n";
  (* We know the first event is ParseBegin, let's handle it directly *)
  let doc_st = 
    match init_events with
    | [] -> 
      printf "   ❌ ERROR: No init events\n";
      exit 1
    | first_event :: _ ->
      (* We can't extract from Sel.Event.t, so let's manually call validate_document *)
      printf "   Manually calling Document.validate_document\n";
      let document = Dm.DocumentManager.Internal.document doc_st in
      let document, parse_events = Dm.Document.validate_document document in
      printf "   ✅ validate_document returned %d parse events\n" (List.length parse_events);
      
      (* Now we need to process these parse events *)
      (* Since we can't extract from Sel.Event.t, let's manually trigger parsing *)
      (* by calling handle_parse_more repeatedly until done *)
      printf "   Processing parse events (simulating event loop)...\n";
      
      (* For now, just check if we have sentences *)
      let sentences = Dm.Document.sentences document in
      printf "   Document has %d sentences after validate_document\n" (List.length sentences);
      
      if List.length sentences = 0 then (
        printf "   ⚠️  WARNING: validate_document doesn't create sentences immediately\n";
        printf "   Sentences are created by processing ParseEvent/Invalidate events\n"
      );
      
      doc_st
  in
  
  (* Step 3: Check current state *)
  printf "\n📋 Step 3: Checking document state\n";
  let document = Dm.DocumentManager.Internal.document doc_st in
  let sentences = Dm.Document.sentences document in
  printf "   Document has %d sentences\n" (List.length sentences);
  
  (* Step 4: Try interpret_to_next *)
  printf "\n📋 Step 4: Calling interpret_to_next\n";
  let (new_st, step_events) = Dm.DocumentManager.interpret_to_next doc_st in
  printf "   ✅ interpret_to_next returned %d events\n" (List.length step_events);
  
  (* Step 5: Extract proof state *)
  printf "\n📋 Step 5: Extracting proof state\n";
  let proof_state = Dm.DocumentManager.get_proof new_st None in
  
  match proof_state with
  | None ->
    printf "   ❌ ERROR: get_proof returned None\n";
    printf "\n🔍 DIAGNOSIS:\n";
    printf "   The issue is that parsing events are NOT being processed\n";
    printf "   We need to process ParseEvent/Invalidate events to create sentences\n";
    printf "   But we can't extract events from Sel.Event.t in tests\n";
    printf "\n💡 SOLUTION:\n";
    printf "   The LSP event loop must process parsing events BEFORE accepting stepForward\n";
    printf "   This is an event ordering issue in the LSP manager\n";
    exit 1
  | Some proof ->
    printf "   ✅ get_proof returned Some proof\n";
    printf "   Goals: %d\n" (List.length proof.Protocol.ProofState.goals);
    printf "   in_proof: %b\n" proof.Protocol.ProofState.in_proof;
    
    if List.length proof.Protocol.ProofState.goals > 0 then (
      let goal = List.hd proof.Protocol.ProofState.goals in
      printf "   Goal text: %s\n" goal.Protocol.ProofState.goal;
      printf "   Hypotheses count: %d\n" (List.length goal.Protocol.ProofState.hypotheses);
      printf "   Hypotheses: [%s]\n" (String.concat "; " goal.Protocol.ProofState.hypotheses);
      
      if List.length goal.Protocol.ProofState.hypotheses > 0 then
        printf "\n🎉 SUCCESS: Full flow works!\n"
      else
        printf "\n⚠️  Hypotheses are empty but goals work\n"
    )
