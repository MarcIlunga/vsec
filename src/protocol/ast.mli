(** AST Serialization for EasyCrypt types to JSON *)

open EcLib

(** Convert EasyCrypt identifier to JSON *)
val yojson_of_ident : EcIdent.t -> Yojson.Safe.t

(** Convert EasyCrypt path to JSON *)
val yojson_of_path : EcPath.path -> Yojson.Safe.t

(** Convert EasyCrypt type expression to JSON *)
val yojson_of_ty : EcTypes.ty -> Yojson.Safe.t

(** Convert EasyCrypt formula to JSON (recursive traversal) *)
val yojson_of_form : EcCoreFol.form -> Yojson.Safe.t

(** Convert hypothesis to JSON *)
val yojson_of_hypothesis : EcBaseLogic.l_local -> Yojson.Safe.t

(** Convert single goal (pregoal) to JSON *)
val yojson_of_goal : int -> EcCoreGoal.pregoal -> Yojson.Safe.t

(** Convert list of goals to JSON array *)
val yojson_of_goals : EcCoreGoal.pregoal list -> Yojson.Safe.t

