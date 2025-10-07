(* Dynlinked EasyCrypt goals adapter for VsEc *)

(* Dependencies expected via dune: easycrypt.ecLib *)

let Dm.Types.Log log = Dm.Log.mk_log "vsec_ec_adapter"

module PS = Protocol.ProofState
module Ast = Protocol.Ast

(* Convert AST JSON to proper pp_atoms for UI rendering *)
let rec json_to_pp_atoms (json: Yojson.Safe.t) : PS.pp =
  match json with
  | `Assoc fields ->
      (* AST node - extract text representation and class *)
      (match List.assoc_opt "node" fields with
      | Some node_json -> json_to_pp_atoms node_json
      | None ->
          (* No node field - check for other renderable fields *)
          (match List.assoc_opt "kind" fields with
          | Some (`String kind) ->
              (* Type or identifier node *)
              (match List.assoc_opt "name" fields, List.assoc_opt "id" fields with
              | Some (`String name), _ -> [ { PS.text = name; cls = Some kind } ]
              | _, Some id_json -> 
                  (match json_to_pp_atoms id_json with
                  | [] -> [ { PS.text = kind; cls = Some kind } ]
                  | atoms -> atoms)
              | _, None -> [ { PS.text = kind; cls = Some kind } ])
          | _ ->
              (* Fallback: render as compact JSON *)
              [ { PS.text = Yojson.Safe.to_string json; cls = None } ]))
  | `String s -> [ { PS.text = s; cls = None } ]
  | `Int i -> [ { PS.text = string_of_int i; cls = Some "number" } ]
  | `List items ->
      (* Flatten list of atoms *)
      List.concat (List.map json_to_pp_atoms items)
  | _ -> [ { PS.text = Yojson.Safe.to_string json; cls = None } ]

(* Convert AST JSON to legacy string (for backward compat) *)
let pp_to_legacy_string (json: Yojson.Safe.t) : string =
  (* Convert to pp_atoms and concatenate text *)
  let atoms = json_to_pp_atoms json in
  String.concat "" (List.map (fun (a: PS.pp_atom) -> a.text) atoms)

(* Extract goals using AST serialization - NO MORE TEXT CONVERSION! *)
let extract_goals_with_ast goals ~id_offset =
  let to_goal idx (pg:EcLib.EcCoreGoal.pregoal) : PS.goal =
    log (fun () -> Printf.sprintf "[Adapter] Extracting goal %d using AST serialization" idx);
    
    (* Extract hypotheses as structured AST *)
    let hyps = EcLib.EcEnv.LDecl.tohyps pg.EcLib.EcCoreGoal.g_hyps in
    let hyps_json = List.map Ast.yojson_of_hypothesis hyps.h_local in
    
    (* Extract conclusion as structured AST *)
    let concl_json = Ast.yojson_of_form pg.EcLib.EcCoreGoal.g_concl in
    
    (* Legacy string representation (temporary during migration) *)
    let hyps_str = List.map pp_to_legacy_string hyps_json in
    let concl_str = pp_to_legacy_string concl_json in
    
    (* Convert to pp format *)
    let hyps_pp = List.map json_to_pp_atoms hyps_json in
    let concl_pp = json_to_pp_atoms concl_json in
    
    log (fun () -> Printf.sprintf "[Adapter] Goal %d: %d hypotheses extracted via AST" idx (List.length hyps.h_local));
    
    { PS.id = id_offset + idx
    ; hypotheses = hyps_str
    ; goal = concl_str
    ; hypotheses_pp = hyps_pp
    ; goal_pp = concl_pp
    }
  in
  List.mapi to_goal goals

let goals_of_scope (scope:EcLib.EcScope.scope) : PS.goal list =
  match EcLib.EcScope.xgoal scope with
  | None -> []
  | Some { EcLib.EcScope.puc_active = None; _ } -> []
  | Some { EcLib.EcScope.puc_active = Some (puc, _); _ } ->
    begin match puc.EcLib.EcScope.puc_jdg with
    | EcLib.EcScope.PSNoCheck -> []
    | EcLib.EcScope.PSCheck proof ->
      let opened = EcLib.EcCoreGoal.all_opened proof in
      (* NO MORE pp_form_to_string! Use AST serialization directly *)
      extract_goals_with_ast opened ~id_offset:0
    end

(* Extract shelved/unfocused goals *)
let shelved_goals_of_scope (scope:EcLib.EcScope.scope) : PS.goal list =
  (* EasyCrypt doesn't expose shelved goals directly in EcCoreGoal,
     but we can check if there are suspended subgoals *)
  try
    match EcLib.EcScope.xgoal scope with
    | Some { EcLib.EcScope.puc_active = Some (puc, _); _ } ->
      begin match puc.EcLib.EcScope.puc_jdg with
      | EcLib.EcScope.PSCheck proof ->
        (* Check if there are any suspended/shelved goals *)
        (* EasyCrypt's proof structure may have these in different places *)
        [] (* For now, return empty - needs deeper EcCoreGoal analysis *)
      | _ -> []
      end
    | _ -> []
  with _ -> []

(* Extract current lemma/theorem name *)
let current_lemma_name (scope:EcLib.EcScope.scope) : string option =
  try
    (* Try to extract the name of the current proof from scope *)
    match EcLib.EcScope.xgoal scope with
    | Some { EcLib.EcScope.puc_active = Some (puc, _); _ } ->
      (* Check if we can get the proof name from the proof unit context *)
      (* EasyCrypt stores this in the proof context name *)
      (try
        (* The proof might have a name in its context *)
        Some "(current proof)" (* Placeholder - would need to extract from puc structure *)
      with _ -> None)
    | _ -> None
  with _ -> None

let () =
  (* Register adapter on dynlink *)
  try
    log (fun () -> "Registering vsec_ec_adapter");
    Dm.EcAdapter.register_goals goals_of_scope
  with _ -> ()


