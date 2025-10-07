open Printf

let () =
  printf "Testing EasyCrypt initialization...\n";
  
  (* Try to get theories path from dune-site if available *)
  (try
    let open EcLib in
    printf "EcVersion: %s\n" EcVersion.hash;
  with exn ->
    printf "Failed to access EcVersion: %s\n" (Printexc.to_string exn));
  
  (* Try adding theories path before init *)
  let theories = "/home/marcilunga/.opam/easycrypt/lib/easycrypt/theories" in
  printf "Adding theories path: %s\n" theories;
  (try
    EcLib.EcCommands.addidir ~recursive:true theories;
    printf "Successfully added theories path\n";
  with exn ->
    printf "Failed to add theories path: %s\n" (Printexc.to_string exn));
  
  (* Try calling initial *)
  let checkmode : EcLib.EcCommands.checkmode = {
    cm_checkall = false;
    cm_timeout  = 2;
    cm_cpufactor= 1;
    cm_nprovers = 1;
    cm_provers  = None;
    cm_profile  = false;
    cm_iterate  = false;
  } in
  
  printf "Calling EcCommands.initial with boot:true...\n";
  (try
    let _scope = EcLib.EcCommands.initial ~checkmode ~boot:true in
    printf "SUCCESS with boot:true!\n"
  with exn ->
    printf "FAILED with boot:true: %s\n" (Printexc.to_string exn);
    printf "Trying with boot:false...\n";
    try
      let _scope = EcLib.EcCommands.initial ~checkmode ~boot:false in
      printf "SUCCESS with boot:false!\n"
    with exn2 ->
      printf "FAILED with boot:false: %s\n" (Printexc.to_string exn2));
  
  ()
