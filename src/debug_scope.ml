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
  
  let scope1 = List.fold_left (fun sc g ->
    EcLib.EcCommands.process_internal EcLib.EcCommands.loader sc g.EcLib.EcParsetree.gl_action
  ) init_scope globals1 in
  
  (* Check xgoal after lemma *)
  (match EcLib.EcScope.xgoal scope1 with
   | None -> printf "After lemma: No xgoal\n%!"
   | Some { EcLib.EcScope.puc_active = None; _ } -> printf "After lemma: xgoal but no active\n%!"
   | Some { EcLib.EcScope.puc_active = Some (puc, _); _ } ->
     printf "After lemma: xgoal active, started=%b\n%!" puc.EcLib.EcScope.puc_started;
     match puc.EcLib.EcScope.puc_jdg with
     | EcLib.EcScope.PSNoCheck -> printf "  PSNoCheck\n%!"
     | EcLib.EcScope.PSCheck proof ->
       let opened = EcLib.EcCoreGoal.all_opened proof in
       printf "  PSCheck: %d open goals\n%!" (List.length opened);
       List.iteri (fun i pg ->
         let ppe = EcLib.EcPrinting.PPEnv.ofenv (EcLib.EcScope.env scope1) in
         let concl_str = Format.asprintf "%a" (EcLib.EcPrinting.pp_form ppe) pg.EcLib.EcCoreGoal.g_concl in
         let hyps_str = Format.asprintf "%a" (EcLib.EcPrinting.pp_hyps ppe) pg.EcLib.EcCoreGoal.g_hyps in
         printf "  Goal %d:\n%!" i;
         printf "    Hypotheses: %s\n%!" hyps_str;
         printf "    Conclusion: %s\n%!" concl_str
       ) opened);
  
  (* Execute "proof" *)
  let proof_text = "proof." in
  let reader2 = EcLib.EcIo.from_string proof_text in
  let globals2 = EcLib.EcIo.parseall reader2 in
  printf "\nParsed 'proof': %d globals\n%!" (List.length globals2);
  
  let scope2 = List.fold_left (fun sc g ->
    EcLib.EcCommands.process_internal EcLib.EcCommands.loader sc g.EcLib.EcParsetree.gl_action
  ) scope1 globals2 in
  
  (* Check after proof *)
  (match EcLib.EcScope.xgoal scope2 with
   | None -> printf "After 'proof': No xgoal\n%!"
   | Some { EcLib.EcScope.puc_active = None; _ } -> printf "After 'proof': xgoal but no active\n%!"
   | Some { EcLib.EcScope.puc_active = Some (puc, _); _ } ->
     printf "After 'proof': xgoal active, started=%b\n%!" puc.EcLib.EcScope.puc_started;
     match puc.EcLib.EcScope.puc_jdg with
     | EcLib.EcScope.PSNoCheck -> printf "  PSNoCheck\n%!"
     | EcLib.EcScope.PSCheck proof ->
       let opened = EcLib.EcCoreGoal.all_opened proof in
       printf "  PSCheck: %d open goals\n%!" (List.length opened);
       List.iteri (fun i pg ->
         let ppe = EcLib.EcPrinting.PPEnv.ofenv (EcLib.EcScope.env scope2) in
         let concl_str = Format.asprintf "%a" (EcLib.EcPrinting.pp_form ppe) pg.EcLib.EcCoreGoal.g_concl in
         let hyps_str = Format.asprintf "%a" (EcLib.EcPrinting.pp_hyps ppe) pg.EcLib.EcCoreGoal.g_hyps in
         printf "  Goal %d:\n%!" i;
         printf "    Hypotheses: %s\n%!" hyps_str;
         printf "    Conclusion: %s\n%!" concl_str
       ) opened);
  
  (* Execute "move=> H_P H_Q" *)
  let move_text = "move=> H_P H_Q." in
  let reader3 = EcLib.EcIo.from_string move_text in
  let globals3 = EcLib.EcIo.parseall reader3 in
  printf "\nParsed 'move=> H_P H_Q': %d globals\n%!" (List.length globals3);
  
  let scope3 = List.fold_left (fun sc g ->
    EcLib.EcCommands.process_internal EcLib.EcCommands.loader sc g.EcLib.EcParsetree.gl_action
  ) scope2 globals3 in
  
  (* Check after move *)
  (match EcLib.EcScope.xgoal scope3 with
   | None -> printf "After 'move=>': No xgoal\n%!"
   | Some { EcLib.EcScope.puc_active = None; _ } -> printf "After 'move=>': xgoal but no active\n%!"
   | Some { EcLib.EcScope.puc_active = Some (puc, _); _ } ->
     printf "After 'move=>': xgoal active, started=%b\n%!" puc.EcLib.EcScope.puc_started;
     match puc.EcLib.EcScope.puc_jdg with
     | EcLib.EcScope.PSNoCheck -> printf "  PSNoCheck\n%!"
     | EcLib.EcScope.PSCheck proof ->
       let opened = EcLib.EcCoreGoal.all_opened proof in
       printf "  PSCheck: %d open goals\n%!" (List.length opened);
       List.iteri (fun i pg ->
         let ppe = EcLib.EcPrinting.PPEnv.ofenv (EcLib.EcScope.env scope3) in
         let concl_str = Format.asprintf "%a" (EcLib.EcPrinting.pp_form ppe) pg.EcLib.EcCoreGoal.g_concl in
         let hyps_str = Format.asprintf "%a" (EcLib.EcPrinting.pp_hyps ppe) pg.EcLib.EcCoreGoal.g_hyps in
         printf "  Goal %d:\n%!" i;
         printf "    Hypotheses:\n%s\n%!" hyps_str;
         printf "    Conclusion: %s\n%!" concl_str
       ) opened)
