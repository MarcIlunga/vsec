(**************************************************************************)
(*                                                                        *)
(*                                 VsEc                                   *)
(*                                                                        *)
(*                   Copyright INRIA and contributors                     *)
(*       (see version control and README file for authors & dates)        *)
(*                                                                        *)
(**************************************************************************)
(*                                                                        *)
(*   This file is distributed under the terms of the MIT License.         *)
(*   See LICENSE file.                                                    *)
(*                                                                        *)
(**************************************************************************)

(** AST Serialization - Convert EasyCrypt's native AST types to JSON
    
    This module provides Yojson serializers for EasyCrypt's AST types.
    We DON'T create wrapper types - we serialize EasyCrypt's types directly!
*)

open EcLib

(* Helper: Convert EcIdent.t to JSON *)
let yojson_of_ident (id: EcIdent.t) : Yojson.Safe.t =
  `Assoc [
    ("name", `String (EcIdent.tostring id));
    ("tag", `Int (EcIdent.tag id));
  ]

(* Helper: Convert EcPath.path to JSON *)
let yojson_of_path (p: EcPath.path) : Yojson.Safe.t =
  `String (EcPath.tostring p)

(* Helper: Convert EcSymbols.symbol to JSON *)
let yojson_of_symbol (sym: EcSymbols.symbol) : Yojson.Safe.t =
  `String sym

(* Convert EcTypes.ty_node to JSON *)
let rec yojson_of_ty_node (tn: EcTypes.ty_node) : Yojson.Safe.t =
  match tn with
  | Tvar tv ->
      (* Type variable - serialize the identifier *)
      `Assoc [
        ("kind", `String "var");
        ("id", yojson_of_ident tv);
      ]
  | Tglob mp ->
      `Assoc [
        ("kind", `String "glob");
        ("ident", yojson_of_ident mp);
      ]
  | Tunivar uid ->
      `Assoc [
        ("kind", `String "univar");
        ("uid", `Int uid);
      ]
  | Tconstr (p, tys) ->
      `Assoc [
        ("kind", `String "constr");
        ("path", yojson_of_path p);
        ("args", `List (List.map yojson_of_ty tys));
      ]
  | Tfun (t1, t2) ->
      `Assoc [
        ("kind", `String "fun");
        ("domain", yojson_of_ty t1);
        ("codomain", yojson_of_ty t2);
      ]
  | Ttuple tys ->
      `Assoc [
        ("kind", `String "tuple");
        ("elements", `List (List.map yojson_of_ty tys));
      ]

(* Convert EcTypes.ty to JSON *)
and yojson_of_ty (ty: EcTypes.ty) : Yojson.Safe.t =
  (* Use proper API to access ty_node *)
  yojson_of_ty_node ty.ty_node

(* Convert quantifier to JSON *)
let yojson_of_quantifier (q: EcAst.quantif) : Yojson.Safe.t =
  match q with
  | Lforall -> `String "forall"
  | Lexists -> `String "exists"
  | Llambda -> `String "lambda"

(* Convert gty (generalized type for local bindings) to JSON *)
let yojson_of_gty (gty: EcCoreFol.gty) : Yojson.Safe.t =
  match gty with
  | GTty ty -> yojson_of_ty ty
  | GTmodty (mty, mr) ->
      `Assoc [
        ("kind", `String "modty");
        (* Simplified - full module type serialization would be complex *)
      ]
  | GTmem mt ->
      `Assoc [
        ("kind", `String "mem");
      ]

(* Convert hoarecmp operator to JSON *)
let yojson_of_hoarecmp (cmp: EcAst.hoarecmp) : Yojson.Safe.t =
  match cmp with
  | FHle -> `String "le"
  | FHeq -> `String "eq"
  | FHge -> `String "ge"

(* Convert form node to JSON - the core AST traversal *)
let rec yojson_of_form_node (fn: EcAst.f_node) : Yojson.Safe.t =
  match fn with
  | Fquant (q, bindings, body) ->
      `Assoc [
        ("kind", `String "quant");
        ("quantifier", yojson_of_quantifier q);
        ("bindings", `List (List.map (fun (id, gty) ->
          `Assoc [
            ("id", yojson_of_ident id);
            ("ty", yojson_of_gty gty);
          ]
        ) bindings));
        ("body", yojson_of_form body);
      ]
  
  | Fif (cond, then_f, else_f) ->
      `Assoc [
        ("kind", `String "if");
        ("condition", yojson_of_form cond);
        ("then", yojson_of_form then_f);
        ("else", yojson_of_form else_f);
      ]
  
  | Fmatch (scrutinee, branches, ty) ->
      `Assoc [
        ("kind", `String "match");
        ("scrutinee", yojson_of_form scrutinee);
        ("branches", `List (List.map yojson_of_form branches));
        ("ty", yojson_of_ty ty);
      ]
  
  | Flet (lp, body, rest) ->
      `Assoc [
        ("kind", `String "let");
        (* lp is a lpattern - simplified *)
        ("body", yojson_of_form body);
        ("rest", yojson_of_form rest);
      ]
  
  | Fint n ->
      `Assoc [
        ("kind", `String "int");
        ("value", `String (EcBigInt.to_string n));
      ]
  
  | Flocal id ->
      `Assoc [
        ("kind", `String "local");
        ("id", yojson_of_ident id);
      ]
  
  | Fpvar (pv, mem) ->
      `Assoc [
        ("kind", `String "pvar");
        ("pv", `String "pvar");  (* Simplified *)
        ("mem", yojson_of_ident mem);
      ]
  
  | Fglob (mp, mem) ->
      `Assoc [
        ("kind", `String "glob");
        ("mp", yojson_of_ident mp);  (* mp is an ident, not a path *)
        ("mem", yojson_of_ident mem);
      ]
  
  | Fop (p, tys) ->
      `Assoc [
        ("kind", `String "op");
        ("path", yojson_of_path p);
        ("type_args", `List (List.map yojson_of_ty tys));
      ]
  
  | Fapp (f, args) ->
      `Assoc [
        ("kind", `String "app");
        ("func", yojson_of_form f);
        ("args", `List (List.map yojson_of_form args));
      ]
  
  | Ftuple fs ->
      `Assoc [
        ("kind", `String "tuple");
        ("elements", `List (List.map yojson_of_form fs));
      ]
  
  | Fproj (f, i) ->
      `Assoc [
        ("kind", `String "proj");
        ("tuple", yojson_of_form f);
        ("index", `Int i);
      ]
  
  (* Hoare/pRHL-specific constructs *)
  | FhoareF hf ->
      `Assoc [
        ("kind", `String "hoareF");
        (* Simplified - full hoare formula serialization *)
      ]
  
  | FhoareS hs ->
      `Assoc [
        ("kind", `String "hoareS");
      ]
  
  | FbdHoareF bhf ->
      `Assoc [
        ("kind", `String "bdHoareF");
      ]
  
  | FbdHoareS bhs ->
      `Assoc [
        ("kind", `String "bdHoareS");
      ]
  
  | FequivF ef ->
      `Assoc [
        ("kind", `String "equivF");
      ]
  
  | FequivS es ->
      `Assoc [
        ("kind", `String "equivS");
      ]
  
  | FeagerF ef ->
      `Assoc [
        ("kind", `String "eagerF");
      ]
  
  | Fpr pr ->
      `Assoc [
        ("kind", `String "pr");
      ]
  | FeHoareF _ ->
      `Assoc [
        ("kind", `String "ehoaref");
      ]
  | FeHoareS _ ->
      `Assoc [
        ("kind", `String "ehoares");
      ]

(* Convert full form to JSON *)
and yojson_of_form (f: EcCoreFol.form) : Yojson.Safe.t =
  (* Use proper API to access form components *)
  let f_node = EcCoreFol.f_node f in
  let f_ty = EcCoreFol.f_ty f in
  `Assoc [
    ("node", yojson_of_form_node f_node);
    ("ty", yojson_of_ty f_ty);
    ("tag", `Int 0);
  ]

(* Convert l_local to JSON - l_local is (EcIdent.t * local_kind) *)
let yojson_of_l_local ((id, kind): EcBaseLogic.l_local) : Yojson.Safe.t =
  match kind with
  | EcBaseLogic.LD_var (ty, def_opt) ->
      `Assoc [
        ("kind", `String "var");
        ("id", yojson_of_ident id);
        ("type", yojson_of_ty ty);
        ("definition", (match def_opt with
          | None -> `Null
          | Some def -> yojson_of_form def));
      ]
  | EcBaseLogic.LD_mem memtype ->
      `Assoc [
        ("kind", `String "mem");
        ("id", yojson_of_ident id);
        ("memtype", `String "memtype");  (* Simplified for now *)
      ]
  | EcBaseLogic.LD_modty mty_mr ->
      `Assoc [
        ("kind", `String "modty");
        ("id", yojson_of_ident id);
        ("mty_mr", `String "mty_mr");  (* Simplified for now *)
      ]
  | EcBaseLogic.LD_hyp form ->
      `Assoc [
        ("kind", `String "hyp");
        ("id", yojson_of_ident id);
        ("form", yojson_of_form form);
      ]
  | EcBaseLogic.LD_abs_st abs_uses ->
      `Assoc [
        ("kind", `String "abs_st");
        ("id", yojson_of_ident id);
        ("abs_uses", `String "abs_uses");  (* Simplified for now *)
      ]

(* Convert hypothesis to JSON - now works with EcBaseLogic.hyps *)
let yojson_of_hypothesis (hyp: EcBaseLogic.l_local) : Yojson.Safe.t =
  yojson_of_l_local hyp

(* Convert goal to JSON *)
let yojson_of_goal (idx: int) (pg: EcCoreGoal.pregoal) : Yojson.Safe.t =
  (* Extract hypotheses from EcBaseLogic.hyps *)
  let hyps = EcLib.EcEnv.LDecl.tohyps pg.EcCoreGoal.g_hyps in
  let hyps_json = List.map yojson_of_hypothesis hyps.h_local in
  `Assoc [
    ("id", `Int idx);
    ("hypotheses", `List hyps_json);
    ("conclusion", yojson_of_form pg.EcCoreGoal.g_concl);
  ]

(* High-level function: convert list of pregoals to JSON *)
let yojson_of_goals (goals: EcCoreGoal.pregoal list) : Yojson.Safe.t =
  `List (List.mapi yojson_of_goal goals)

