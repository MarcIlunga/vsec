(* TODO: Replace with EasyCrypt completion system *)
(* Temporarily disabled Coq completion system for build success *)

type completion_level = 
  | Fully
  | Partially
  | No_completion

let symbol_prefix (completes: completion_level option) =
  match completes with
  | None -> ""
  | Some level -> match level with
    | Fully -> "★ "
    | Partially -> "☆ "
    | No_completion -> ""

(* Placeholder completion_item type - will be replaced with EasyCrypt equivalent *)
type completion_item = {
  name : string;
  typ : string;
  detail : string;
  completes : completion_level option;
  debug_info : string;
}

(* Placeholder function - will be replaced with EasyCrypt implementation *)
let mk_completion_item name typ detail : completion_item = 
  {
    name = name;
    typ = typ;
    detail = detail;
    completes = None;
    debug_info = "";
  }

(* Placeholder function - will be replaced with EasyCrypt implementation *)
let pp_completion_item (item : completion_item) : (string * string * string * string) =
  let name = item.name in
  let path = item.detail ^ "\n" ^ item.debug_info in
  let typ = item.typ in
  (Printf.sprintf "%s%s" (symbol_prefix item.completes) name, name, typ, path)