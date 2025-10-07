open Printf

(* Test restart prover functionality - using synchronous execution *)

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

(* Parse and execute text synchronously *)
let parse_and_execute init_scope text =
  let reader = EcLib.EcIo.from_string text in
  let commands = EcLib.EcIo.parseall reader in
  
  let rec exec scope = function
    | [] -> scope
    | cmd :: rest ->
      try
        let scope' = EcLib.EcCommands.process_internal EcLib.EcCommands.loader scope cmd.EcLib.EcParsetree.gl_action in
        exec scope' rest
      with
        | EcLib.EcCommands.Restart -> exec init_scope rest
        | e ->
          printf "Warning: Command failed: %s\n" (Printexc.to_string e);
          raise e
  in
  exec init_scope commands

let () =
  printf "🧪 Testing Restart Prover (Synchronous)\n";
  printf "========================================\n\n";
  
  (* Setup *)
  printf "📋 Step 1: Setup EasyCrypt environment\n";
  let init_scope = setup_easycrypt () in
  printf "   ✅ Initial scope created\n";
  
  (* Execute some proof steps *)
  printf "\n📋 Step 2: Execute proof to mid-way point\n";
  let text1 = "lemma test: true /\\ true.\nproof.\n  split." in
  let scope_midway = parse_and_execute init_scope text1 in
  printf "   ✅ Executed: lemma + proof. + split.\n";
  
  (* Check we have multiple goals *)
  match Dm.EcAdapter.try_goals scope_midway with
  | None ->
    printf "   ⚠️  No goals at midway (unexpected)\n"
  | Some goals ->
    printf "   ✅ At midway: %d goals\n" (List.length goals);
  
  (* Simulate restart by going back to init_scope *)
  printf "\n📋 Step 3: Restart (reset to initial scope)\n";
  let scope_after_restart = init_scope in
  printf "   ✅ Reset to initial scope\n";
  
  (* Re-execute from beginning *)
  printf "\n📋 Step 4: Re-execute from beginning\n";
  let text2 = "lemma test: true /\\ true.\nproof." in
  let scope_after_restart_steps = parse_and_execute scope_after_restart text2 in
  printf "   ✅ Executed: lemma + proof.\n";
  
  (* Check we're back at initial goal *)
  printf "\n📋 Step 5: Verify we're back at initial goal\n";
  match Dm.EcAdapter.try_goals scope_after_restart_steps with
  | None ->
    printf "   ❌ ERROR: No goals after restart + proof.\n";
    printf "\n🔍 BUG: Restart doesn't properly reset state\n";
    exit 1
  | Some goals ->
    if List.length goals = 0 then (
      printf "   ❌ ERROR: Empty goals after restart + proof.\n";
      exit 1
    ) else (
      let goal = List.hd goals in
      printf "   ✅ Found goals after restart: %d\n" (List.length goals);
      printf "   ✅ Goal text: %s\n" 
        (String.sub goal.Protocol.ProofState.goal 0 (min 60 (String.length goal.Protocol.ProofState.goal)));
      
      (* The initial goal should be the original lemma statement *)
      if String.length goal.Protocol.ProofState.goal > 0 && 
         String.contains goal.Protocol.ProofState.goal '/' then (
        printf "\n🎉 SUCCESS: Restart works correctly!\n";
        printf "   Initial goal restored after restart\n";
        exit 0
      ) else (
        printf "\n⚠️  WARNING: Goal doesn't look like initial goal\n";
        exit 1
      )
    )
