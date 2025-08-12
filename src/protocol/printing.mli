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

(** Pretty printing for EasyCrypt structures *)

type pp_tag = string [@@deriving yojson]

type block_type = 
  | Pp_hbox
  | Pp_vbox   of int
  | Pp_hvbox  of int
  | Pp_hovbox of int
[@@deriving yojson]

type pp =
| Ppcmd_empty
| Ppcmd_string of string
| Ppcmd_glue of pp list
| Ppcmd_box  of block_type * pp
| Ppcmd_tag of pp_tag * pp
| Ppcmd_print_break of int * int
| Ppcmd_force_newline
| Ppcmd_comment of string list
[@@deriving yojson]

(** Convert string to pp structure for EasyCrypt *)
val pp_of_string : string -> pp

(** Convert EasyCrypt structures to formatted strings *)
val string_of_pp : pp -> string