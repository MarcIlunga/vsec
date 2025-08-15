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

(** Proof state management for EasyCrypt interactive proving *)

type proof_statement [@@deriving yojson]

type proof_step [@@deriving yojson]

type proof_block [@@deriving yojson]

type t [@@deriving yojson]

(** Get proof state from EasyCrypt execution state *)
val get_proof : previous:EcLib.EcScope.scope option -> EcLib.EcScope.scope -> t option

(** Create proof statement with text and range *)
val mk_proof_statement : string -> Lsp.Types.Range.t -> proof_statement

(** Create proof step with tactic and range *)
val mk_proof_step : string -> Lsp.Types.Range.t -> proof_step

(** Create proof block with statement, steps, and range *)
val mk_proof_block : proof_statement -> proof_step list -> Lsp.Types.Range.t -> proof_block