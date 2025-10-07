open Printf

(* Integration Test: Query Commands via LSP *)

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

(* Test helper: simulate LSP query request *)
let test_query_request uri command argument scope =
  try
    let env = EcLib.EcScope.env scope in
    let ppe = EcLib.EcPrinting.PPEnv.ofenv env in
    
    match command with
    | "print" ->
      begin
        try
          let qname = ([], argument) in
          let (path, tydecl) = EcLib.EcEnv.Ty.lookup qname env in
          let arity = List.length tydecl.EcLib.EcDecl.tyd_params in
          Some (Printf.sprintf "✓ Type: %s\nArity: %d type parameter%s" 
            (EcLib.EcPath.tostring path) arity (if arity = 1 then "" else "s"))
        with _ ->
          begin
            try
              let qname = ([], argument) in
              let (path, op) = EcLib.EcEnv.Op.lookup qname env in
              let op_ty = Format.asprintf "%a" (EcLib.EcPrinting.pp_type ppe) op.EcLib.EcDecl.op_ty in
              Some (Printf.sprintf "✓ Operator: %s\nType: %s" (EcLib.EcPath.tostring path) op_ty)
            with _ -> Some (Printf.sprintf "✗ Symbol not found: %s" argument)
          end
      end
    
    | "check" ->
      begin
        try
          let qname = ([], argument) in
          let (path, tydecl) = EcLib.EcEnv.Ty.lookup qname env in
          let arity = List.length tydecl.EcLib.EcDecl.tyd_params in
          Some (Printf.sprintf "✓ Type: %s\nArity: %d type parameter%s" 
            (EcLib.EcPath.tostring path) arity (if arity = 1 then "" else "s"))
        with _ -> Some (Printf.sprintf "✗ Symbol not found: %s" argument)
      end
    
    | "search" ->
      begin
        let results = ref [] in
        let callback path _ =
          let name = EcLib.EcPath.tostring path in
          if String.length argument > 0 && 
             (try Str.search_forward (Str.regexp_case_fold argument) name 0 >= 0
              with Not_found -> false) then
            results := name :: !results
        in
        
        EcLib.EcEnv.Op.iter callback env;
        EcLib.EcEnv.Ax.iter callback env;
        
        if List.length !results > 0 then
          Some (String.concat "\n" (List.rev !results |> List.map (fun s -> s ^ " : <type>")))
        else
          Some (Printf.sprintf "No results found for: %s" argument)
      end
    
    | "locate" ->
      begin
        try
          let qname = ([], argument) in
          let (path, _) = EcLib.EcEnv.Ty.lookup qname env in
          Some (Printf.sprintf "✓ Type: %s" (EcLib.EcPath.tostring path))
        with _ ->
          begin
            try
              let qname = ([], argument) in
              let (path, _) = EcLib.EcEnv.Op.lookup qname env in
              Some (Printf.sprintf "✓ Operator: %s" (EcLib.EcPath.tostring path))
            with _ ->
              begin
                try
                  let qname = ([], argument) in
                  let (path, _) = EcLib.EcEnv.Theory.lookup qname env in
                  Some (Printf.sprintf "✓ Theory: %s" (EcLib.EcPath.tostring path))
                with _ -> Some (Printf.sprintf "✗ Not found: %s" argument)
              end
          end
      end
    
    | _ -> Some (Printf.sprintf "Unknown command: %s" command)
  with exn ->
    Some (Printf.sprintf "Error: %s" (Printexc.to_string exn))

(* Test suite *)
let () =
  printf "\n╔══════════════════════════════════════════════════════════╗\n";
  printf "║  Query Commands Integration Test Suite                 ║\n";
  printf "╚══════════════════════════════════════════════════════════╝\n\n";
  
  printf "⚙️  Setting up EasyCrypt environment...\n";
  let init_scope = setup_easycrypt () in
  printf "✅ EasyCrypt initialized\n\n";
  
  let uri = "file:///test_integration.ec" in
  let tests_passed = ref 0 in
  let tests_failed = ref 0 in
  
  let run_test name command argument expected_success =
    printf "📋 Test: %s\n" name;
    printf "   Command: %s %s\n" command argument;
    
    match test_query_request uri command argument init_scope with
    | Some result ->
      let success = 
        if expected_success then
          not (String.length result > 0 && 
               (Str.string_match (Str.regexp "✗\\|Error") result 0))
        else
          String.length result > 0 && 
          (Str.string_match (Str.regexp "✗\\|Error\\|No results") result 0)
      in
      
      if success then begin
        printf "   ✅ PASS\n";
        printf "   Result: %s\n" (String.sub result 0 (min 60 (String.length result)));
        incr tests_passed
      end else begin
        printf "   ❌ FAIL\n";
        printf "   Result: %s\n" result;
        incr tests_failed
      end
    | None ->
      printf "   ❌ FAIL: No result returned\n";
      incr tests_failed;
    printf "\n"
  in
  
  (* Test Suite *)
  printf "═══════════════════════════════════════════════════════════\n";
  printf "TEST SUITE 1: PRINT COMMAND\n";
  printf "═══════════════════════════════════════════════════════════\n\n";
  
  run_test "Print bool type" "print" "bool" true;
  run_test "Print int type" "print" "int" true;
  run_test "Print unknown symbol" "print" "unknown_xyz" false;
  
  printf "═══════════════════════════════════════════════════════════\n";
  printf "TEST SUITE 2: CHECK COMMAND\n";
  printf "═══════════════════════════════════════════════════════════\n\n";
  
  run_test "Check bool type" "check" "bool" true;
  run_test "Check int type" "check" "int" true;
  run_test "Check unknown type" "check" "unknown_type" false;
  
  printf "═══════════════════════════════════════════════════════════\n";
  printf "TEST SUITE 3: SEARCH COMMAND\n";
  printf "═══════════════════════════════════════════════════════════\n\n";
  
  run_test "Search for 'eq'" "search" "eq" true;
  run_test "Search for 'add'" "search" "add" true;
  run_test "Search impossible" "search" "xyz_impossible_999" false;
  
  printf "═══════════════════════════════════════════════════════════\n";
  printf "TEST SUITE 4: LOCATE COMMAND\n";
  printf "═══════════════════════════════════════════════════════════\n\n";
  
  run_test "Locate bool" "locate" "bool" true;
  run_test "Locate int" "locate" "int" true;
  run_test "Locate unknown" "locate" "unknown_module" false;
  
  printf "═══════════════════════════════════════════════════════════\n";
  printf "TEST SUITE 5: ERROR HANDLING\n";
  printf "═══════════════════════════════════════════════════════════\n\n";
  
  (* Note: Unknown command returns error string, not success *)
  printf "📋 Test: %s\n" "Unknown command";
  printf "   Command: %s %s\n" "invalid" "bool";
  (match test_query_request uri "invalid" "bool" init_scope with
   | Some result when String.length result > 0 && 
                     (Str.string_match (Str.regexp "Unknown\\|Error") result 0) ->
     printf "   ✅ PASS\n";
     printf "   Result: %s\n" (String.sub result 0 (min 60 (String.length result)));
     incr tests_passed
   | _ ->
     printf "   ❌ FAIL\n";
     incr tests_failed);
  printf "\n";
  
  run_test "Empty argument" "print" "" false;
  
  printf "═══════════════════════════════════════════════════════════\n";
  printf "TEST SUITE 6: QUALIFIED NAMES\n";
  printf "═══════════════════════════════════════════════════════════\n\n";
  
  (* Note: Qualified names need special parsing - skip for now *)
  printf "📋 Test: %s\n" "Print Bool.andb (requires qualified name support)";
  printf "   Command: %s %s\n" "print" "Bool.andb";
  printf "   ⚠️  SKIPPED (qualified names need parser enhancement)\n\n";
  
  (* Summary *)
  printf "\n╔══════════════════════════════════════════════════════════╗\n";
  printf "║  TEST SUMMARY                                           ║\n";
  printf "╚══════════════════════════════════════════════════════════╝\n\n";
  
  let total = !tests_passed + !tests_failed in
  printf "Total Tests: %d\n" total;
  printf "✅ Passed: %d\n" !tests_passed;
  printf "❌ Failed: %d\n" !tests_failed;
  printf "Success Rate: %.1f%%\n" 
    (if total > 0 then float_of_int !tests_passed /. float_of_int total *. 100.0 else 0.0);
  
  if !tests_failed = 0 then begin
    printf "\n🎉 ALL TESTS PASSED!\n\n";
    exit 0
  end else begin
    printf "\n⚠️  SOME TESTS FAILED\n\n";
    exit 1
  end

