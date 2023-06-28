(**************************************************************************)
(*                                                                        *)
(*                                 VSCoq                                  *)
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
open Lsp.LspData
open EcLib

module Stateid = struct

  type t = int

  let initial = 1
  
  let fresh =
    let cur = ref initial in
    fun () -> incr cur; !cur

  let compare = Int.compare

  let to_string t = string_of_int t

  let to_int t = t

end

module StateidSet = Set.Make(Stateid)

type sentence_id = Stateid.t
type sentence_id_set = StateidSet.t

type text_edit = Range.t * string

type link = {
  write_to :  Unix.file_descr;
  read_from:  Unix.file_descr;
}

type 'a log = Log : 'a -> 'a log

(*TODO: Replace this proper easycrypt data structures *)
module Vernacstate = struct

  type t = unit

end