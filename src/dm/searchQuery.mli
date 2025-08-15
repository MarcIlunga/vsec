(**************************************************************************)
(*                                                                        *)
(*                                 VSRocq                                 *)
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
open Protocol.LspWrapper
open Types

val query_feedback : notification Sel.Event.t

(* TODO: Replace with EasyCrypt search system *)
(* Temporarily disabled Coq search for build success *)
val interp_search :
  id:string ->
  string -> (* simplified environment *)
  string -> (* simplified evar_map *)
  (bool * string) list -> (* simplified search_request *)
  string list -> (* simplified search_restriction *)
  notification Sel.Event.t list
