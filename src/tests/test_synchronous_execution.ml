open Printf

(* Test synchronous execution in interpret_to_next *)

let () =
  printf "🧪 Testing Synchronous Execution (EasyCrypt CLI pattern)\n";
  printf "=======================================================\n\n";
  
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
  
  (* Step 1: Create DocumentManager *)
  printf "📋 Step 1: Creating DocumentManager state\n";
  let (doc_st, init_events) = Dm.DocumentManager.init init_scope uri ~text:test_doc_text in
  printf "   ✅ Created with %d initial events\n" (List.length init_events);
  
  (* Process initial parsing events (simulate main loop) *)
  printf "   🔧 Processing initial parsing events...\n";
  let rec process_events st = function
    | [] -> st
    | ev :: rest ->
        (* Extract event from Sel.Event.t - we can't do this! Events are async *)
        (* Instead, we need to trigger parsing differently *)
        process_events st rest
  in
  let doc_st = doc_st in  (* Can't process Sel.Event.t synchronously *)
  
  (* WORKAROUND: Force sentence creation by calling validate_document *)
  printf "   🔧 Forcing document parsing synchronously for test...\n";
  let doc_text = Dm.RawDocument.text (Dm.DocumentManager.Internal.raw_document doc_st) in
  let doc_length = String.length doc_text in
  (* Trigger parsing by validating the entire document *)
  let parse_info = { Dm.Document.parsed_loc = doc_length; feedback = [] } in
  let doc_st = Dm.DocumentManager.Internal.validate_document doc_st parse_info in
  
  (* Check number of sentences after forcing parse *)
  let sentences = Dm.Document.sentences (Dm.DocumentManager.Internal.document doc_st) in
  printf "   📊 Sentences after parsing: %d\n" (List.length sentences);
  
  if List.length sentences = 0 then (
    printf "   ❌ ERROR: Still no sentences after forced parsing!\n";
    exit 1
  );
  
  (* Step 2: Call interpret_to_next (first step - lemma) *)
  printf "\n📋 Step 2: First stepForward (execute lemma)\n";
  let (st1, events1) = Dm.DocumentManager.interpret_to_next doc_st in
  printf "   ✅ interpret_to_next returned %d events\n" (List.length events1);
  
  (* Step 3: Check proof state after first step *)
  printf "\n📋 Step 3: Checking proof state after lemma\n";
  let proof1 = Dm.DocumentManager.get_proof st1 None in
  (match proof1 with
   | None -> 
     printf "   ⚠️  No proof state (expected - lemma statement doesn't start proof)\n"
   | Some p ->
     printf "   ✅ Proof state found: %d goals, in_proof=%b\n" 
       (List.length p.Protocol.ProofState.goals) p.Protocol.ProofState.in_proof);
  
  (* Step 4: Second stepForward (execute proof.) *)
  printf "\n📋 Step 4: Second stepForward (execute 'proof.')\n";
  let (st2, events2) = Dm.DocumentManager.interpret_to_next st1 in
  printf "   ✅ interpret_to_next returned %d events\n" (List.length events2);
  
  (* Step 5: Check proof state after proof keyword *)
  printf "\n📋 Step 5: Checking proof state after 'proof.'\n";
  let proof2 = Dm.DocumentManager.get_proof st2 None in
  (match proof2 with
   | None -> 
     printf "   ❌ ERROR: No proof state after 'proof.'\n";
     exit 1
   | Some p ->
     printf "   ✅ Proof state: %d goals, in_proof=%b\n" 
       (List.length p.Protocol.ProofState.goals) p.Protocol.ProofState.in_proof;
     if not p.Protocol.ProofState.in_proof then (
       printf "   ❌ ERROR: in_proof should be true\n";
       exit 1
     ));
  
  (* Step 6: Third stepForward (execute 'move=> H_P H_Q.') *)
  printf "\n📋 Step 6: Third stepForward (execute 'move=> H_P H_Q.')\n";
  let (st3, events3) = Dm.DocumentManager.interpret_to_next st2 in
  printf "   ✅ interpret_to_next returned %d events\n" (List.length events3);
  
  (* Step 7: Check proof state - THIS IS THE CRITICAL TEST *)
  printf "\n📋 Step 7: Checking proof state after 'move=> H_P H_Q.'\n";
  let proof3 = Dm.DocumentManager.get_proof st3 None in
  (match proof3 with
   | None -> 
     printf "   ❌ ERROR: No proof state after tactic\n";
     exit 1
   | Some p ->
     printf "   ✅ Proof state: %d goals, in_proof=%b\n" 
       (List.length p.Protocol.ProofState.goals) p.Protocol.ProofState.in_proof;
     
     if List.length p.Protocol.ProofState.goals = 0 then (
       printf "   ❌ ERROR: No goals found\n";
       exit 1
     );
     
     let goal = List.hd p.Protocol.ProofState.goals in
     printf "   Goal: %s\n" goal.Protocol.ProofState.goal;
     printf "   Hypotheses count: %d\n" (List.length goal.Protocol.ProofState.hypotheses);
     
     if List.length goal.Protocol.ProofState.hypotheses = 0 then (
       printf "   ❌ ERROR: No hypotheses extracted!\n";
       printf "   🔍 This means synchronous execution is NOT updating current_scope correctly\n";
       exit 1
     );
     
     printf "   ✅ Hypotheses found:\n";
     List.iter (fun h -> printf "      - %s\n" h) goal.Protocol.ProofState.hypotheses;
     
     (* Check for expected hypotheses *)
     let has_h_p = List.exists (fun h -> String.contains h 'H' && String.contains h 'P') goal.Protocol.ProofState.hypotheses in
     let has_h_q = List.exists (fun h -> String.contains h 'H' && String.contains h 'Q') goal.Protocol.ProofState.hypotheses in
     
     if has_h_p && has_h_q then (
       printf "\n🎉 SUCCESS: Synchronous execution works! Hypotheses extracted correctly!\n"
     ) else (
       printf "\n⚠️  WARNING: Expected hypotheses H_P and H_Q not found\n";
       printf "   Found: [%s]\n" (String.concat "; " goal.Protocol.ProofState.hypotheses);
       exit 1
     )
  )

