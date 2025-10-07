open Printf

let () =
  (* Configure load path *)
  let theories_paths = EcLib.EcDuneSites.Sites.theories in
  List.iter (fun theory ->
    let prelude = Filename.concat theory "prelude" in
    EcLib.EcCommands.addidir ~namespace:`System prelude;
    EcLib.EcCommands.addidir ~namespace:`System ~recursive:true theory
  ) theories_paths;
  printf "Configured %d theory paths\n%!" (List.length theories_paths);
  
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
  printf "Initial scope created\n%!";
  
  (* Execute lemma statement *)
  let lemma_text = "lemma test_hyp (P Q : bool): P => Q => P /\\ Q." in
  let reader1 = EcLib.EcIo.from_string lemma_text in
  let globals1 = EcLib.EcIo.parseall reader1 in
  printf "Parsed lemma: %d globals\n%!" (List.length globals1);
  let current_scope = List.fold_left (fun sc (g:EcLib.EcParsetree.global) ->
    EcLib.EcCommands.process_internal EcLib.EcCommands.loader sc g.gl_action
  ) init_scope globals1 in
  
  let print_goals scope_name scope =
    printf "After '%s': xgoal active, started=%b\n%!" scope_name 
      (match EcLib.EcScope.xgoal scope with Some {EcLib.EcScope.puc_active=Some(puc,_)} -> puc.EcLib.EcScope.puc_started | _ -> false);
    match EcLib.EcScope.xgoal scope with
    | None -> printf "  No xgoal\n%!"
    | Some { EcLib.EcScope.puc_active = None; _ } -> printf "  xgoal active=None\n%!"
    | Some { EcLib.EcScope.puc_active = Some (puc, _); _ } ->
      begin match puc.EcLib.EcScope.puc_jdg with
      | EcLib.EcScope.PSNoCheck -> printf "  PSNoCheck\n%!"
      | EcLib.EcScope.PSCheck proof ->
        let opened = EcLib.EcCoreGoal.all_opened proof in
        printf "  PSCheck: %d open goals\n%!" (List.length opened);
        let ppe = EcLib.EcPrinting.PPEnv.ofenv (EcLib.EcScope.env scope) in
        List.iteri (fun idx pg ->
          printf "  Goal %d:\n%!" idx;
          let hyps_str = Format.asprintf "%a" (EcLib.EcPrinting.pp_hyps ppe) pg.EcLib.EcCoreGoal.g_hyps in
          let concl_str = Format.asprintf "%a" (EcLib.EcPrinting.pp_form ppe) pg.EcLib.EcCoreGoal.g_concl in
          printf "    Hypotheses: %s\n%!" hyps_str;
          printf "    Conclusion: %s\n%!" concl_str;
        ) opened
      end
  in
  print_goals "lemma" current_scope;

  (* Execute 'proof.' statement *)
  let proof_text = "proof." in
  let reader2 = EcLib.EcIo.from_string proof_text in
  let globals2 = EcLib.EcIo.parseall reader2 in
  printf "Parsed 'proof': %d globals\n%!" (List.length globals2);
  let current_scope = List.fold_left (fun sc (g:EcLib.EcParsetree.global) ->
    EcLib.EcCommands.process_internal EcLib.EcCommands.loader sc g.gl_action
  ) current_scope globals2 in
  print_goals "proof" current_scope;

  (* Execute 'move=> H_P H_Q.' statement *)
  let move_text = "move=> H_P H_Q." in
  let reader3 = EcLib.EcIo.from_string move_text in
  let globals3 = EcLib.EcIo.parseall reader3 in
  printf "Parsed 'move=> H_P H_Q': %d globals\n%!" (List.length globals3);
  let current_scope = List.fold_left (fun sc (g:EcLib.EcParsetree.global) ->
    EcLib.EcCommands.process_internal EcLib.EcCommands.loader sc g.gl_action
  ) current_scope globals3 in
  print_goals "move=>" current_scope;
  
  (* Now test our adapter directly *)
  printf "\n=== Testing Adapter ===\n%!";
  try
    (* Try to dynlink and use our adapter *)
    let () = Dm.EcAdapter.try_dynlink () in
    printf "Adapter dynlinked successfully\n%!";
    let goals_opt = Dm.EcAdapter.try_goals current_scope in
    match goals_opt with
    | None -> printf "Adapter returned None\n%!"
    | Some goals ->
      printf "Adapter returned %d goals:\n%!" (List.length goals);
      List.iteri (fun idx goal ->
        printf "  Adapter Goal %d:\n%!" idx;
        printf "    ID: %d\n%!" goal.Protocol.ProofState.id;
        printf "    Hypotheses: [%s]\n%!" (String.concat "; " goal.Protocol.ProofState.hypotheses);
        printf "    Goal: %s\n%!" goal.Protocol.ProofState.goal;
      ) goals
  with exn ->
    printf "Adapter test failed: %s\n%!" (Printexc.to_string exn)
