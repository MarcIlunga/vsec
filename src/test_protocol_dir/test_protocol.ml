(* Test that we can access Protocol modules like VSRocq *)
open Protocol.LspWrapper

let test_position () =
  let pos = Position.{ line = 1; character = 5 } in
  let pos_str = Position.to_string pos in
  Printf.printf "Position: %s\n" pos_str

let test_range () = 
  let start_pos = Position.{ line = 1; character = 0 } in
  let end_pos = Position.{ line = 1; character = 10 } in
  let range = Range.{ start = start_pos; end_ = end_pos } in
  let range_str = Range.to_string range in
  Printf.printf "Range: %s\n" range_str

let () =
  print_endline "Testing Protocol access...";
  test_position ();
  test_range ();
  print_endline "Protocol test completed!"