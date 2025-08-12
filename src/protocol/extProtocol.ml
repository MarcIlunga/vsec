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
open Lsp.Types
open LspWrapper
open Printing

open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Notification = struct

  module Client = struct

    module InterpretToPointParams = struct

      type t = {
        textDocument : VersionedTextDocumentIdentifier.t;
        position : Position.t;
      } [@@deriving yojson]

    end

    module InterpretToEndParams = struct

      type t = {
        textDocument : VersionedTextDocumentIdentifier.t;
      } [@@deriving yojson]

    end

    module StepBackwardParams = struct

      type t = {
        textDocument : VersionedTextDocumentIdentifier.t;
      } [@@deriving yojson]

    end

    module StepForwardParams = struct

      type t = {
        textDocument : VersionedTextDocumentIdentifier.t;
      } [@@deriving yojson]

    end

    type t =
    | Std of Lsp.Client_notification.t
    | InterpretToEnd of InterpretToEndParams.t
    | InterpretToPoint of InterpretToPointParams.t
    | StepForward of StepForwardParams.t
    | StepBackward of StepBackwardParams.t

    let of_jsonrpc (Jsonrpc.Notification.{ method_; params } as notif) =
      let open Lsp.Import.Result.O in
      match method_ with
      | "prover/interpretToPoint" ->
        let+ params = Lsp.Import.Json.message_params params InterpretToPointParams.t_of_yojson in
        InterpretToPoint params
      | "prover/stepBackward" ->
        let+ params = Lsp.Import.Json.message_params params StepBackwardParams.t_of_yojson in
        StepBackward params
      | "prover/stepForward" ->
        let+ params = Lsp.Import.Json.message_params params StepForwardParams.t_of_yojson in
        StepForward params
      | "prover/interpretToEnd" ->
        let+ params = Lsp.Import.Json.message_params params InterpretToEndParams.t_of_yojson in
        InterpretToEnd params
      | _ ->
        let+ notif = Lsp.Client_notification.of_jsonrpc notif in
        Std notif

  end

  module Server = struct

    module ProofViewParams = struct

      type t = {
        textDocument : VersionedTextDocumentIdentifier.t;
        proofState : ProofState.t option;
      } [@@deriving yojson]

    end

    module MoveCursorParams = struct

      type t = {
        textDocument : VersionedTextDocumentIdentifier.t;
        position : Position.t;
      } [@@deriving yojson]

    end

    type t = 
    | ProofView of ProofViewParams.t
    | MoveCursor of MoveCursorParams.t

    let proofView textDocument proofState =
      let method_ = "prover/proofView" in
      let params = ProofViewParams.{ textDocument; proofState } in
      let params = ProofViewParams.yojson_of_t params in
      let params = Some (Jsonrpc.Structured.t_of_yojson params) in
      Jsonrpc.Notification.{ method_; params }

    let moveCursor textDocument position =
      let method_ = "prover/moveCursor" in
      let params = MoveCursorParams.{ textDocument; position } in  
      let params = MoveCursorParams.yojson_of_t params in
      let params = Some (Jsonrpc.Structured.t_of_yojson params) in
      Jsonrpc.Notification.{ method_; params }

  end

end

(* Copy VSRocq Request module *)
module Request = struct
  module Client = struct
    
    (* EasyCrypt-specific requests can be added here later *)
    type 'a t =
    | Std : 'a Lsp.Client_request.t -> 'a t
    
    type packed = Pack : 'a t -> packed
    
    let t_of_jsonrpc (Jsonrpc.Request.{ method_; params } as req) =
      let open Lsp.Import.Result.O in
      (* For now, handle everything as standard LSP *)
      let+ E req = Lsp.Client_request.of_jsonrpc req in
      Pack (Std req)
    
    let yojson_of_result : type a. a t -> a -> Yojson.Safe.t = fun req resp ->
      match req with
      | Std req -> Lsp.Client_request.yojson_of_result req resp
  end
end