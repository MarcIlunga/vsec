open Dm

let%test_module "pg_compat_parsing" = (module struct
  module Pg = Pg_compat

  let sample_with_header_and_sep =
    "[1|check]>\n" ^
    "Current goal (remaining: 1)\n" ^
    "Type variables: 'a\n" ^
    "x: bool\n" ^
    "-----\n" ^
    "true\n" ^
    "[1|check]>\n"

  let sample_single_line_no_sep =
    "[2|check]>\n" ^
    "Current goal\n" ^
    "P -> Q\n" ^
    "[2|check]>\n"

  let sample_no_more_goals =
    "[3|check]>\n" ^
    "No more goals.\n" ^
    "[3|check]>\n"

  let sample_multiple_goals =
    "[4|check]>\n" ^
    "Current goal (remaining: 3)\n" ^
    "Type variables: 'a\n" ^
    "x: bool\n" ^
    "-----\n" ^
    "true\n" ^
    "\n" ^
    "Goal #2\n" ^
    "false \/ true\n" ^
    "\n" ^
    "Goal #3\n" ^
    "P -> Q\n" ^
    "[4|check]>\n"

  let sample_multiline_goals =
    "[8|check]>\n" ^
    "Current goal (remaining: 2)\n" ^
    "-----\n" ^
    "(forall x,\n" ^
    "  P x ->\n" ^
    "  Q x)\n" ^
    "\n" ^
    "Goal #2\n" ^
    "A /\\\n" ^
    "(B \/ C)\n" ^
    "[8|check]>\n"

  let%test "prompt_detection" =
    Pg.is_prompt_only "[3|check]>" &&
    Pg.has_prompt "abc [42|weakcheck]> xyz"

  let%test "goal_markers_and_remaining" =
    Pg.contains_current_goal "... Current goal (remaining: 2) ..." &&
    match Pg.extract_remaining_count "Current goal (remaining: 2)" with
    | Some 2 -> true
    | _ -> false

  let%test "no_more_goals_detection" =
    Pg.contains_no_more_goals "No more goals." &&
    Pg.contains_no_more_goals "There are no more subgoals"

  let%test "parse_goals_with_header_and_separator" =
    match Pg.parse_goals_from_output sample_with_header_and_sep with
    | [ (hyps, goal) ] ->
        let has_type_vars = List.exists (fun s -> Stdlib.String.index_opt s '\'' |> Option.is_some) hyps in
        let has_x_bool = List.exists (fun s -> String.equal s "x: bool") hyps in
        has_type_vars && has_x_bool && String.equal goal "true"
    | _ -> false

  let%test "parse_goals_single_line_no_separator" =
    match Pg.parse_goals_from_output sample_single_line_no_sep with
    | [ (_hyps, goal) ] -> String.equal goal "P -> Q"
    | _ -> false

  let%test "parse_no_more_goals_yields_empty" =
    match Pg.parse_goals_from_output sample_no_more_goals with
    | [] -> true
    | _ -> false

  let%test "parse_multiple_goals_with_markers" =
    match Pg.parse_goals_from_output sample_multiple_goals with
    | (hyps1, g1) :: (hyps2, g2) :: (hyps3, g3) :: [] ->
        let has_x_bool = List.exists (fun s -> String.equal s "x: bool") hyps1 in
        has_x_bool && String.equal g1 "true" &&
        (hyps2 = [] && String.equal g2 "false \/ true") &&
        (hyps3 = [] && String.equal g3 "P -> Q")
    | _ -> false

  let%test "parse_multiline_goals_and_subgoals" =
    match Pg.parse_goals_from_output sample_multiline_goals with
    | (_hyps1, g1) :: (_hyps2, g2) :: [] ->
        String.equal g1 "(forall x,\nP x ->\nQ x)" &&
        String.equal g2 "A /\\\n(B \/ C)"
    | _ -> false

  let%test "parse_prompt_info_modes" =
    match Pg.parse_prompt_info "[5|weakcheck]>" with
    | Some (5, true) -> (
        match Pg.parse_prompt_info "[3|check]>" with
        | Some (3, false) -> true
        | _ -> false
      )
    | _ -> false
end)


let%test_module "pg_progress" = (module struct
  module Pg = Pg_compat

  let sample_remaining_3 =
    "[10|check]>\n" ^
    "Current goal (remaining: 3)\n" ^
    "-----\n" ^
    "G\n" ^
    "[10|check]>\n"

  let sample_done =
    "[11|check]>\n" ^
    "No more goals.\n" ^
    "[11|check]>\n"

  let%test "progress_from_remaining_header" =
    match Pg.extract_remaining_count sample_remaining_3 with
    | Some 3 ->
      let p = Pg.progress_of_output sample_remaining_3 in
      p > 0.0 && p < 1.0
    | _ -> false

  let%test "progress_for_no_more_goals_is_one" =
    Pg.contains_no_more_goals sample_done && Pg.progress_of_output sample_done = 1.0

  let%test "progress_unknown_defaults_zero" =
    let unknown = "[12|check]>\nSome unrelated output\n[12|check]>\n" in
    Pg.progress_of_output unknown = 0.0
end)


let%test_module "pg_grouped_goals" = (module struct
  module Pg = Pg_compat

  let sample_grouped =
    "[7|check]>\n" ^
    "Current goal (remaining: 2)\n" ^
    "Type variables: 'a\n" ^
    "x: bool\n" ^
    "-----\n" ^
    "true\n" ^
    "\n" ^
    "Goal #2\n" ^
    "P /\\ Q\n" ^
    "\n" ^
    "Shelved goals:\n" ^
    "-----\n" ^
    "R -> S\n" ^
    "\n" ^
    "Unfocused goals:\n" ^
    "-----\n" ^
    "exists x. T x\n" ^
    "\n" ^
    "Given up goals:\n" ^
    "-----\n" ^
    "False\n" ^
    "[7|check]>\n"

  let%test "parse_grouped_current_and_others" =
    let g = Pg.parse_goal_groups_from_output sample_grouped in
    let ok_current =
      match g.current with
      | (hyps1, g1) :: (_hyps2, g2) :: [] ->
          let has_x_bool = List.exists (fun s -> String.equal s "x: bool") hyps1 in
          has_x_bool && String.equal g1 "true" && String.equal g2 "P /\\ Q"
      | _ -> false
    in
    let ok_shelved =
      match g.shelved with
      | [ ([], s) ] -> String.equal s "R -> S"
      | _ -> false
    in
    let ok_unfocused =
      match g.unfocused with
      | [ ([], u) ] -> String.equal u "exists x. T x"
      | _ -> false
    in
    let ok_given_up =
      match g.given_up with
      | [ ([], d) ] -> String.equal d "False"
      | _ -> false
    in
    ok_current && ok_shelved && ok_unfocused && ok_given_up
end)


let%test_module "pg_subgoal_patterns" = (module struct
  module Pg = Pg_compat

  (* split: two subgoals *)
  let sample_split =
    "[9|check]>\n" ^
    "Current goal (remaining: 2)\n" ^
    "-----\n" ^
    "A /\\ B\n" ^
    "\n" ^
    "Goal #2\n" ^
    "A -> B\n" ^
    "[9|check]>\n"

  (* case: two branches *)
  let sample_case =
    "[10|check]>\n" ^
    "Current goal (remaining: 2)\n" ^
    "-----\n" ^
    "X = true -> G\n" ^
    "\n" ^
    "Goal #2\n" ^
    "X = false -> G\n" ^
    "[10|check]>\n"

  (* Subgoal markers instead of Goal #n *)
  let sample_subgoal_markers =
    "[11|check]>\n" ^
    "Current goal (remaining: 2)\n" ^
    "-----\n" ^
    "H -> T\n" ^
    "\n" ^
    "Subgoal 2\n" ^
    "T -> H\n" ^
    "[11|check]>\n"

  let%test "parse_split_two_subgoals" =
    match Pg.parse_goals_from_output sample_split with
    | (_, g1) :: (_, g2) :: [] ->
        String.equal g1 "A /\\ B" && String.equal g2 "A -> B"
    | _ -> false

  let%test "parse_case_two_subgoals" =
    match Pg.parse_goals_from_output sample_case with
    | (_, a) :: (_, b) :: [] ->
        String.equal a "X = true -> G" && String.equal b "X = false -> G"
    | _ -> false

  let%test "parse_subgoal_markers" =
    match Pg.parse_goals_from_output sample_subgoal_markers with
    | (_, a) :: (_, b) :: [] ->
        String.equal a "H -> T" && String.equal b "T -> H"
    | _ -> false
end)

