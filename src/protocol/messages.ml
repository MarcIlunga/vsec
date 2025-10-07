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

(** Structured message protocol for prover/messages notification *)

open Lsp.Types
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

(** Message severity levels matching LSP DiagnosticSeverity *)
type severity =
  | Error
  | Warning
  | Information
  | Hint
[@@deriving yojson]

(** A single prover message with location information *)
type message = {
  text: string;
  severity: severity;
  range: Range.t;
} [@@deriving yojson]

(** Prover messages notification params *)
type params = {
  textDocument: VersionedTextDocumentIdentifier.t;
  messages: message list;
} [@@deriving yojson]

(** Convert LSP DiagnosticSeverity to our severity type *)
let severity_of_diagnostic_severity = function
  | DiagnosticSeverity.Error -> Error
  | DiagnosticSeverity.Warning -> Warning
  | DiagnosticSeverity.Information -> Information
  | DiagnosticSeverity.Hint -> Hint

(** Convert diagnostic message union to plain text *)
let text_of_diagnostic_message = function
  | `String s -> s
  | `MarkupContent mc -> 
      (* Extract plain text from MarkupContent *)
      mc.MarkupContent.value

(** Convert LSP Diagnostic to our message type *)
let message_of_diagnostic (d: Diagnostic.t) : message =
  let severity = match d.severity with
    | None -> Information
    | Some s -> severity_of_diagnostic_severity s
  in
  let text = text_of_diagnostic_message d.message in
  {
    text;
    severity;
    range = d.range;
  }

(** Create params from URI and diagnostics list *)
let create_params (uri: string) (diagnostics: Diagnostic.t list) : params =
  let text_document = VersionedTextDocumentIdentifier.create
    ~uri:(DocumentUri.of_string uri)
    ~version:1
  in
  let messages = List.map message_of_diagnostic diagnostics in
  { textDocument = text_document; messages }

(** Convert params to Yojson for sending *)
let to_yojson (p: params) : Yojson.Safe.t =
  yojson_of_params p

(** Create LSP notification JSON for prover/messages *)
let create_notification (uri: string) (diagnostics: Diagnostic.t list) : Yojson.Safe.t =
  let params = create_params uri diagnostics in
  `Assoc [
    ("jsonrpc", `String "2.0");
    ("method", `String "prover/messages");
    ("params", to_yojson params);
  ]

