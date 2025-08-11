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
  | Lsp of Lsp.Server.t
  | UpdateSettings of Jsonrpc.Structured.t option

type event = lsp_event Sel.event

let pr_event = function
  | Sel.Now Lsp _ -> "Lsp"
  | Sel.Now (UpdateSettings _) -> "UpdateSettings"
  | Sel.Later _ -> "Later"

let init () =
  (* Initialize EasyCrypt state (similar to VSRocq's Vernacstate.freeze_full_state) *)
  let gstate = EcLib.EcGState.create () in
  let scope = EcLib.EcScope.empty gstate in
  init_state := Some scope;
  let lsp = Sel.now @@ Lsp (Lsp.Server.make (Unix.stdin, Unix.stdout) (Lsp.Server.create_stdio_scheduler ())) in
  [lsp]

let handle_event = function
  | Lsp lsp_server -> 
    log (fun () -> "Processing LSP event");
    (* Handle LSP messages using external lsp library *)
    [Sel.now @@ Lsp lsp_server]
  | UpdateSettings config ->
    log (fun () -> "Processing settings update");
    []