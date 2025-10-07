open Printf

(* Test multiple goals extraction after split tactic *)

let () =
  printf "🧪 Testing Multiple Goals Extraction\n";
  printf "===================================\n\n";
  
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
  
  (* Test with split tactic *)
  printf "📋 Testing split tactic (should create 2 subgoals)\n";
  
  let lemma_text = "lemma split_test: true /\\ false." in
  let proof_text = "proof." in
  let split_text = "split." in
  
  (* Execute lemma *)
  let reader1 = EcLib.EcIo.from_string lemma_text in
  let globals1 = EcLib.EcIo.parseall reader1 in
  let scope1 = List.fold_left (fun sc (g:EcLib.EcParsetree.global) ->
    EcLib.EcCommands.process_internal EcLib.EcCommands.loader sc g.gl_action
  ) init_scope globals1 in
  printf "   ✅ Executed: %s\n" lemma_text;
  
  (* Execute proof *)
  let reader2 = EcLib.EcIo.from_string proof_text in
  let globals2 = EcLib.EcIo.parseall reader2 in
  let scope2 = List.fold_left (fun sc (g:EcLib.EcParsetree.global) ->
    EcLib.EcCommands.process_internal EcLib.EcCommands.loader sc g.gl_action
  ) scope1 globals2 in
  printf "   ✅ Executed: %s\n" proof_text;
  
  (* Execute split *)
  let reader3 = EcLib.EcIo.from_string split_text in
  let globals3 = EcLib.EcIo.parseall reader3 in
  let scope3 = List.fold_left (fun sc (g:EcLib.EcParsetree.global) ->
    EcLib.EcCommands.process_internal EcLib.EcCommands.loader sc g.gl_action
  ) scope2 globals3 in
  printf "   ✅ Executed: %s\n" split_text;
  
  (* Check proof state *)
  printf "\n📋 Extracting proof state after split\n";
  let xgoal_opt = EcLib.EcScope.xgoal scope3 in
  match xgoal_opt with
  | None ->
    printf "   ❌ ERROR: No xgoal found\n";
    exit 1
  | Some xgoal ->
    match xgoal.EcLib.EcScope.puc_active with
    | None ->
      printf "   ❌ ERROR: No active proof\n";
      exit 1
    | Some (puc, _) ->
      match puc.EcLib.EcScope.puc_jdg with
      | EcLib.EcScope.PSNoCheck ->
        printf "   ❌ ERROR: PSNoCheck (no proof checking)\n";
        exit 1
      | EcLib.EcScope.PSCheck proof ->
        let opened_goals = EcLib.EcCoreGoal.all_opened proof in
        printf "   ✅ Found %d opened goals\n" (List.length opened_goals);
        
        if List.length opened_goals < 2 then (
          printf "\n🔍 BUG #5: Multiple Goals Not Properly Extracted\n";
          printf "   Expected: 2 subgoals after 'split' tactic\n";
          printf "   Actual: %d goals\n" (List.length opened_goals);
          printf "\n💡 INVESTIGATION NEEDED:\n";
          printf "   - Check if EcCoreGoal.all_opened returns all subgoals or just focused\n";
          printf "   - May need to use different API to get all subgoals\n";
          printf "   - Check EasyCrypt's proof state structure for multiple goals\n";
          exit 1
        ) else (
          printf "\n🎉 SUCCESS: Multiple goals extracted correctly!\n";
          let ppe = EcLib.EcPrinting.PPEnv.ofenv (EcLib.EcScope.env scope3) in
          List.iteri (fun idx pg ->
            let goal_str = Format.asprintf "%a" (EcLib.EcPrinting.pp_form ppe) pg.EcLib.EcCoreGoal.g_concl in
            printf "   Goal %d: %s\n" (idx + 1) goal_str
          ) opened_goals
        )
