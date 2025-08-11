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

(** This toplevel implements an LSP-based server language for VsCode,
    used by the VsCoq extension. *)

open Lsp
open LspData
open ExtProtocol

let init_state : EcLib.EcScope.scope option ref = ref None
let get_init_state () =
  match !init_state with
  | Some st -> st
  | None -> assert false (* TODO fixme *)

type tab = { st : Dm.DocumentManager.state; visible : bool }

let states : (string, tab) Hashtbl.t = Hashtbl.create 39

let check_mode = ref LspData.Settings.Mode.Continuous

let Dm.Types.Log log = Dm.Log.mk_log "lspManager"

let conf_request_id = 3456736879

let server_info = LspData.ServerInfo.{
  name = "easycrypt-language-server";
  version = "1.0.0";
} 

type lsp_event = 
  | Receive of JsonRpc.t option
  | Send of JsonRpc.t

type event =
 | LspManagerEvent of lsp_event
 | DocumentManagerEvent of Uri.t * Dm.DocumentManager.event
 | Notification of notification
 | LogEvent of Dm.Log.event

type events = event Sel.event list

let lsp : event Sel.event =
  Sel.on_httpcle Unix.stdin (function
    | Ok buff ->
      begin
        let msg = Bytes.to_string buff in
        log @@ "=== LSP MESSAGE RECEIVED ===";
        log @@ "Message length: " ^ (string_of_int (String.length msg));
        log @@ "Message preview: " ^ (String.sub msg 0 (min 100 (String.length msg)));
        try 
          let json = Yojson.Safe.from_string msg in
          log @@ "=== JSON PARSED SUCCESSFULLY ===";
          let rpc = JsonRpc.t_of_yojson json in
          log @@ "=== RPC PARSED SUCCESSFULLY ===";
          LspManagerEvent (Receive (Some rpc))
        with exn ->
          log @@ "=== JSON/RPC PARSE ERROR ===";
          log @@ "Parse error: " ^ (Printexc.to_string exn);
          LspManagerEvent (Receive None)
      end
    | Error exn ->
        log @@ "=== INPUT READ ERROR ===";
        log @@ ("Input read error: " ^ Printexc.to_string exn);
        (* do not remove this line otherwise the server stays running in some scenarios *)
        exit 0)
  |> fst
  |> Sel.name "lsp"
  |> Sel.make_recurring
  |> Sel.set_priority Dm.PriorityManager.lsp_message

let output_json obj =
  let msg  = Yojson.Safe.pretty_to_string ~std:true obj in
  let size = String.length msg in
  let s = Printf.sprintf "Content-Length: %d\r\n\r\n%s" size msg in
  log @@ "sent: " ^ msg;
  ignore(Unix.write_substring Unix.stdout s 0 (String.length s)) (* TODO ERROR *)

let output_jsonrpc jsonrpc =
  output_json @@ JsonRpc.yojson_of_t jsonrpc

let inject_dm_event uri x : event Sel.event =
  Sel.map (fun e -> DocumentManagerEvent(uri,e)) x

let inject_notification x : event Sel.event =
  Sel.map (fun x -> Notification(x)) x

let inject_debug_event x : event Sel.event =
  Sel.map (fun x -> LogEvent x) x

let inject_dm_events (uri,l) =
  List.map (inject_dm_event uri) l

let inject_notifications l =
  List.map inject_notification l

let inject_debug_events l =
  List.map inject_debug_event l

let do_configuration settings = 
  let open LspData.Settings in
  check_mode := settings.proof.mode

let send_configuration_request () =
  let id = conf_request_id in
  let mk_configuration_item section =
    ConfigurationItem.({ scopeUri = None; section = Some section })
  in
  let items = List.map mk_configuration_item ["vscoq"] in
  let req = Request.Server.(jsonrpc_of_t @@ Configuration (id, { items })) in
  Send (Request req)

let do_initialize ~id params =
  log "=== INITIALIZE REQUEST RECEIVED ===";
  flush_all ();
  
  (* Handle initialization options like VSRocq *)
  let Request.Client.InitializeParams.{ initializationOptions } = params in
  begin match initializationOptions with
  | None -> log "No initialization options provided"
  | Some initializationOptions ->
    log "=== Processing initialization options ===";
    do_configuration @@ LspData.Settings.t_of_yojson initializationOptions;
  end;
  
  (* Match VSRocq capabilities and enable ALL features we advertise! *)
  let capabilities = LspData.ServerCapabilities.{
    textDocumentSync = Incremental;
    completionProvider = { 
      resolveProvider = Some false; 
      triggerCharacters = None; 
      allCommitCharacters = None; 
      completionItem = None 
    };
    hoverProvider = true;
    definitionProvider = Some true;
    documentSymbolProvider = Some true;
    (* Enable semantic tokens like we advertise! *)
    semanticTokensProvider = Some {
      legend = {
        tokenTypes = ["keyword"; "tactic"; "module"; "theory"; "operator"; "predicate"; "goal"; "hypothesis"; "type"; "variable"];
        tokenModifiers = ["local"; "global"; "imported"; "proof"];
      };
      range = Some true;
      full = Some true;
    };
  } in
  
  let initialize_result = Request.Client.InitializeResult.{
    capabilities = capabilities; 
    serverInfo = server_info;
  } in
  
  log "=== INITIALIZATION COMPLETE - SERVER READY ===";
  flush_all ();
  let debug_events = Dm.Log.lsp_initialization_done () |> inject_debug_events in
  Ok initialize_result, debug_events@[Sel.now @@ LspManagerEvent (send_configuration_request ())]

let do_shutdown ~id params =
  Ok(()), []

let do_exit () =
  exit 0

let parse_loc json =
  let open Yojson.Safe.Util in
  let line = json |> member "line" |> to_int in
  let character = json |> member "character" |> to_int in
  Position.{ line ; character }

let publish_diagnostics uri doc =
  let diagnostics = Dm.DocumentManager.diagnostics doc in
  let notification = Protocol.Notification.Server.PublishDiagnostics {
    uri;
    diagnostics
  }
  in
  output_jsonrpc @@ Notification Protocol.Notification.Server.(jsonrpc_of_t notification)

let send_highlights uri doc =
  let { Dm.DocumentManager.parsed; checked; checked_by_delegate; legacy_highlight } =
    Dm.DocumentManager.executed_ranges doc in
  let notification = Notification.Server.UpdateHighlights {
    uri;
    parsedRange = parsed;
    processingRange = checked;
    processedRange = legacy_highlight;
  }
  in
  output_jsonrpc @@ Notification Notification.Server.(jsonrpc_of_t notification)

let update_view uri st =
  send_highlights uri st;
  publish_diagnostics uri st

let open_new_document uri text =
  log @@ "=== OPENING NEW DOCUMENT: " ^ (Uri.to_string uri) ^ " ===";
  let vst = get_init_state () in
  let st, events = try 
    log @@ "Initializing document manager for: " ^ (Uri.to_string uri);
    Dm.DocumentManager.init vst uri ~text 
  with e -> 
    log @@ "Error initializing document: " ^ (Printexc.to_string e);
    raise e
  in
  let st = Dm.DocumentManager.validate_document st in
  Hashtbl.add states (Uri.path uri) { st; visible = true };
  log @@ "Document successfully added to states, total: " ^ (string_of_int (Hashtbl.length states));
  update_view uri st;
  inject_dm_events (uri, events)

let textDocumentDidOpen params =
  let Notification.Client.DidOpenTextDocumentParams.{ textDocument = { uri; text } } = params in
  log @@ "=== textDocument/didOpen REQUEST ===";
  log @@ "URI: " ^ (Uri.to_string uri);
  log @@ "Text length: " ^ (string_of_int (String.length text)) ^ " characters";
  flush_all ();
  
  match Hashtbl.find_opt states (Uri.path uri) with
  | None -> 
    log @@ "Document not found in states, opening new document";
    open_new_document uri text
  | Some { st } ->
    log @@ "Document already exists in states, updating";
    (* Document already exists, just update view *)
    update_view uri st;
    []

let textDocumentDidChange params =
  let Notification.Client.DidChangeTextDocumentParams.{ textDocument; contentChanges } = params in
  let uri = textDocument.uri in
  let { st; visible } = Hashtbl.find states (Uri.path uri) in
  let mk_text_edit TextDocumentContentChangeEvent.{ range; text } =
    Option.get range, text
  in
  let text_edits = List.map mk_text_edit contentChanges in
  let st = Dm.DocumentManager.apply_text_edits st text_edits in
  let st = Dm.DocumentManager.validate_document st in
  Hashtbl.replace states (Uri.path uri) { st; visible };
  update_view uri st;
  inject_dm_events (uri, [])

let textDocumentDidSave params =
  let Notification.Client.DidChangeTextDocumentParams.{ textDocument } = params in
  let uri = textDocument.uri in
  let { st; visible } = Hashtbl.find states (Uri.path uri) in
  let st = Dm.DocumentManager.validate_document st in
  Hashtbl.replace states (Uri.path uri) { st; visible };
  update_view uri st

let textDocumentDidClose params =
  let Notification.Client.DidCloseTextDocumentParams.{ textDocument } = params in
  let uri = textDocument.uri in
  let path = Uri.path uri in
  begin match Hashtbl.find_opt states path with
  | None -> log @@ "[textDocumentDidClose] closed document with no state"
  | Some { st } -> Hashtbl.replace states path { st; visible = false }
  end;
  []

let textDocumentHover ~id params = 
  let Request.Client.HoverParams.{ textDocument; position } = params in
  
  log @@ "textDocumentHover request for: " ^ (Uri.to_string textDocument.uri);
  log @@ "Available documents in states: " ^ (string_of_int (Hashtbl.length states));
  
  match Hashtbl.find_opt states (Uri.path textDocument.uri) with
  | None -> 
    log @@ "[textDocumentHover] ignoring event on non existing document"; 
    Ok None
  | Some { st } ->
    log @@ "Found document state for hover"; 
    match Dm.DocumentManager.hover st position with
    | Some (Ok contents) -> 
      (* Use MarkupContent like VSCoq *)
      let markup_content = Request.Client.MarkupContent.create contents in
      Ok (Some (Request.Client.HoverResult.{ contents = Request.Client.HoverResult.MarkupContent markup_content }))
    | Some (Error _) | None -> 
      Ok None

let progress_hook uri () =
  let { st } = Hashtbl.find states (Uri.path uri) in
  update_view uri st

let coqtopInterpretToPoint params =
  let Notification.Client.InterpretToPointParams.{ textDocument; position } = params in
  let uri = textDocument.uri in
  let { st; visible } = Hashtbl.find states (Uri.path uri) in
  let (st, events) = Dm.DocumentManager.interpret_to_position st position in
  Hashtbl.replace states (Uri.path uri) { st; visible };
  update_view uri st;
  inject_dm_events (uri, events)

let coqtopInterpretToEnd params =
  let Notification.Client.InterpretToEndParams.{ textDocument = { uri } } = params in
  let { st; visible } = Hashtbl.find states (Uri.path uri) in
  let st = Dm.DocumentManager.validate_document st in
  let (st, events) = Dm.DocumentManager.interpret_to_end st in
  Hashtbl.replace states (Uri.path uri) { st; visible };
  update_view uri st;
  inject_dm_events (uri,events)

let coqtopStepBackward params =
  let Notification.Client.StepBackwardParams.{ textDocument = { uri } } = params in
  let { st; visible } = Hashtbl.find states (Uri.path uri) in
  let st = Dm.DocumentManager.validate_document st in
  let (st, events) = Dm.DocumentManager.interpret_to_previous st in
  Hashtbl.replace states (Uri.path uri) { st; visible };
  update_view uri st;
  inject_dm_events (uri,events)

let coqtopStepForward params =
  let Notification.Client.StepForwardParams.{ textDocument = { uri } } = params in
  let { st; visible } = Hashtbl.find states (Uri.path uri) in
  let st = Dm.DocumentManager.validate_document st in
  let (st, events) = Dm.DocumentManager.interpret_to_next st in
  Hashtbl.replace states (Uri.path uri) { st; visible };
  update_view uri st;
  inject_dm_events (uri,events)
  
 let make_CompletionItem (label, typ, path) : CompletionItem.t = 
   {
     label;
     detail = Some typ;
     documentation = Some ("Path: " ^ path);
   } 

let sendDocumentState ~id params = 
  let Request.Client.DocumentStateParams.{ textDocument } = params in
  let uri = textDocument.uri in
  let { st } = Hashtbl.find states (Uri.path uri) in
  let document = Dm.DocumentManager.Internal.string_of_state st in
  Ok Request.Client.DocumentStateResult.{ document }, []

let workspaceDidChangeConfiguration params = 
  let Protocol.Notification.Client.DidChangeConfigurationParams.{ settings } = params in
  let settings = Settings.t_of_yojson settings in
  do_configuration settings;
  []

let make_CompletionItem (label, typ, path) : CompletionItem.t = 
  {
    label;
    detail = Some typ;
    documentation = Some ("Path: " ^ path);
  } 

let get_easycrypt_keywords () = [
  "lemma"; "theorem"; "axiom"; "proof"; "qed"; "by"; "auto"; "smt";
  "require"; "import"; "open"; "module"; "type"; "op"; "pred"; "theory";
  "end"; "section"; "declare"; "as"; "export"; "local"; "clone";
  "with"; "remove"; "rename"; "equiv"; "hoare"; "phoare"; "lossless";
  "islossless"; "eager"; "while"; "if"; "then"; "else"; "return";
  "var"; "proc"; "fun"; "let"; "in"; "match"; "case"; "def"
]

let get_easycrypt_tactics () = [
  "trivial"; "reflexivity"; "symmetry"; "transitivity"; "assumption";
  "exact"; "apply"; "rewrite"; "split"; "left"; "right"; "exists";
  "generalize"; "clear"; "intro"; "intros"; "move"; "case"; "elim";
  "induction"; "destruct"; "unfold"; "fold"; "simpl"; "compute";
  "change"; "replace"; "assert"; "cut"; "have"; "suffices"; "wlog";
  "progress"; "first"; "last"; "seq"; "wp"; "sp"; "skip"; "rnd";
  "swap"; "cfold"; "rcondt"; "rcondf"; "inline"; "outline"; "sim"
]

let create_completion_item ~label ~detail =
  LspData.CompletionItem.{
    label;
    detail = Some detail;
    documentation = None;
  }

let textDocumentCompletion ~id params =
  let return_completion ~isIncomplete ~items =
    Ok Request.Client.CompletionResult.{ isIncomplete; items }
  in
  let Request.Client.CompletionParams.{ textDocument; position } = params in
  
  match Hashtbl.find_opt states (Uri.path textDocument.uri) with
  | None -> 
    log @@ "[textDocumentCompletion] ignoring event on non existent document"; 
    return_completion ~isIncomplete:false ~items:[]
  | Some { st } ->
    try
      (* Try to get completions from document manager first *)
      (* For now, use our static completions until we have proper DM integration *)
      let keywords = get_easycrypt_keywords () in
      let tactics = get_easycrypt_tactics () in
      
      let keyword_items = List.map (fun kw -> 
        create_completion_item ~label:kw ~detail:"EasyCrypt keyword"
      ) keywords in
      
      let tactic_items = List.map (fun tactic -> 
        create_completion_item ~label:tactic ~detail:"EasyCrypt tactic"
      ) tactics in
      
      (* Add basic type completions *)
      let type_items = [
        create_completion_item ~label:"bool" ~detail:"Boolean type";
        create_completion_item ~label:"int" ~detail:"Integer type";
        create_completion_item ~label:"real" ~detail:"Real type";
        create_completion_item ~label:"True" ~detail:"Boolean constant";
        create_completion_item ~label:"False" ~detail:"Boolean constant";
      ] in
      
      let all_items = keyword_items @ tactic_items @ type_items in
      return_completion ~isIncomplete:false ~items:all_items
    with
    | exn ->
      log @@ "[textDocumentCompletion] error: " ^ (Printexc.to_string exn);
      return_completion ~isIncomplete:false ~items:[]

let textDocumentDefinition ~id params =
  let Request.Client.DefinitionParams.{ textDocument; position } = params in
  
  match Hashtbl.find_opt states (Uri.path textDocument.uri) with
  | None -> 
    log @@ "[textDocumentDefinition] ignoring event on non existing document"; 
    Ok []
  | Some { st } ->
    (* Try to use DocumentManager's jump_to_definition if available *)
    try
      (* For now, return empty list since we don't have jump_to_definition implemented in our DM *)
      (* In the future, this should call: Dm.DocumentManager.jump_to_definition st position *)
      log @@ "[textDocumentDefinition] could not find symbol location"; 
      Ok []
    with
    | exn ->
      log @@ "[textDocumentDefinition] error: " ^ (Printexc.to_string exn);
      Ok []

let textDocumentDocumentSymbol ~id params =
  let Request.Client.DocumentSymbolParams.{ textDocument } = params in
  
  match Hashtbl.find_opt states (Uri.path textDocument.uri) with
  | None -> 
    log @@ "[documentSymbol] ignoring event on non existent document"; 
    Error "Document does not exist"
  | Some { st } -> 
    log @@ "[documentSymbol] getting symbols";
    try
      (* For now, return empty symbols since we don't have get_document_symbols implemented *)
      (* In the future, this should call: Dm.DocumentManager.get_document_symbols st *)
      Ok []
    with
    | exn ->
      log @@ "[documentSymbol] error: " ^ (Printexc.to_string exn);
      Error "Internal error"

let textDocumentReferences ~id params =
  let Request.Client.ReferenceParams.{ textDocument; position; context } = params in
  
  try
    (* Get document state *)
    let { st } = Hashtbl.find states (Uri.path textDocument.uri) in
    
    (* Placeholder: return current position as a reference *)
    let location = Request.Client.Location.{
      uri = textDocument.uri;
      range = {
        start = position;
        end_ = position;
      };
    } in
    
    Ok [location]
    
  with
  | Not_found ->
    Ok []

(* Semantic token types - must match the client configuration *)
module SemanticTokenTypes = struct
  let keyword = 0
  let tactic = 1
  let module_ = 2
  let theory = 3
  let operator = 4
  let predicate = 5
  let goal = 6
  let hypothesis = 7
  let type_ = 8
  let variable = 9
end

module SemanticTokenModifiers = struct
  let local = 1 lsl 0
  let global = 1 lsl 1
  let imported = 1 lsl 2
  let proof = 1 lsl 3
end

let get_easycrypt_semantic_tokens text =
  (* Simple regex-based semantic tokenization for demo *)
  (* In a full implementation, this would use the parsed AST *)
  let keywords = [
    "lemma"; "theorem"; "axiom"; "proof"; "qed"; "by"; "require"; "import"; 
    "open"; "module"; "type"; "op"; "pred"; "theory"; "end"; "section"
  ] in
  let tactics = [
    "trivial"; "reflexivity"; "symmetry"; "apply"; "rewrite"; "split";
    "auto"; "smt"; "exact"; "assumption"
  ] in
  
  let tokens = ref [] in
  let lines = String.split_on_char '\n' text in
  
  List.iteri (fun line_idx line ->
    let words = String.split_on_char ' ' line in
    let char_pos = ref 0 in
    
    List.iter (fun word ->
      let word = String.trim word in
      if word <> "" then (
        let token_type = 
          if List.mem word keywords then SemanticTokenTypes.keyword
          else if List.mem word tactics then SemanticTokenTypes.tactic
          else -1
        in
        
        if token_type >= 0 then (
          tokens := (line_idx, !char_pos, String.length word, token_type, 0) :: !tokens
        )
      );
      char_pos := !char_pos + String.length word + 1
    ) words
  ) lines;
  
  List.rev !tokens

let encode_semantic_tokens tokens =
  (* Encode tokens in LSP format: [deltaLine, deltaStart, length, tokenType, tokenModifiers] *)
  let prev_line = ref 0 in
  let prev_char = ref 0 in
  let encoded = ref [] in
  
  List.iter (fun (line, char, length, token_type, modifiers) ->
    let delta_line = line - !prev_line in
    let delta_char = if delta_line = 0 then char - !prev_char else char in
    
    encoded := delta_line :: delta_char :: length :: token_type :: modifiers :: !encoded;
    
    prev_line := line;
    prev_char := char
  ) tokens;
  
  List.rev !encoded

let textDocumentSemanticTokens ~id params =
  let Request.Client.SemanticTokensParams.{ textDocument } = params in
  
  log @@ "[semanticTokens] Processing: " ^ (Uri.to_string textDocument.uri);
  
  match Hashtbl.find_opt states (Uri.path textDocument.uri) with
  | None ->
    log @@ "[semanticTokens] Document not found"; 
    Ok Request.Client.SemanticTokensResult.{ data = [] }
  | Some { st } ->
    try
      let doc = Dm.DocumentManager.Internal.document st in
      let raw_doc = Dm.Document.raw_document doc in
      let text = Dm.RawDocument.text raw_doc in
      
      log @@ "[semanticTokens] Analyzing text of length: " ^ (string_of_int (String.length text));
      
      (* Get semantic tokens *)
      let tokens = get_easycrypt_semantic_tokens text in
      let encoded_tokens = encode_semantic_tokens tokens in
      
      log @@ "[semanticTokens] Generated " ^ (string_of_int (List.length tokens)) ^ " tokens";
      log @@ "[semanticTokens] Encoded to " ^ (string_of_int (List.length encoded_tokens)) ^ " values";
      
      Ok Request.Client.SemanticTokensResult.{ data = encoded_tokens }
      
    with
    | exn ->
      log @@ "[semanticTokens] Error: " ^ (Printexc.to_string exn);
      Ok Request.Client.SemanticTokensResult.{ data = [] }

let dispatch_request : type a. id:int -> a Protocol.Request.Client.params -> (a,string) result * events =
  fun ~id req ->
  match req with
  | Initialize params ->
    do_initialize ~id params
  | Shutdown ->
    do_shutdown ~id ()
  | Hover params ->
    textDocumentHover ~id params, []
  | Completion params ->
    textDocumentCompletion ~id params, []
  | Definition params ->
    textDocumentDefinition ~id params, []
  | DocumentSymbol params ->
    textDocumentDocumentSymbol ~id params, []
  | References params ->
    textDocumentReferences ~id params, []
  | SemanticTokens params ->
    log @@ "[dispatch] SemanticTokens request received";
    textDocumentSemanticTokens ~id params, []
  | UnknownRequest -> 
    log @@ "[dispatch] Unknown request"; 
    Ok(()), []

let dispatch_ext_request : type a. id:int -> a Request.Client.params -> (a,string) result * events =
  fun ~id req ->
  match req with
  | DocumentState params -> sendDocumentState ~id params
  | Reset _ -> Ok (), []
  | About _ -> Ok "VsEc - EasyCrypt Language Server", []
  | Check _ -> Ok "Not implemented", []
  | Locate _ -> Ok "Not implemented", []
  | Print _ -> Ok "Not implemented", []
  | Search _ -> Ok (), []

let dispatch_notification = 
  let open Protocol.Notification.Client in function 
  | DidOpenTextDocument params ->
    textDocumentDidOpen params
  | DidChangeTextDocument params ->
    textDocumentDidChange params
  | DidCloseTextDocument params ->
    textDocumentDidClose params
  | DidChangeConfiguration params ->
    workspaceDidChangeConfiguration params
  | Initialized -> []
  | Exit ->
    do_exit ()
  | UnknownNotification -> log "Received unknown notification"; []

let dispatch_ext_notification =
  let open Notification.Client in function
  | InterpretToPoint params -> coqtopInterpretToPoint params
  | InterpretToEnd params -> coqtopInterpretToEnd params
  | StepBackward params -> coqtopStepBackward params
  | StepForward params -> coqtopStepForward params
  | Std notif -> dispatch_notification notif

let dispatch = Request.Client.{ dispatch_std = dispatch_request; dispatch_ext = dispatch_ext_request }

let handle_lsp_event = function
  | Receive None ->
      [lsp] (* Re-add lsp event to keep listening *)
  | Receive (Some rpc) ->
    lsp :: (* Make the event recurrent like VSRocq *)
    begin try
      begin match rpc with
      | Request req ->
          log @@ "=== UI REQUEST: " ^ req.method_ ^ " ===";
          flush_all ();
          let resp, events = Request.Client.yojson_of_result req dispatch in
          log @@ "=== REQUEST PROCESSED ===";
          flush_all ();
          output_json resp;
          events
      | Notification notif ->
        dispatch_ext_notification @@ Notification.Client.t_of_jsonrpc notif
      | Response resp ->
          log @@ "got unknown response";
          []
      end
    with Ppx_yojson_conv_lib__Yojson_conv.Of_yojson_error(exn,json) ->
      log @@ "error parsing json: " ^ Yojson.Safe.pretty_to_string json;
      []
    end
  | Send jsonrpc ->
    output_json (JsonRpc.yojson_of_t jsonrpc); []

let pr_lsp_event = function
  | Receive jsonrpc ->
    "Request"
  | Send jsonrpc ->
    "Send"

let output_notification = function
| QueryResultNotification params ->
  output_jsonrpc @@ Notification Notification.Server.(jsonrpc_of_t @@ SearchResult params)

let handle_event = function
  | LspManagerEvent e -> handle_lsp_event e
  | DocumentManagerEvent (uri, e) ->
    begin match Hashtbl.find_opt states (Uri.path uri) with
    | None ->
      log @@ "ignoring event on non-existing document";
      []
    | Some { st; visible } ->
      let (ost, events) = Dm.DocumentManager.handle_event e st in
      begin match ost with
        | None -> ()
        | Some st ->
          Hashtbl.replace states (Uri.path uri) { st; visible };
          update_view uri st
      end;
      inject_dm_events (uri, events)
    end
  | Notification notification ->
    output_notification notification; []
  | LogEvent e ->
    Dm.Log.handle_event e; []

let pr_event = function
  | LspManagerEvent e -> pr_lsp_event e
  | DocumentManagerEvent (uri, e) ->Format.asprintf "%a" Dm.DocumentManager.pp_event e
  | Notification _ -> "notif"
  | LogEvent _ -> "debug"

let init () =
  (* Initialize EasyCrypt state (similar to VSRocq's Vernacstate.freeze_full_state) *)
  let gstate = EcLib.EcGState.create () in
  let scope = EcLib.EcScope.empty gstate in
  init_state := Some scope;
  [lsp]
