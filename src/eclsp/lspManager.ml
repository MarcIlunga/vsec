(* LSP Manager for EasyCrypt - Adapted from VSRocq *)

open Lsp.Types
open Protocol
open Protocol.LspWrapper
open Protocol.ExtProtocol

let init_state : EcLib.EcScope.scope option ref = ref None
let get_init_state () =
  match !init_state with
  | Some st -> st
  | None -> failwith "EasyCrypt initial state not available"

type tab = { st : Dm.DocumentManager.state; visible : bool }

let states : (string, tab) Hashtbl.t = Hashtbl.create 39

let Dm.Types.Log log = Dm.Log.mk_log "lspManager"

let server_info = InitializeResult.create_serverInfo
  ~name:"vsec-language-server"
  ~version:"0.1.0"
  ()

type lsp_event = 
  | Receive of Jsonrpc.Packet.t option
  | Send of Jsonrpc.Packet.t

type event =
 | LspManagerEvent of lsp_event
 | DocumentManagerEvent of Lsp.Types.DocumentUri.t * Dm.DocumentManager.event
 | Notification of Lsp.Server_notification.t (* Simplified - use standard LSP notifications *)
 | LogEvent of Dm.Log.event

type events = event Sel.Event.t list

(* Copy VSRocq stdin reading with httpcle *)
let lsp : event Sel.Event.t =
  Sel.On.httpcle ~name:"lsp" Unix.stdin (function
    | Ok buff ->
      begin
        log (fun () -> "UI req ready");
        try LspManagerEvent (Receive (Some (Jsonrpc.Packet.t_of_yojson (Yojson.Safe.from_string (Bytes.to_string buff)))))
        with exn ->
          log (fun () -> "failed to decode json");
          LspManagerEvent (Receive None)
      end
    | Error exn ->
        log (fun () -> ("failed to read message: " ^ Printexc.to_string exn));
        (* do not remove this line otherwise the server stays running in some scenarios *)
        exit 0)

let pr_event event = "Event" (* simplified for EasyCrypt *)

let init () =
  (* Initialize EasyCrypt state like VSRocq initializes Vernacstate *)
  let gstate = EcLib.EcGState.create () in
  let scope = EcLib.EcScope.empty gstate in
  init_state := Some scope;
  log (fun () -> "EasyCrypt state initialized");
  (* Return the lsp event to start reading *)
  [lsp]

(* Copy VSRocq do_initialize function, adapted for EasyCrypt *)
type error = { message : string; code : int option }

let rec do_initialize id params =
  let Lsp.Types.InitializeParams.{ initializationOptions = _ } = params in
  log (fun () -> "Processing Initialize request");
  
  (* For now, ignore initializationOptions - will add EasyCrypt settings later *)
  let textDocumentSync = `TextDocumentSyncKind Lsp.Types.TextDocumentSyncKind.Incremental in
  let completionProvider = Lsp.Types.CompletionOptions.create ~resolveProvider:false () in
  let hoverProvider = `Bool true in
  let capabilities = Lsp.Types.ServerCapabilities.create
    ~textDocumentSync
    ~completionProvider
    ~hoverProvider
  ()
  in
  let initialize_result = Lsp.Types.InitializeResult.{
    capabilities = capabilities; 
    serverInfo = Some server_info;
  } in
  log (fun () -> "EasyCrypt LSP initialized");
  Ok initialize_result, []

(* Copy VSRocq completion and hover functions *)
and textDocumentCompletion id params =
  let return_completion ~isIncomplete ~items =
    Ok (Some (`CompletionList (Lsp.Types.CompletionList.create ~isIncomplete ~items ())))
  in
  let Lsp.Types.CompletionParams.{ textDocument = { uri }; position } = params in
  match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path uri) with
  | None -> 
    log (fun () -> "[textDocumentCompletion] ignoring event on non existent document"); 
    Error( {code=None; message="Document does not exist"} ), []
  | Some { st } -> 
    (* For now, return basic EasyCrypt keywords - will integrate with DM later *)
    let basic_items = [
      Lsp.Types.CompletionItem.create ~label:"lemma" ~kind:CompletionItemKind.Keyword ();
      Lsp.Types.CompletionItem.create ~label:"theorem" ~kind:CompletionItemKind.Keyword ();
      Lsp.Types.CompletionItem.create ~label:"proof" ~kind:CompletionItemKind.Keyword ();
      Lsp.Types.CompletionItem.create ~label:"qed" ~kind:CompletionItemKind.Keyword ();
    ] in
    return_completion ~isIncomplete:false ~items:basic_items, []

and textDocumentHover id params = 
  let Lsp.Types.HoverParams.{ textDocument; position } = params in
  match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path textDocument.uri) with
  | None -> 
    log (fun () -> "[textDocumentHover] ignoring event on non existing document"); 
    Ok None, []
  | Some { st } ->
    match Dm.DocumentManager.hover st position with
    | Some contents -> Ok (Some (Lsp.Types.Hover.create ~contents:(`MarkupContent contents) ())), []
    | _ -> Ok None, []

(* Copy VSRocq dispatch functions exactly, adapted for EasyCrypt *)
and dispatch_std_request : type a. Jsonrpc.Id.t -> a Lsp.Client_request.t -> (a, error) result * events =
  fun id req ->
  match req with
  | Initialize params ->
    do_initialize id params
  | Shutdown ->
    log (fun () -> "Shutdown request received"); Ok (), []
  | TextDocumentCompletion params ->
    let result, events = textDocumentCompletion id params in result, events
  | TextDocumentHover params ->
    let result, events = textDocumentHover id params in result, events
  | UnknownRequest _ | _  -> Error ({message="Received unknown request"; code=None}), []

and dispatch_request : type a. Jsonrpc.Id.t -> a Request.Client.t -> (a, error) result * events =
  fun id req ->
  match req with
  | Std req -> dispatch_std_request id req

(* Copy VSRocq injection functions *)
let inject_dm_event uri x : event Sel.Event.t =
  Sel.Event.map (fun e -> DocumentManagerEvent(uri,e)) x

let inject_notification x : event Sel.Event.t =
  Sel.Event.map (fun x -> Notification(x)) x

let inject_debug_event x : event Sel.Event.t =
  Sel.Event.map (fun x -> LogEvent x) x

let inject_dm_events (uri,l) =
  List.map (inject_dm_event uri) l

let inject_notifications l =
  List.map inject_notification l

let inject_debug_events l =
  List.map inject_debug_event l

(* Copy VSRocq output_json function *)
let output_json obj =
  log (fun () -> "output_json called");
  let msg  = Yojson.Safe.pretty_to_string ~std:true obj in
  let size = String.length msg in
  let s = Printf.sprintf "Content-Length: %d\r\n\r\n%s" size msg in
  log (fun () -> "sent: " ^ msg);
  let bytes_written = Unix.write_substring Unix.stdout s 0 (String.length s) in
  log (fun () -> Printf.sprintf "Wrote %d bytes to stdout" bytes_written);
  flush stdout;
  log (fun () -> "stdout flushed")

(* Copy VSRocq document functions, adapted for EasyCrypt *)
let open_new_document uri text =
  log (fun () -> ("Opening new document: " ^ (Lsp.Types.DocumentUri.to_path uri)));
  let vst = get_init_state () in
  let st, events = try 
    Dm.DocumentManager.init vst uri ~text 
  with e -> 
    log (fun () -> ("Error initializing document: " ^ (Printexc.to_string e)));
    raise e
  in
  (* For now, skip document validation - will implement later *)
  let st = st in
  Hashtbl.add states (Lsp.Types.DocumentUri.to_path uri) { st ; visible = true; };
  log (fun () -> ("Document added to states, total: " ^ (string_of_int (Hashtbl.length states))));
  inject_dm_events (uri, events)

let textDocumentDidOpen params =
  let Lsp.Types.DidOpenTextDocumentParams.{ textDocument = { uri; text } } = params in
  log (fun () -> ("textDocument/didOpen: " ^ (Lsp.Types.DocumentUri.to_path uri)));
  match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path uri) with
  | None -> 
    log (fun () -> "Document not found, opening new");
    open_new_document uri text
  | Some { st } ->
    log (fun () -> "Document already exists");
    (* Document already exists, skip validation for now *)
    let st = st in
    Hashtbl.replace states (Lsp.Types.DocumentUri.to_path uri) { st; visible = true };
    []

let textDocumentDidChange params =
  let Lsp.Types.DidChangeTextDocumentParams.{ textDocument; contentChanges } = params in
  let uri = textDocument.uri in
  match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path uri) with
    | None -> log (fun () -> "[textDocumentDidChange] ignoring event on non-existing document"); []
    | Some { st; visible } ->
      let mk_text_edit Lsp.Types.TextDocumentContentChangeEvent.{ range; text } =
        Option.get range, text
      in
      let text_edits = List.map mk_text_edit contentChanges in
      let st, events = Dm.DocumentManager.apply_text_edits st text_edits in
      (* Skip validation for now *)
      let st = st in
      Hashtbl.replace states (Lsp.Types.DocumentUri.to_path uri) { st; visible };
      inject_dm_events (uri, events)

let textDocumentDidClose params =
  let Lsp.Types.DidCloseTextDocumentParams.{ textDocument } = params in
  let path = Lsp.Types.DocumentUri.to_path textDocument.uri in
  begin match Hashtbl.find_opt states path with
  | None -> log (fun () -> "[textDocumentDidClose] closed document with no state")
  | Some { st } -> Hashtbl.replace states path { st; visible = false }
  end;
  []

(* Copy VSRocq hover and completion handlers *)
let textDocumentHover id params = 
  let Lsp.Types.HoverParams.{ textDocument; position } = params in
  match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path textDocument.uri) with
  | None -> 
    log (fun () -> "[textDocumentHover] ignoring event on non existing document"); 
    Ok None
  | Some { st } ->
    match Dm.DocumentManager.hover st position with
    | Some contents -> Ok (Some (Lsp.Types.Hover.create ~contents:(`MarkupContent contents) ()))
    | _ -> Ok None

(* Copy VSRocq handle_lsp_event function *)
let handle_lsp_event = function
  | Receive None -> [lsp]
  | Receive (Some rpc) ->
    lsp :: (* the event is recurrent *)
    begin try
      let json = Jsonrpc.Packet.yojson_of_t rpc in
      let msg = Yojson.Safe.pretty_to_string ~std:true json in
      log (fun () -> "recieved: " ^ msg);
      begin match rpc with
      | Request req ->
          log (fun () -> "ui request: " ^ req.method_);
          log (fun () -> "Request ID present");
          log (fun () -> "About to call Request.Client.t_of_jsonrpc");
          let decode_result = try
            Request.Client.t_of_jsonrpc req
          with 
          | exn -> 
            log (fun () -> "Exception in Request.Client.t_of_jsonrpc: " ^ Printexc.to_string exn);
            Error "Exception during request decode"
          in
          log (fun () -> "Request.Client.t_of_jsonrpc completed");
          begin match decode_result with
          | Error(e) -> log (fun () -> "Error decoding request: " ^ e); []
          | Ok(Pack r) ->
            log (fun () -> "Successfully decoded request - dispatching");
            let resp, events = dispatch_request req.id r in
            log (fun () -> "Dispatch completed - processing response");
            begin match resp with
            | Error {code; message} ->
              log (fun () -> "Request failed with error: " ^ message);
              (* Simplified error handling for EasyCrypt *)
              let error_msg = Printf.sprintf "Request failed: %s" message in
              log (fun () -> error_msg);
              output_json @@ `Assoc [("jsonrpc", `String "2.0"); ("id", `Null); ("error", `Assoc [("code", `Int (-32603)); ("message", `String message)])]
            | Ok resp ->
              log (fun () -> "Request succeeded - sending response");
              let resp = Request.Client.yojson_of_result r resp in
              log (fun () -> "Response JSON created - calling output_json");
              output_json @@ Jsonrpc.Response.(yojson_of_t @@ ok req.id resp);
              log (fun () -> "Response sent")
            end;
            events
          end
      | Notification notif ->
          log (fun () -> "ui notification");
          begin match Lsp.Client_notification.of_jsonrpc notif with
          | Ok (TextDocumentDidOpen params) -> textDocumentDidOpen params
          | Ok (TextDocumentDidChange params) -> textDocumentDidChange params
          | Ok (TextDocumentDidClose params) -> textDocumentDidClose params
          | Ok (Initialized) -> 
            log (fun () -> "LSP Initialized notification received"); []
          | Ok (Exit) -> 
            log (fun () -> "LSP Exit notification received"); exit 0
          | Ok (_other_notif) -> 
            log (fun () -> "Unsupported notification"); []
          | Error e -> 
            log (fun () -> "Error decoding notification: " ^ e); []
          end
      | Response resp ->
          log (fun () -> "got unknown response");
          []
      | Batch_response _ -> log (fun () -> "Unsupported batch response received"); []
      | Batch_call _ -> log (fun () -> "Unsupported batch call received"); []
      end
    with Ppx_yojson_conv_lib__Yojson_conv.Of_yojson_error(exn,json) ->
      log (fun () -> "error parsing json: " ^ Yojson.Safe.pretty_to_string json);
      []
    end
  | Send jsonrpc ->
    output_json (Jsonrpc.Packet.yojson_of_t jsonrpc); []

let handle_event (event : event) = 
  match event with
  | LspManagerEvent lsp_event -> handle_lsp_event lsp_event
  | DocumentManagerEvent (uri, dm_event) ->
    begin match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path uri) with
    | None ->
      log (fun () -> "ignoring event on non-existing document");
      []
    | Some { st; visible } ->
      let handled_event = Dm.DocumentManager.handle_event dm_event st ~block:false in
      begin match handled_event.state with
        | None -> ()
        | Some st ->
          Hashtbl.replace states (Lsp.Types.DocumentUri.to_path uri) { st; visible };
      end;
      inject_dm_events (uri, handled_event.events)
    end
  | Notification notification ->
    log (fun () -> "Processing notification");
    (* TODO: Add notification output handling *)
    []
  | LogEvent log_event ->
    Dm.Log.handle_event log_event; 
    [inject_debug_event Dm.Log.debug]