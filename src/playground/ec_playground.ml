open Printf

let () =
  (* Probe basic EcVersion metadata *)
  printf "EasyCrypt copyright lines: %d\n"
    (List.length EcLib.EcVersion.copyright);
  printf "EasyCrypt URL: %s\n" EcLib.EcVersion.url;
  printf "EasyCrypt GIT hash: %s\n" EcLib.EcVersion.hash;
  printf "EasyCrypt app name: %s\n" EcLib.EcVersion.app;

  (* Try tokenizing a simple snippet to verify parser wiring *)
  let sample = "lemma L: true. proof. trivial. qed." in
  begin match EcLib.EcIo.lex_single_token sample with
  | None -> printf "lex_single_token: none\n"
  | Some _ -> printf "lex_single_token: ok\n"
  end;

  (* Parse a small EasyCrypt snippet *)
  let reader = EcLib.EcIo.from_string sample in
  (try
     let _prog = EcLib.EcIo.parse reader in
     printf "parse: ok\n"
   with exn ->
     printf "parse: failed: %s\n" (Printexc.to_string exn));
  EcLib.EcIo.finalize reader;

  (* Exercise a tiny part of ecCommands API without global init *)
  let checkmode : EcLib.EcCommands.checkmode = {
    cm_checkall = false;
    cm_timeout  = 2;
    cm_cpufactor= 1;
    cm_nprovers = 1;
    cm_provers  = None;
    cm_profile  = false;
    cm_iterate  = false;
  } in
  (* Initialize a scope to ensure libraries can be resolved if needed. *)
  (try
     EcLib.EcCommands.initialize ~restart:false ~undo:false ~boot:true ~checkmode;
     printf "EcCommands.initialize: ok\n"
   with exn ->
     printf "EcCommands.initialize: failed: %s\n" (Printexc.to_string exn));

  ()


