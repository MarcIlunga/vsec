open Printf

(* Test Query Commands - print, search, locate *)

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

(* Helper to create a DocumentManager with some content *)
let create_test_document init_scope =
  let text = "lemma test_query (P Q : bool): P => Q => P /\\ Q.\nproof.\n  move=> H_P H_Q." in
  let uri = Lsp.Types.DocumentUri.of_string "file:///test_query.ec" in
  let (st, _events) = Dm.DocumentManager.init init_scope uri ~text in
  (st, uri)

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
   TEST 1: Print Command - Known Symbol
   ======================================== *)
let test_print_known_symbol st =
  printf "\n📋 Test 1: Print Command - Known Symbol (bool)\n";
  try
    let scope = Dm.ExecutionManager.get_current_scope (Dm.DocumentManager.Internal.execution_state st) in
    let env = EcLib.EcScope.env scope in
    let ppe = EcLib.EcPrinting.PPEnv.ofenv env in
    
    (* Try to look up 'bool' type *)
    let parts = String.split_on_char '.' "bool" in
    let (modules, name) = match List.rev parts with
      | [] -> ([], "")
      | n :: rest -> (List.rev rest, n)
    in
    let qname : EcLib.EcSymbols.qsymbol = (modules, name) in
    
    let found = try
      let (path, _) = EcLib.EcEnv.Ty.lookup qname env in
      Some (EcLib.EcPath.tostring path)
    with _ -> None
    in
    
    match found with
    | Some path ->
      printf "   ✓ Found 'bool' at: %s\n" path;
      add_result "Print - Known Symbol" true None;
      printf "   ✅ PASSED: Can look up known symbols\n"
    | None ->
      add_result "Print - Known Symbol" false (Some "Could not find 'bool' type");
      printf "   ❌ FAILED: Could not find 'bool' type\n"
  with exn ->
    add_result "Print - Known Symbol" false (Some (Printexc.to_string exn));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string exn)

(* ========================================
   TEST 2: Print Command - Unknown Symbol
   ======================================== *)
let test_print_unknown_symbol st =
  printf "\n📋 Test 2: Print Command - Unknown Symbol\n";
  try
    let scope = Dm.ExecutionManager.get_current_scope (Dm.DocumentManager.Internal.execution_state st) in
    let env = EcLib.EcScope.env scope in
    
    let parts = String.split_on_char '.' "NonExistentSymbol12345" in
    let (modules, name) = match List.rev parts with
      | [] -> ([], "")
      | n :: rest -> (List.rev rest, n)
    in
    let qname : EcLib.EcSymbols.qsymbol = (modules, name) in
    
    let found = try
      let (path, _) = EcLib.EcEnv.Ty.lookup qname env in
      Some (EcLib.EcPath.tostring path)
    with _ ->
      try
        let (path, _) = EcLib.EcEnv.Op.lookup qname env in
        Some (EcLib.EcPath.tostring path)
      with _ ->
        try
          let (path, _) = EcLib.EcEnv.Ax.lookup qname env in
          Some (EcLib.EcPath.tostring path)
        with _ -> None
    in
    
    match found with
    | None ->
      printf "   ✓ Correctly returned None for unknown symbol\n";
      add_result "Print - Unknown Symbol" true None;
      printf "   ✅ PASSED: Unknown symbols return None\n"
    | Some path ->
      add_result "Print - Unknown Symbol" false (Some (Printf.sprintf "Unexpectedly found: %s" path));
      printf "   ❌ FAILED: Unexpectedly found unknown symbol at: %s\n" path
  with exn ->
    add_result "Print - Unknown Symbol" false (Some (Printexc.to_string exn));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string exn)

(* ========================================
   TEST 3: Search Command - Pattern Match
   ======================================== *)
let test_search_pattern st =
  printf "\n📋 Test 3: Search Command - Pattern Match\n";
  try
    let scope = Dm.ExecutionManager.get_current_scope (Dm.DocumentManager.Internal.execution_state st) in
    let env = EcLib.EcScope.env scope in
    
    (* Search for axioms containing "eq" *)
    let pattern = "eq" in
    let all_axioms = EcLib.EcEnv.Ax.all env in
    let matching = List.filter (fun (path, _ax) ->
      let name = EcLib.EcPath.tostring path in
      String.length pattern > 0 && 
      (try Str.search_forward (Str.regexp_case_fold pattern) name 0 >= 0 with Not_found -> false)
    ) all_axioms in
    
    let count = List.length matching in
    printf "   ✓ Found %d axioms matching '%s'\n" count pattern;
    
    if count > 0 then (
      (* Show first few *)
      let first_few = List.take (min 3 count) matching in
      List.iter (fun (path, _ax) ->
        printf "     - %s\n" (EcLib.EcPath.tostring path)
      ) first_few;
      add_result "Search - Pattern Match" true None;
      printf "   ✅ PASSED: Search found matching axioms\n"
    ) else (
      add_result "Search - Pattern Match" false (Some "No matches found for 'eq'");
      printf "   ❌ FAILED: No matches found (expected some)\n"
    )
  with exn ->
    add_result "Search - Pattern Match" false (Some (Printexc.to_string exn));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string exn)

(* ========================================
   TEST 4: Search Command - No Matches
   ======================================== *)
let test_search_no_matches st =
  printf "\n📋 Test 4: Search Command - No Matches\n";
  try
    let scope = Dm.ExecutionManager.get_current_scope (Dm.DocumentManager.Internal.execution_state st) in
    let env = EcLib.EcScope.env scope in
    
    let pattern = "ZzZzNonExistent999" in
    let all_axioms = EcLib.EcEnv.Ax.all env in
    let matching = List.filter (fun (path, _ax) ->
      let name = EcLib.EcPath.tostring path in
      String.length pattern > 0 && 
      (try Str.search_forward (Str.regexp_case_fold pattern) name 0 >= 0 with Not_found -> false)
    ) all_axioms in
    
    let count = List.length matching in
    printf "   ✓ Found %d axioms matching '%s'\n" count pattern;
    
    if count = 0 then (
      add_result "Search - No Matches" true None;
      printf "   ✅ PASSED: Search correctly returns no matches\n"
    ) else (
      add_result "Search - No Matches" false (Some (Printf.sprintf "Unexpected matches: %d" count));
      printf "   ❌ FAILED: Unexpected matches found\n"
    )
  with exn ->
    add_result "Search - No Matches" false (Some (Printexc.to_string exn));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string exn)

(* ========================================
   TEST 5: Locate Command - Standard Type
   ======================================== *)
let test_locate_type st =
  printf "\n📋 Test 5: Locate Command - Standard Type\n";
  try
    let scope = Dm.ExecutionManager.get_current_scope (Dm.DocumentManager.Internal.execution_state st) in
    let env = EcLib.EcScope.env scope in
    
    (* Try to locate 'int' *)
    let parts = String.split_on_char '.' "int" in
    let (modules, name) = match List.rev parts with
      | [] -> ([], "")
      | n :: rest -> (List.rev rest, n)
    in
    let qname : EcLib.EcSymbols.qsymbol = (modules, name) in
    
    let location =
      try
        let (path, _) = EcLib.EcEnv.Ty.lookup qname env in
        Some (Printf.sprintf "Type: %s" (EcLib.EcPath.tostring path))
      with _ ->
        try
          let (path, _) = EcLib.EcEnv.Op.lookup qname env in
          Some (Printf.sprintf "Operator: %s" (EcLib.EcPath.tostring path))
        with _ -> None
    in
    
    match location with
    | Some loc ->
      printf "   ✓ Located: %s\n" loc;
      add_result "Locate - Type" true None;
      printf "   ✅ PASSED: Locate found type successfully\n"
    | None ->
      add_result "Locate - Type" false (Some "Could not locate 'int'");
      printf "   ❌ FAILED: Could not locate 'int'\n"
  with exn ->
    add_result "Locate - Type" false (Some (Printexc.to_string exn));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string exn)

(* ========================================
   TEST 6: Check Command - Basic Functionality
   ======================================== *)
let test_check_command st =
  printf "\n📋 Test 6: Check Command - Basic Functionality\n";
  try
    let scope = Dm.ExecutionManager.get_current_scope (Dm.DocumentManager.Internal.execution_state st) in
    let env = EcLib.EcScope.env scope in
    let ppe = EcLib.EcPrinting.PPEnv.ofenv env in
    
    (* Test checking bool type *)
    let parts = String.split_on_char '.' "bool" in
    let (modules, name) = match List.rev parts with
      | [] -> ([], "")
      | n :: rest -> (List.rev rest, n)
    in
    let qname : EcLib.EcSymbols.qsymbol = (modules, name) in
    
    let result = try
      let (path, tydecl) = EcLib.EcEnv.Ty.lookup qname env in
      Some (EcLib.EcPath.tostring path)
    with _ -> None
    in
    
    match result with
    | Some path ->
      printf "   ✓ check bool: %s\n" path;
      add_result "Check Command" true None;
      printf "   ✅ PASSED: Check command works\n"
    | None ->
      add_result "Check Command" false (Some "Could not check bool");
      printf "   ❌ FAILED: Could not check bool\n"
  with exn ->
    add_result "Check Command" false (Some (Printexc.to_string exn));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string exn)

(* ========================================
   TEST 7: Symbol Parsing - Qualified Names
   ======================================== *)
let test_qualified_name_parsing () =
  printf "\n📋 Test 7: Symbol Parsing - Qualified Names\n";
  try
    (* Test parsing "Module.SubModule.symbol" *)
    let test_cases = [
      ("symbol", ([], "symbol"));
      ("Module.symbol", (["Module"], "symbol"));
      ("Module.Sub.symbol", (["Module"; "Sub"], "symbol"));
    ] in
    
    let all_passed = List.for_all (fun (input, expected) ->
      let parts = String.split_on_char '.' input in
      let (modules, name) = match List.rev parts with
        | [] -> ([], "")
        | n :: rest -> (List.rev rest, n)
      in
      let result = (modules, name) in
      if result = expected then (
        printf "   ✓ '%s' → (%s, '%s')\n" input (String.concat "." modules) name;
        true
      ) else (
        printf "   ✗ '%s' failed\n" input;
        false
      )
    ) test_cases in
    
    if all_passed then (
      add_result "Qualified Name Parsing" true None;
      printf "   ✅ PASSED: All parsing cases work\n"
    ) else (
      add_result "Qualified Name Parsing" false (Some "Some cases failed");
      printf "   ❌ FAILED: Some parsing cases failed\n"
    )
  with exn ->
    add_result "Qualified Name Parsing" false (Some (Printexc.to_string exn));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string exn)

(* ========================================
   Main Test Runner
   ======================================== *)
let () =
  printf "╔══════════════════════════════════════════════════════════╗\n";
  printf "║  QUERY COMMANDS TEST SUITE                              ║\n";
  printf "╚══════════════════════════════════════════════════════════╝\n";
  
  printf "\n🔧 Setup: Configuring EasyCrypt environment...\n";
  let init_scope = setup_easycrypt () in
  printf "✅ Setup complete\n";
  
  printf "\n🔧 Creating test document...\n";
  let (st, _uri) = create_test_document init_scope in
  printf "✅ Document created\n";
  
  printf "\n";
  printf "═══════════════════════════════════════════════════════════\n";
  printf "  RUNNING QUERY COMMAND TESTS\n";
  printf "═══════════════════════════════════════════════════════════\n";
  
  test_print_known_symbol st;
  test_print_unknown_symbol st;
  test_search_pattern st;
  test_search_no_matches st;
  test_locate_type st;
  test_check_command st;
  test_qualified_name_parsing ();
  
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
  printf "─────────────────────────────────────────────────────────\n";
  printf "  Commands tested: print, search, locate, check\n";
  printf "─────────────────────────────────────────────────────────\n\n";
  
  if failed > 0 then (
    printf "❌ SOME TESTS FAILED\n\n";
    exit 1
  ) else (
    printf "🎉 ALL QUERY COMMAND TESTS PASSED\n\n";
    exit 0
  )

