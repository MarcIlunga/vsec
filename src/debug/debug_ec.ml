let _ =
  Printf.printf "Starting EasyCrypt test...\n%!";
  try
    Printf.printf "Creating GState...\n%!";
    let gstate = EcLib.EcGState.create () in
    Printf.printf "GState created successfully\n%!";
    Printf.printf "Creating Scope...\n%!";
    let _scope = EcLib.EcScope.empty gstate in
    Printf.printf "Scope created successfully\n%!";
    Printf.printf "EasyCrypt initialization complete\n%!"
  with exn ->
    Printf.printf "ERROR: %s\n%!" (Printexc.to_string exn);
    Printf.printf "Backtrace: %s\n%!" (Printexc.get_backtrace ())