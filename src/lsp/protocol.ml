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
open LspData

module Notification = struct

  module Server = struct

    module PublishDiagnosticsParams = struct

      type t = {
        uri : Uri.t;
        diagnostics : Diagnostic.t list
      } [@@deriving yojson]

    end

    type t =
    | PublishDiagnostics of PublishDiagnosticsParams.t

    let jsonrpc_of_t notification =
      let method_, params = match notification with
      | PublishDiagnostics params ->
        "textDocument/publishDiagnostics", PublishDiagnosticsParams.yojson_of_t params
      in
      JsonRpc.Notification.{ method_; params }      

  end

  module Client = struct

    module DidOpenTextDocumentParams = struct

      type t = {
        textDocument: TextDocumentItem.t;
      } [@@deriving yojson]

    end

    module DidChangeTextDocumentParams = struct

      type t = {
        textDocument: VersionedTextDocumentIdentifier.t;
        contentChanges: TextDocumentContentChangeEvent.t list;
      } [@@deriving yojson]

    end

    module DidCloseTextDocumentParams = struct

      type t = {
        textDocument: VersionedTextDocumentIdentifier.t;
      } [@@deriving yojson]

    end

    module DidChangeConfigurationParams = struct

      type t = {
        settings : Yojson.Safe.t;
      }

      let t_of_yojson json =
        match json with
        | `Assoc [(`Str "settings", settings)] -> { settings }
        | _ -> raise (Invalid_argument "DidChangeConfigurationParams of json")

    end

    type t =
    | DidOpenTextDocument of DidOpenTextDocumentParams.t
    | DidChangeTextDocument of DidChangeTextDocumentParams.t
    | DidCloseTextDocument of DidCloseTextDocumentParams.t
    | DidChangeConfiguration of DidChangeConfigurationParams.t
    | Initialized
    | Exit
    | UnknownNotification

    let t_of_jsonrpc JsonRpc.Notification.{ method_; params } =
      match method_ with
      | "textDocument/didOpen" ->
        DidOpenTextDocument DidOpenTextDocumentParams.(t_of_yojson params)
      | "textDocument/didChange" ->
        DidChangeTextDocument DidChangeTextDocumentParams.(t_of_yojson params)
      | "textDocument/didClose" ->
        DidCloseTextDocument DidCloseTextDocumentParams.(t_of_yojson params)
      | "exit" ->
        Exit
      | _ ->
        UnknownNotification

  end

end

module Request = struct

  module Server = struct

    module ConfigurationParams = struct

      type t = { items: ConfigurationItem.t list } [@@deriving yojson]

    end

    type t =
    | Configuration of int * ConfigurationParams.t

    let jsonrpc_of_t req =
      let id, method_, params = match req with
      | Configuration (id,params) ->
        id, "workspace/configuration", ConfigurationParams.yojson_of_t params
      in
      JsonRpc.Request.{ id; method_; params }      

  end

  module Client = struct

    module HoverParams = struct

      type t = {
        textDocument : TextDocumentIdentifier.t;
        position : Position.t
      } [@@deriving yojson]

    end

    module MarkupContent = struct
      type markup_kind = Plaintext | Markdown [@@deriving yojson]
      
      type t = {
        kind : markup_kind;
        value : string;
      } [@@deriving yojson]
      
      let create ?(kind=Markdown) value = { kind; value }
    end

    module HoverResult = struct
      type contents = 
        | String of string
        | MarkupContent of MarkupContent.t
      [@@deriving yojson]

      type t = {
        contents : contents;
      } [@@deriving yojson]

    end

    module InitializeParams = struct
      
      type t = {
        processId: int option;
        rootUri: Uri.t option;
        initializationOptions : Yojson.Safe.t option;
      }

      let t_of_yojson json =
        let open Yojson.Safe.Util in
        let processId = json |> member "processId" |> to_option to_int in
        let rootUri = json |> member "rootUri" |> to_option Uri.t_of_yojson in
        let initializationOptions = json |> member "initializationOptions" |> function
          | `Null -> None
          | v -> Some v
        in
        { processId; rootUri; initializationOptions }

      let yojson_of_t { processId; rootUri; initializationOptions } =
        let fields = [
          ("processId", match processId with None -> `Null | Some i -> `Int i);
          ("rootUri", match rootUri with None -> `Null | Some uri -> Uri.yojson_of_t uri);
        ] in
        let fields = match initializationOptions with
          | None -> fields
          | Some opts -> ("initializationOptions", opts) :: fields
        in
        `Assoc fields

    end

    module InitializeResult = struct
      
      type t = {
        capabilities: ServerCapabilities.t; 
        serverInfo: ServerInfo.t;
      } [@@deriving yojson]

    end

    module CompletionParams = struct

      type t = {
        textDocument : TextDocumentIdentifier.t;
        position : Position.t;
      } [@@deriving yojson] [@@yojson.allow_extra_fields]

    end

    module CompletionResult = struct 

      type t = {
        isIncomplete : bool;
        items : CompletionItem.t list;
      } [@@deriving yojson]
      
    end

    module DefinitionParams = struct

      type t = {
        textDocument : TextDocumentIdentifier.t;
        position : Position.t;
      } [@@deriving yojson] [@@yojson.allow_extra_fields]

    end

    module Location = struct

      type t = {
        uri : Uri.t;
        range : Range.t;
      } [@@deriving yojson]

    end

    module DefinitionResult = struct

      type t = Location.t list [@@deriving yojson]

    end

    module DocumentSymbolParams = struct

      type t = {
        textDocument : TextDocumentIdentifier.t;
      } [@@deriving yojson] [@@yojson.allow_extra_fields]

    end

    module SymbolKind = struct
      type t = int [@@deriving yojson]
      
      let file = 1
      let module_ = 2  
      let namespace = 3
      let package = 4
      let class_ = 5
      let method_ = 6
      let property = 7
      let field = 8
      let constructor = 9
      let enum = 10
      let interface = 11
      let function_ = 12
      let variable = 13
      let constant = 14
      let string = 15
      let number = 16
      let boolean = 17
      let array = 18
    end

    module DocumentSymbol = struct

      type t = {
        name : string;
        kind : SymbolKind.t;
        range : Range.t;
        selectionRange : Range.t;
      } [@@deriving yojson]

    end

    module DocumentSymbolResult = struct

      type t = DocumentSymbol.t list [@@deriving yojson]

    end

    module ReferenceContext = struct
      type t = {
        includeDeclaration : bool;
      } [@@deriving yojson]
    end

    module ReferenceParams = struct
      type t = {
        textDocument : TextDocumentIdentifier.t;
        position : Position.t;
        context : ReferenceContext.t;
      } [@@deriving yojson] [@@yojson.allow_extra_fields]
    end

    module ReferenceResult = struct

      type t = Location.t list [@@deriving yojson]

    end

    module SemanticTokensParams = struct
      type t = {
        textDocument : TextDocumentIdentifier.t;
      } [@@deriving yojson] [@@yojson.allow_extra_fields]
    end

    module SemanticTokensResult = struct
      type t = {
        data : int list;
      } [@@deriving yojson]
    end

    type 'rsp params =
    | Initialize : InitializeParams.t -> InitializeResult.t params
    | Shutdown : unit params
    | Hover : HoverParams.t -> HoverResult.t option params
    | Completion : CompletionParams.t -> CompletionResult.t params
    | Definition : DefinitionParams.t -> DefinitionResult.t params
    | DocumentSymbol : DocumentSymbolParams.t -> DocumentSymbolResult.t params
    | References : ReferenceParams.t -> ReferenceResult.t params
    | SemanticTokens : SemanticTokensParams.t -> SemanticTokensResult.t params
    | UnknownRequest : unit params

    type t = Pack : int * _ params -> t

    let t_of_jsonrpc JsonRpc.Request.{ id; method_; params } =
      match method_ with
      | "initialize" -> Pack (id, Initialize InitializeParams.(t_of_yojson params))
      | "shutdown" -> Pack (id, Shutdown)
      | "textDocument/hover" -> Pack (id, Hover HoverParams.(t_of_yojson params))
      | "textDocument/completion" -> Pack (id, Completion CompletionParams.(t_of_yojson params))
      | "textDocument/definition" -> Pack (id, Definition DefinitionParams.(t_of_yojson params))
      | "textDocument/documentSymbol" -> Pack (id, DocumentSymbol DocumentSymbolParams.(t_of_yojson params))
      | "textDocument/references" -> Pack (id, References ReferenceParams.(t_of_yojson params))
      | "textDocument/semanticTokens/full" -> Pack (id, SemanticTokens SemanticTokensParams.(t_of_yojson params))
      | _ -> Pack (id, UnknownRequest)

    let yojson_of_response : type a. a params -> a -> Yojson.Safe.t =
      fun req resp ->
        match req with
        | Initialize _ -> InitializeResult.yojson_of_t resp
        | Shutdown -> yojson_of_unit resp
        | Hover _ -> yojson_of_option HoverResult.yojson_of_t resp
        | Completion _ -> CompletionResult.yojson_of_t resp
        | Definition _ -> DefinitionResult.yojson_of_t resp
        | DocumentSymbol _ -> DocumentSymbolResult.yojson_of_t resp
        | References _ -> ReferenceResult.yojson_of_t resp
        | SemanticTokens _ -> SemanticTokensResult.yojson_of_t resp
        | UnknownRequest -> yojson_of_unit resp

    type 'b dispatch = {
      f : 'a. id:int -> 'a params -> 'a * 'b
    }

    let yojson_of_result : JsonRpc.Request.t -> 'a dispatch -> Yojson.Safe.t * 'a =
      fun req foo ->
        let Pack(id, req) = t_of_jsonrpc req in
        let resp, data = foo.f ~id req in
        let resp = yojson_of_response req resp in
        let result = Ok(resp) in
        JsonRpc.Response.(yojson_of_t { id; result }), data

    (*
    type result =
    | DocumentHover of DocumentHoverResult.t option
    | Initialize of InitializeResult.t

    let yojson_of_result = function
    | DocumentHover None -> `Null
    | DocumentHover (Some result) -> DocumentHoverResult.yojson_of_t result
    | Initialize 

    type t = { id : int; result : result }

    let yojson_of_t { id; result } =
      JsonRpc.Response.(yojson_of_t { id; result = Ok (yojson_of_result result) })
      *)

  end

end
