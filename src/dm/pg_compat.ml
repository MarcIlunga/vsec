open Str

(* Proof General compatibility helpers for EasyCrypt Emacs-mode interaction *)

(* Prompt example: [3|check]> or [42|weakcheck]> *)
let prompt_regexp = regexp "^\\[[0-9]+|[A-Za-z0-9_]+\\]>[ \\t\\r\\n]*$"

let is_prompt_only (s:string) : bool =
  string_match prompt_regexp (String.trim s) 0

let prompt_anywhere_regexp = regexp "\\[[0-9]+|[A-Za-z0-9_]+\\]>"

let has_prompt (s:string) : bool =
  try ignore (search_forward prompt_anywhere_regexp s 0); true with Not_found -> false

let contains_current_goal (s:string) : bool =
  try ignore (search_forward (regexp_case_fold "Current goal") s 0); true with Not_found -> false

let contains_no_more_goals (s:string) : bool =
  try ignore (search_forward (regexp_case_fold "No more goals") s 0); true with Not_found ->
  try ignore (search_forward (regexp_case_fold "There are no more subgoals") s 0); true with Not_found -> false

(* Extract (remaining: N) from Current goal line, if present *)
let extract_remaining_count (s:string) : int option =
  let re = regexp_case_fold "current goal (remaining: *\\([0-9]+\\))" in
  try
    ignore (search_forward re s 0);
    let n = int_of_string (matched_group 1 s) in
    Some n
  with Not_found -> None

let parse_prompt_info (s:string) : (int * bool) option =
  (* PG: "\\[\\([0-9]+\\)|\\(\\sw+\\)\\]"; we treat mode = weakcheck as weak *)
  let re = regexp "\\[\\([0-9]+\\)|\\([A-Za-z0-9_]+\\)\\]" in
  if string_match re s 0 then (
    let n = int_of_string (matched_group 1 s) in
    let mode = String.lowercase_ascii (matched_group 2 s) in
    Some (n, String.contains mode 'w')
  ) else None

(* Parse EasyCrypt goal block following PG conventions. Returns list of (hyps, goal) *)
let parse_goals_from_output (output:string) : (string list * string) list =
  let s = output in
  if contains_no_more_goals s then [] else (
    (* Find the 'Current goal' segment anywhere in the text *)
    let cg_re = regexp_case_fold "current goal" in
    let start_idx = try search_forward cg_re s 0 with Not_found -> -1 in
    if start_idx < 0 then [] else (
      let after = String.sub s start_idx (String.length s - start_idx) in
      (* Skip optional '(remaining: N)' chunk *)
      let header_start =
        let rem_re = regexp_case_fold "^\\s*current goal\\( (remaining: *[0-9]+)\\)?\\s*" in
        if string_match rem_re after 0 then match_end () else 0
      in
      let after_from_header = String.sub after header_start (String.length after - header_start) in
      (* Find a dashed separator '-----' or longer *)
      let sep_re = regexp "-----+" in
      let sep_rel = try search_forward sep_re after_from_header 0 with Not_found -> -1 in
      if sep_rel < 0 then (
        (* Fallback: if no separator present, try to extract goal up to prompt *)
        let prompt_re = prompt_regexp in
        let g_end = try search_forward prompt_re after_from_header 0 with Not_found -> -1 in
        let raw_goal = if g_end < 0 then after_from_header else String.sub after_from_header 0 g_end in
        (* Support multiple goals indicated by 'Goal #n' lines even without header separator *)
        let lines = String.split_on_char '\n' raw_goal in
        let goal_marker = regexp "^\\s*\\(Goal #[0-9]+\\|Subgoal [0-9]+\\)\\b.*$" in
        let sep_re = regexp "-----+" in
        let rec split_chunks acc current = function
          | [] -> List.rev (current :: acc)
          | l :: ls ->
            let t = String.trim l in
            if string_match goal_marker t 0 then
              split_chunks (current :: acc) [] ls
            else
              split_chunks acc (current @ [l]) ls
        in
        let chunks = split_chunks [] [] lines |> List.filter (fun ch -> ch <> []) in
        let clean_goal_text chunk =
          let content_lines =
            chunk
            |> List.map String.trim
            |> List.filter (fun l -> String.length l > 0 && not (string_match sep_re l 0))
          in
          match content_lines with
          | [] -> "No goal content found"
          | ls -> String.concat "\n" ls
        in
        (match chunks with
        | [] ->
          let goal_line = clean_goal_text lines in
          [ ([], goal_line) ]
        | cs ->
          (* First chunk uses header hyps (none here), following as additional goals *)
          let goals = List.map clean_goal_text cs in
          (match goals with
           | [] -> []
           | g1 :: rest -> ([], g1) :: List.map (fun g -> ([], g)) rest))
      ) else (
        let header = String.sub after_from_header 0 sep_rel in
        let after_sep = let _ = match_end () in String.sub after_from_header (match_end ()) (String.length after_from_header - (match_end ())) in
        (* Collect hypotheses from header: 'Type variables: ...' and tokens like 'x: type' *)
        let type_vars =
          try ignore (search_forward (regexp_case_fold "type variables:[^\n-]*") header 0); String.trim (matched_string header)
          with Not_found -> ""
        in
        let hyps_tokens =
          let rec collect acc pos =
            try
              ignore (search_forward (regexp "\\b[^\\s:]+\\s*:\\s*[^\\s\n-]+") header pos);
              let tok = matched_string header |> String.trim in
              let next_pos = match_end () in
              collect (tok :: acc) next_pos
            with Not_found -> List.rev acc
          in collect [] 0
        in
        let hyps =
          let base = if String.length type_vars > 0 then [type_vars] else [] in
          let rec dedup seen acc = function
            | [] -> List.rev acc
            | x :: xs -> if List.mem x seen then dedup seen acc xs else dedup (x :: seen) (x :: acc) xs
          in
          dedup base base hyps_tokens
        in
        (* Extract all goals until prompt. Split on lines like 'Goal #n' (pp_goal1 markers). *)
        let prompt_re = prompt_regexp in
        let g_end = try search_forward prompt_re after_sep 0 with Not_found -> -1 in
        let raw_goals = if g_end < 0 then after_sep else String.sub after_sep 0 g_end in
        let lines = String.split_on_char '\n' raw_goals in
        let goal_marker = regexp "^\\s*\\(Goal #[0-9]+\\|Subgoal [0-9]+\\)\\b.*$" in
        let sep_re = regexp "-----+" in
        let rec split_chunks acc current = function
          | [] -> List.rev (current :: acc)
          | l :: ls ->
            let t = String.trim l in
            if string_match goal_marker t 0 then
              split_chunks (current :: acc) [] ls
            else
              split_chunks acc (current @ [l]) ls
        in
        let chunks = split_chunks [] [] lines |> List.filter (fun ch -> ch <> []) in
        let clean_goal_text chunk =
          let content_lines =
            chunk
            |> List.map String.trim
            |> List.filter (fun l -> String.length l > 0 && not (string_match sep_re l 0))
          in
          match content_lines with
          | [] -> "No goal content found"
          | ls -> String.concat "\n" ls
        in
        (match chunks with
        | [] ->
          let g = clean_goal_text lines in
          [ (hyps, g) ]
        | cs ->
          let goals = List.map clean_goal_text cs in
          (match goals with
           | [] -> []
           | g1 :: rest -> (hyps, g1) :: List.map (fun g -> ([], g)) rest))
      )
    )
  )

type goal_groups = {
  current : (string list * string) list;
  shelved : (string list * string) list;
  given_up : (string list * string) list;
  unfocused : (string list * string) list;
}

let parse_simple_goal_chunks (text:string) : (string list * string) list =
  let lines = String.split_on_char '\n' text in
  let goal_marker = regexp "^\\s*\\(Goal #[0-9]+\\|Subgoal [0-9]+\\)\\b.*$" in
  let sep_re = regexp "-----+" in
  let rec split_chunks acc current = function
    | [] -> List.rev (current :: acc)
    | l :: ls ->
      let t = String.trim l in
      if string_match goal_marker t 0 then
        split_chunks (current :: acc) [] ls
      else
        split_chunks acc (current @ [l]) ls
  in
  let chunks = split_chunks [] [] lines |> List.filter (fun ch -> ch <> []) in
  let clean_first_nonempty chunk =
    chunk
    |> List.filter (fun l ->
          let t = String.trim l in
          String.length t > 0 && not (string_match sep_re t 0))
    |> (function | [] -> "No goal content found" | x :: _ -> String.trim x)
  in
  match chunks with
  | [] ->
    let g = clean_first_nonempty lines in
    if String.length (String.trim g) = 0 then [] else [ ([], g) ]
  | cs -> List.map (fun g -> ([], clean_first_nonempty g)) cs

let parse_goal_groups_from_output (output:string) : goal_groups =
  let s = output in
  if contains_no_more_goals s then { current = []; shelved = []; given_up = []; unfocused = [] } else (
    let lower = String.lowercase_ascii s in
    let find_pos needle =
      try ignore (search_forward (regexp needle) lower 0); Some (match_beginning ()) with Not_found -> None
    in
    let positions =
      [ ("current", find_pos "current goal");
        ("shelved", find_pos "shelved goals");
        ("unfocused", find_pos "unfocused goals");
        ("given_up", find_pos "given up goals") ]
      |> List.filter (fun (_,p) -> p <> None)
      |> List.map (fun (k, p) -> (k, Option.get p))
      |> List.sort (fun (_,a) (_,b) -> compare a b)
    in
    let prompt_pos = (try ignore (search_forward prompt_anywhere_regexp s 0); Some (match_beginning ()) with Not_found -> None) in
    let take_segment start_idx end_idx_opt =
      match end_idx_opt with
      | None -> String.sub s start_idx (String.length s - start_idx)
      | Some e when e > start_idx -> String.sub s start_idx (e - start_idx)
      | Some _ -> ""
    in
    (* Build segments per header; end at next header or prompt *)
    let find_prompt_after start_idx =
      try ignore (search_forward prompt_anywhere_regexp s start_idx); Some (match_beginning ()) with Not_found -> None
    in
    let segments =
      let rec aux acc = function
        | [] -> List.rev acc
        | (k, pos) :: rest ->
          let next_pos =
            match rest with
            | [] -> find_prompt_after pos
            | (_, p2) :: _ -> Some p2
          in
          (k, take_segment pos next_pos) :: aux acc rest
      in aux [] positions
    in
    let drop_first_line s =
      try
        let i = String.index s '\n' in
        String.sub s (i + 1) (String.length s - i - 1)
      with Not_found -> ""
    in
    let current =
      match List.assoc_opt "current" segments with
      | None -> []
      | Some seg -> parse_goals_from_output seg
    in
    let shelved =
      match List.assoc_opt "shelved" segments with
      | None -> []
      | Some seg -> parse_simple_goal_chunks (drop_first_line seg)
    in
    let unfocused =
      match List.assoc_opt "unfocused" segments with
      | None -> []
      | Some seg -> parse_simple_goal_chunks (drop_first_line seg)
    in
    let given_up =
      match List.assoc_opt "given_up" segments with
      | None -> []
      | Some seg -> parse_simple_goal_chunks (drop_first_line seg)
    in
    { current; shelved; given_up; unfocused }
  )


(* Compute a simple proof progress from PG-style output *)
let progress_of_output (s:string) : float =
  if contains_no_more_goals s then 1.0 else
  match extract_remaining_count s with
  | None -> 0.0
  | Some n when n <= 0 -> 1.0
  | Some n -> if n > 0 then 1.0 /. float_of_int (n + 1) else 0.0

