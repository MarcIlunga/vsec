open Printf

let () =
  printf "🧪 Testing Step Forward Flow\n";
  printf "============================\n\n";
  
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
  
  (* Test document with proof (without qed - we can't run SMT provers in tests) *)
  let test_doc_text = "lemma test_hyp (P Q : bool): P => Q => P /\\ Q.\nproof.\n  move=> H_P H_Q." in
  
  (* Parse using EasyCrypt's parseall (synchronous like CLI) *)
  printf "📋 Step 1: Parsing document with EcIo.parseall\n";
  let reader = EcLib.EcIo.from_string test_doc_text in
  let parsed_commands = EcLib.EcIo.parseall reader in
  printf "   ✅ Parsed %d commands\n" (List.length parsed_commands);
  
  (* Execute each command synchronously using process_internal *)
  printf "\n📋 Step 2: Executing commands synchronously (like EasyCrypt CLI)\n";
  let rec execute_commands scope = function
    | [] -> scope
    | cmd :: rest ->
        printf "   Executing command...\n";
        try
          let new_scope = EcLib.EcCommands.process_internal EcLib.EcCommands.loader scope cmd.EcLib.EcParsetree.gl_action in
          execute_commands new_scope rest
        with e ->
          printf "   ❌ ERROR executing command: %s\n" (Printexc.to_string e);
          printf "   This test uses EasyCrypt's process_internal which requires proper theory context\n";
          exit 1
  in
  let final_scope = execute_commands init_scope parsed_commands in
  printf "   ✅ Executed all commands\n";
  
  (* Extract proof state from final scope using adapter *)
  printf "\n📋 Step 3: Extracting proof state from final scope\n";
  let goals_opt = Dm.EcAdapter.try_goals final_scope in
  
  match goals_opt with
  | None ->
    printf "   ❌ ERROR: EcAdapter.try_goals returned None\n";
    printf "   This means xgoal returned None - no active proof\n";
    exit 1
  | Some goals ->
    printf "   ✅ Adapter returned %d goals\n" (List.length goals);
    
    if List.length goals = 0 then (
      printf "   ❌ ERROR: No goals found\n";
      exit 1
    );
    
    let goal = List.hd goals in
    printf "   Goal ID: %d\n" goal.Protocol.ProofState.id;
    printf "   Goal text: %s\n" goal.Protocol.ProofState.goal;
    printf "   Hypotheses count: %d\n" (List.length goal.Protocol.ProofState.hypotheses);
    
    if List.length goal.Protocol.ProofState.hypotheses = 0 then (
      printf "   ❌ ERROR: No hypotheses found!\n";
      printf "\n🔍 This means the adapter or EasyCrypt API is not returning hypotheses\n";
      exit 1
    );
    
    printf "   ✅ Hypotheses found:\n";
    List.iter (fun h -> printf "      - %s\n" h) goal.Protocol.ProofState.hypotheses;
    printf "\n🎉 SUCCESS: Synchronous execution works! Hypotheses extracted!\n"
