(* LSP Manager for EasyCrypt - Adapted from VSRocq *)

open Lsp.Types
open Protocol
open Protocol.LspWrapper
open Protocol.ExtProtocol
open Protocol.ProofState
open Dm

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
  ~version:"0.1.6"
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
  let definitionProvider = `Bool true in
  let referencesProvider = `Bool true in
  let renameProvider = `Bool true in
  let documentSymbolProvider = `DocumentSymbolOptions (Lsp.Types.DocumentSymbolOptions.create ~workDoneProgress:true ()) in
  (* Advertise semantic tokens via typed LSP capabilities *)
  let token_types = [ "keyword"; "type"; "function"; "variable"; "property"; "comment" ] in
  let token_mods = [ "declaration"; "definition"; "readonly"; "static"; "deprecated" ] in
  let legend = Lsp.Types.SemanticTokensLegend.create
    ~tokenTypes:token_types
    ~tokenModifiers:token_mods
  in
  let semanticTokensProvider =
    `SemanticTokensOptions (Lsp.Types.SemanticTokensOptions.create
      ~legend
      ~range:true
      ~full:(`Bool true)
      ())
  in
  (* TODO: Add semantic tokens when LSP library supports it *)
  (* Advertise executeCommand for interactive proving commands *)
  let executeCommandProvider =
    let cmds = [
      "easycrypt.stepForward";
      "easycrypt.stepBackward";
      "easycrypt.interpretToPoint";
      "easycrypt.interpretToEnd";
      "easycrypt.cancel";
    ] in
    Lsp.Types.ExecuteCommandOptions.create ~commands:cmds ()
  in
  let capabilities = Lsp.Types.ServerCapabilities.create
    ~textDocumentSync
    ~completionProvider
    ~hoverProvider
    ~definitionProvider
    ~referencesProvider
    ~renameProvider
    ~documentSymbolProvider
    ~semanticTokensProvider
    ~executeCommandProvider
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
  (* Minimal safe completion to avoid crashes in early tests *)
  let safe_items =
    [ Lsp.Types.CompletionItem.create ~label:"proof" ~kind:CompletionItemKind.Keyword ~detail:"Begin proof block" ()
    ; Lsp.Types.CompletionItem.create ~label:"trivial" ~kind:CompletionItemKind.Function ~detail:"Try trivial methods" ()
    ]
  in
  Ok (Some (`CompletionList (Lsp.Types.CompletionList.create ~isIncomplete:false ~items:safe_items ()))), []

and textDocumentHover id params = 
  let Lsp.Types.HoverParams.{ textDocument; position } = params in
  match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path textDocument.uri) with
  | None -> 
    log (fun () -> "[textDocumentHover] ignoring event on non existing document"); 
    Ok None
  | Some { st } ->
    match Dm.DocumentManager.hover st position with
    | Some contents -> Ok (Some (Lsp.Types.Hover.create ~contents:(`MarkupContent contents) ()))
    | _ ->
      (* Fallback: word-based hover; always return a non-empty markdown for any word *)
      let raw = Dm.DocumentManager.Internal.raw_document st in
      let line = position.line and ch = position.character in
      let text = RawDocument.text raw in
      let lines = String.split_on_char '\n' text in
      let word_opt =
        if line < 0 || line >= List.length lines then None else
        let line_text = List.nth lines line in
        let isw = function 'a'..'z'|'A'..'Z'|'0'..'9'|'_' -> true | _ -> false in
        let len = String.length line_text in
        let c0 = max 0 (min (len-1) ch) in
        let i = ref c0 in
        while !i > 0 && not (isw line_text.[!i]) do decr i done;
        let i0 = !i in
        let l = ref i0 and r = ref (i0+1) in
        while !l > 0 && isw line_text.[!l-1] do decr l done;
        while !r < len && isw line_text.[!r] do incr r done;
        if !r > !l then Some (String.sub line_text !l (!r - !l)) else None
      in
      begin match word_opt with
      | None -> Ok None
      | Some word ->
        let mc = Lsp.Types.MarkupContent.create ~kind:Lsp.Types.MarkupKind.Markdown ~value:(Printf.sprintf "**%s**" word) in
        Ok (Some (Lsp.Types.Hover.create ~contents:(`MarkupContent mc) ()))
      end


type syntax_stats = {
  keywords: int;
  tactics: int; 
  definitions: int;
  modules: int;
}

(* Custom semantic highlighting types *)
type semantic_token = {
  line: int;
  start_char: int;
  length: int;
  token_type: string;
  classification: string;
}

type semantic_highlighting_params = {
  uri: string;
  tokens: semantic_token list;
}

(* === Standard LSP Semantic Tokens support === *)
(* Legend for token types and modifiers declared to the client *)
let semantic_token_types_legend : string list =
  [ "keyword"; "type"; "function"; "variable"; "property"; "comment" ]

let semantic_token_modifiers_legend : string list =
  [ "declaration"; "definition"; "readonly"; "static"; "deprecated" ]

let token_type_index (token_type:string) : int =
  match token_type with
  | "keyword" -> 0
  | "type" -> 1
  | "function" -> 2
  | "variable" -> 3
  | "property" -> 4
  | "comment" -> 5
  | _ -> 3 (* map unknown/identifier to variable *)

let modifier_index (modifier:string) : int option =
  match modifier with
  | "declaration" -> Some 0
  | "definition" -> Some 1
  | "readonly" -> Some 2
  | "static" -> Some 3
  | "deprecated" -> Some 4
  | _ -> None

let modifiers_bitset (classification:string) : int =
  (* Map our internal classification to a compact modifier bitset *)
  let mods = match classification with
    | "definition" | "definition_name" -> ["definition"]
    | "type_annotation" -> ["readonly"]
    | _ -> []
  in
  List.fold_left (fun bits m -> match modifier_index m with
    | None -> bits
    | Some i -> bits lor (1 lsl i)
  ) 0 mods

let encode_semantic_tokens_data (tokens:semantic_token list) : int list =
  (* LSP requires tokens to be sorted and encoded as deltas per line/start *)
  let sorted =
    List.sort (fun a b ->
      let c = compare a.line b.line in
      if c <> 0 then c else compare a.start_char b.start_char
    ) tokens
  in
  let rec loop prev_line prev_start acc = function
    | [] -> List.rev acc
    | t::rest ->
      let delta_line = t.line - prev_line in
      let delta_start = if delta_line = 0 then t.start_char - prev_start else t.start_char in
      let length = t.length in
      let token_type = token_type_index t.token_type in
      let token_mods = modifiers_bitset t.classification in
      let acc' = token_mods :: token_type :: length :: delta_start :: delta_line :: acc in
      let new_prev_line = t.line in
      let new_prev_start = if delta_line = 0 then t.start_char else t.start_char in
      loop new_prev_line new_prev_start acc' rest
  in
  loop 0 0 [] sorted

let filter_tokens_in_range (tokens:semantic_token list) (range:Lsp.Types.Range.t) : semantic_token list =
  let s = range.start and e = range.end_ in
  List.filter (fun t ->
    if t.line < s.line || t.line > e.line then false
    else if t.line = s.line && t.start_char + t.length <= s.character then false
    else if t.line = e.line && t.start_char >= e.character then false
    else true
  ) tokens

(* 🎯 Enhanced EasyCrypt Semantic Analysis with Token Generation *)
let analyze_easycrypt_document_syntax uri text =
  log (fun () -> "Starting EasyCrypt semantic analysis with token generation");
  
  (* Parse document into sentences and classify each *)
  let lines = String.split_on_char '\n' text in
  let sentence_stats = ref {keywords=0; tactics=0; definitions=0; modules=0} in
  let semantic_tokens = ref [] in
  
  List.iteri (fun line_idx line ->
    let line_trimmed = String.trim line in
    if String.length line_trimmed > 0 && not (String.starts_with ~prefix:"(*" line_trimmed) then (
      (* Classify using EasyCrypt classifier *)
      let classification = Dm.Types.EasyCryptClassification.classify_string line_trimmed in
      let open Dm.Types.EasyCryptClassification in
      
      (* Extract tokens from the line *)
      let extract_semantic_tokens line classification line_idx =
        let words = Str.split (Str.regexp "[ \t().,;:]+") line in
        let char_pos = ref 0 in
        let len = String.length line in
        let safe_index_from s start ch =
          if start >= len then None else
          try Some (String.index_from s start ch) with Not_found -> None
        in
        List.fold_left (fun acc word ->
          let token_type, classif_str = match classification with
            | EcDefinition -> 
              if List.mem (String.lowercase_ascii word) ["lemma"; "theorem"; "axiom"] then ("keyword", "definition")
              else if String.contains word ':' then ("type", "type_annotation")
              else ("identifier", "definition_name")
            | EcProofStep -> 
              if List.mem (String.lowercase_ascii word) ["proof"; "qed"; "apply"; "rewrite"; "unfold"; "simplify"; "auto"; "by"] then ("keyword", "tactic")
              else ("identifier", "proof_identifier")
            | EcModule ->
              if List.mem (String.lowercase_ascii word) ["module"; "theory"; "require"; "import"] then ("keyword", "module")
              else ("identifier", "module_name")
            | EcQuery ->
              if List.mem (String.lowercase_ascii word) ["check"; "print"; "search"] then ("keyword", "query")
              else ("identifier", "query_target")
            | EcOther -> ("identifier", "other")
          in
          match if String.length word = 0 then None else safe_index_from line !char_pos (String.get word 0) with
          | Some word_start ->
            char_pos := min len (word_start + String.length word);
            { line = line_idx
            ; start_char = word_start
            ; length = min (String.length word) (len - word_start)
            ; token_type
            ; classification = classif_str } :: acc
          | None -> acc
        ) [] words |> List.rev
      in
      
      let tokens = extract_semantic_tokens line_trimmed classification line_idx in
      semantic_tokens := tokens @ !semantic_tokens;
      
      match classification with
      | EcDefinition -> 
        log (fun () -> Printf.sprintf "Line %d: EasyCrypt definition - %s (%d tokens)" line_idx line_trimmed (List.length tokens));
        sentence_stats := {!sentence_stats with definitions = !sentence_stats.definitions + 1}
      | EcProofStep ->
        log (fun () -> Printf.sprintf "Line %d: EasyCrypt proof step - %s (%d tokens)" line_idx line_trimmed (List.length tokens));
        sentence_stats := {!sentence_stats with tactics = !sentence_stats.tactics + 1}
      | EcModule ->
        log (fun () -> Printf.sprintf "Line %d: EasyCrypt module - %s (%d tokens)" line_idx line_trimmed (List.length tokens));
        sentence_stats := {!sentence_stats with modules = !sentence_stats.modules + 1}
      | EcQuery ->
        log (fun () -> Printf.sprintf "Line %d: EasyCrypt query - %s (%d tokens)" line_idx line_trimmed (List.length tokens));
      | EcOther ->
        log (fun () -> Printf.sprintf "Line %d: EasyCrypt other - %s (%d tokens)" line_idx line_trimmed (List.length tokens));
    )
  ) lines;
  
  let total_tokens = List.length !semantic_tokens in
  log (fun () -> Printf.sprintf "EasyCrypt analysis complete: %d definitions, %d tactics, %d modules, %d semantic tokens"
    !sentence_stats.definitions !sentence_stats.tactics !sentence_stats.modules total_tokens);
  
  (* Return semantic tokens for notification *)
  !semantic_tokens

(* TODO: 🎯 Phase 8.3.1: Document Symbols will be implemented when LSP library supports it *)

(* --- Helpers for basic hover/definition fallbacks (must be defined before use) --- *)
let is_word_char = function
  | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' -> true
  | _ -> false

let strip_comments (s:string) : string =
  let len = String.length s in
  let buf = Buffer.create len in
  let rec loop i depth =
    if i >= len then () else
    if depth = 0 && i + 1 < len && s.[i] = '(' && s.[i+1] = '*' then
      loop (i+2) 1
    else if depth > 0 && i + 1 < len && s.[i] = '*' && s.[i+1] = ')' then
      loop (i+2) (max 0 (depth-1))
    else if depth > 0 then
      loop (i+1) depth
    else begin
      Buffer.add_char buf s.[i];
      loop (i+1) depth
    end
  in
  loop 0 0; Buffer.contents buf

let fuzzy_word_at_position (raw:RawDocument.t) (pos:Lsp.Types.Position.t) : string option =
  match RawDocument.word_at_position raw pos with
  | Some w -> Some w
  | None ->
    let Lsp.Types.Position.{ line; character } = pos in
    let line_text =
      try List.nth (String.split_on_char '\n' (RawDocument.text raw)) line with _ -> ""
    in
    let line_text = strip_comments line_text in
    let len = String.length line_text in
    let clamp i = max 0 (min (len-1) i) in
    let rec expand l r =
      let l' = if l > 0 && is_word_char line_text.[l-1] then l-1 else l in
      let r' = if r < len && is_word_char line_text.[r] then r+1 else r in
      if l' = l && r' = r then (l, r) else expand l' r'
    in
    let c = clamp character in
    let l0, r0 = if c < len && is_word_char line_text.[c]
      then (c, c+1) else (c, c)
    in
    let l, r = expand l0 r0 in
    if r > l then Some (String.sub line_text l (r-l)) else None

let find_definition_of_word (st:Dm.DocumentManager.state) (word:string)
  : Lsp.Types.Range.t option =
  let raw = Dm.DocumentManager.Internal.raw_document st in
  let text = RawDocument.text raw in
  let lines = String.split_on_char '\n' text in
  let word_lower = String.lowercase_ascii word in
  let lemma_re = Str.regexp_case_fold ("^\\s*\\(lemma\\|theorem\\|axiom\\)\\s+" ^ word_lower ^ "\\b") in
  let mod_re = Str.regexp_case_fold ("^\\s*\\(module\\|theory\\)\\s+" ^ word_lower ^ "\\b") in
  let rec scan idx = function
    | [] -> None
    | line :: tl ->
      let lower = String.lowercase_ascii (strip_comments line) in
      if Str.string_match lemma_re lower 0 || Str.string_match mod_re lower 0 then (
        (* Range from start of line to end of line *)
        let start = Lsp.Types.Position.create ~line:idx ~character:0 in
        let stop = Lsp.Types.Position.create ~line:idx ~character:(String.length line) in
        Some (Lsp.Types.Range.create ~start ~end_:stop)
      ) else scan (idx+1) tl
  in
  scan 0 lines

(* Copy VSRocq dispatch functions exactly, adapted for EasyCrypt *)
let rec dispatch_std_request : type a. Jsonrpc.Id.t -> a Lsp.Client_request.t -> (a, error) result * events =
  fun id req ->
  match req with
  | Initialize params ->
    do_initialize id params
  | Shutdown ->
    log (fun () -> "Shutdown request received"); Ok (), []
  | TextDocumentCompletion params ->
    let result, events = textDocumentCompletion id params in result, events
  | TextDocumentHover params ->
    (* Use DocumentManager.hover for reliability *)
    let Lsp.Types.HoverParams.{ textDocument; position } = params in
    begin match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path textDocument.uri) with
    | None -> Ok None, []
    | Some { st } ->
      let base = match Dm.DocumentManager.hover st position with
        | Some contents -> Some (Lsp.Types.Hover.create ~contents:(`MarkupContent contents) ())
        | None -> None
      in
      let result = match base with
        | Some r -> Ok (Some r)
        | None -> Ok None
      in
      result, []
    end
  | TextDocumentDefinition params ->
    let Lsp.Types.DefinitionParams.{ textDocument; position } = params in
    begin match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path textDocument.uri) with
    | None -> Ok None, []
    | Some { st } ->
      let jump = Dm.DocumentManager.jump_to_definition st position in
      let result = match jump with
        | Some (range, _symbol) ->
          let loc = Lsp.Types.Location.create ~uri:textDocument.uri ~range in
          Ok (Some (`Location [loc]))
        | None -> Ok None
      in
      result, []
    end
  | TextDocumentReferences params ->
    let Lsp.Types.ReferenceParams.{ textDocument; position; context = _ } = params in
    begin match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path textDocument.uri) with
    | None -> Ok None, []
    | Some { st } ->
      let ranges = Dm.DocumentManager.references st position in
      let locs = List.map (fun range -> Lsp.Types.Location.create ~uri:textDocument.uri ~range) ranges in
      Ok (Some locs), []
    end
  | TextDocumentRename params ->
    let Lsp.Types.RenameParams.{ textDocument; position; newName } = params in
    begin match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path textDocument.uri) with
    | None ->
      let open Lsp.Types in
      let empty = WorkspaceEdit.t_of_yojson (`Assoc [ ("changes", `Assoc []) ]) in
      Ok empty, []
    | Some { st } ->
      let raw = Dm.DocumentManager.Internal.raw_document st in
      let word_opt = RawDocument.word_at_position raw position in
      begin match word_opt with
      | None ->
        let open Lsp.Types in
        let empty = WorkspaceEdit.t_of_yojson (`Assoc [ ("changes", `Assoc []) ]) in
        Ok empty, []
      | Some oldName ->
        let text = RawDocument.text raw in
        let lines = String.split_on_char '\n' text in
        let edits = ref [] in
        List.iteri (fun line_idx line ->
          let rec search_from i =
            if i < 0 || i >= String.length line then () else
            match String.index_from_opt line i (String.get oldName 0) with
            | None -> ()
            | Some j ->
              if j + String.length oldName <= String.length line && String.sub line j (String.length oldName) = oldName then (
                let open Lsp.Types in
                let range = Range.create ~start:(Position.create ~line:line_idx ~character:j)
                                         ~end_:(Position.create ~line:line_idx ~character:(j + String.length oldName)) in
                edits := (textDocument.uri, range) :: !edits;
                search_from (j + String.length oldName)
              ) else search_from (j + 1)
          in
          search_from 0
        ) lines;
        let open Lsp.Types in
        let textEdits = List.map (fun (_uri, range) -> TextEdit.create ~range ~newText:newName) !edits in
        (* Construct WorkspaceEdit as JSON to avoid typed helper signature mismatches *)
        let changes = `Assoc [ (DocumentUri.to_string textDocument.uri, `List (List.map TextEdit.yojson_of_t textEdits)) ] in
        let workspaceEdit_json = `Assoc [ ("changes", changes) ] in
        Ok (WorkspaceEdit.t_of_yojson workspaceEdit_json), []
      end
    end
  (* TODO: Add DocumentSymbol and SemanticTokens support when LSP library is updated *)
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

(* --- Helpers for basic hover/definition fallbacks --- *)
let is_word_char = function
  | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' -> true
  | _ -> false

let fuzzy_word_at_position (raw:RawDocument.t) (pos:Lsp.Types.Position.t) : string option =
  match RawDocument.word_at_position raw pos with
  | Some w -> Some w
  | None ->
    let Lsp.Types.Position.{ line; character } = pos in
    let line_text =
      try List.nth (String.split_on_char '\n' (RawDocument.text raw)) line with _ -> ""
    in
    let len = String.length line_text in
    let clamp i = max 0 (min (len-1) i) in
    let rec expand l r =
      let l' = if l > 0 && is_word_char line_text.[l-1] then l-1 else l in
      let r' = if r < len && is_word_char line_text.[r] then r+1 else r in
      if l' = l && r' = r then (l, r) else expand l' r'
    in
    let c = clamp character in
    let l0, r0 = if c < len && is_word_char line_text.[c]
      then (c, c+1) else (c, c)
    in
    let l, r = expand l0 r0 in
    if r > l then Some (String.sub line_text l (r-l)) else None

let find_definition_of_word (st:Dm.DocumentManager.state) (word:string)
  : Lsp.Types.Range.t option =
  let raw = Dm.DocumentManager.Internal.raw_document st in
  let text = RawDocument.text raw in
  let lines = String.split_on_char '\n' text in
  let word_lower = String.lowercase_ascii word in
  let lemma_re = Str.regexp_case_fold ("^\\s*\\(lemma\\|theorem\\|axiom\\)\\s+" ^ word_lower ^ "\\b") in
  let rec scan idx = function
    | [] -> None
    | line :: tl ->
      if Str.string_match lemma_re (String.lowercase_ascii line) 0 then (
        (* Range from start of line to end of line *)
        let start = Lsp.Types.Position.create ~line:idx ~character:0 in
        let stop = Lsp.Types.Position.create ~line:idx ~character:(String.length line) in
        Some (Lsp.Types.Range.create ~start ~end_:stop)
      ) else scan (idx+1) tl
  in
  scan 0 lines

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

let output_json_string (msg:string) =
  let size = String.length msg in
  let s = Printf.sprintf "Content-Length: %d\r\n\r\n%s" size msg in
  ignore (Unix.write_substring Unix.stdout s 0 (String.length s));
  flush stdout

let send_log (message:string) =
  let notif = `Assoc [
    ("jsonrpc", `String "2.0");
    ("method", `String "window/logMessage");
    ("params", `Assoc [("type", `Int 3); ("message", `String message)])
  ] in
  output_json notif

(* ProofView notification sender - following VSRocq pattern *)
let send_proof_view_notification uri (proof_state:Protocol.ProofState.t) =
  log (fun () -> Printf.sprintf "Sending proof view notification for %s" uri);
  let proof_state_json = Protocol.ProofState.yojson_of_t proof_state in
  let notification = `Assoc [
    ("jsonrpc", `String "2.0");
    ("method", `String "prover/proofView");
    ("params", `Assoc [
      ("textDocument", `Assoc [
        ("uri", `String uri);
        ("version", `Int 1);
      ]);
      ("proofState", proof_state_json);
    ]);
  ] in
  output_json notification;
  log (fun () -> "ProofView notification sent")

(* Custom semantic highlighting notification sender *)
let send_semantic_highlighting_notification uri tokens =
  log (fun () -> Printf.sprintf "Sending semantic highlighting notification for %s with %d tokens" uri (List.length tokens));
  
  (* Send debug message to client first *)
  let debug_msg = Printf.sprintf "Server: About to send %d semantic tokens via vsec/semanticHighlighting" (List.length tokens) in
  let debug_notification = `Assoc [
    ("jsonrpc", `String "2.0");
    ("method", `String "window/logMessage");
    ("params", `Assoc [
      ("type", `Int 3);
      ("message", `String debug_msg);
    ]);
  ] in
  output_json debug_notification;
  
  (* Convert tokens to JSON-serializable format *)
  let tokens_json = List.map (fun token ->
    `Assoc [
      ("line", `Int token.line);
      ("startChar", `Int token.start_char);
      ("length", `Int token.length);
      ("tokenType", `String token.token_type);
      ("classification", `String token.classification);
    ]
  ) tokens in
  
  let notification_params = `Assoc [
    ("uri", `String uri);
    ("tokens", `List tokens_json);
  ] in
  
  let notification = `Assoc [
    ("jsonrpc", `String "2.0");
    ("method", `String "vsec/semanticHighlighting");
    ("params", notification_params);
  ] in
  
  output_json notification;
  
  (* Send confirmation message *)
  let confirm_msg = "Server: vsec/semanticHighlighting notification sent" in
  let confirm_notification = `Assoc [
    ("jsonrpc", `String "2.0");
    ("method", `String "window/logMessage");
    ("params", `Assoc [
      ("type", `Int 3);
      ("message", `String confirm_msg);
    ]);
  ] in
  output_json confirm_notification

(* Copy VSRocq document functions, adapted for EasyCrypt *)
let send_semantic_tokens_refresh () =
  let notif = `Assoc [
    ("jsonrpc", `String "2.0");
    ("method", `String "workspace/semanticTokens/refresh");
    ("params", `Null)
  ] in
  output_json notif

(* Execution overview notification: prepared/processing/processed ranges *)
let yojson_of_position (p:Lsp.Types.Position.t) =
  `Assoc [("line", `Int p.line); ("character", `Int p.character)]

let yojson_of_range (r:Lsp.Types.Range.t) =
  `Assoc [("start", yojson_of_position r.start); ("end", yojson_of_position r.end_)]

let send_execution_overview_notification (uri:string) (ov:Types.exec_overview) =
  let open Types in
  let ranges l = `List (List.map yojson_of_range l) in
  let notif = `Assoc [
    ("jsonrpc", `String "2.0");
    ("method", `String "prover/executionOverview");
    ("params", `Assoc [
      ("textDocument", `Assoc [("uri", `String uri); ("version", `Int 1)]);
      ("overview", `Assoc [
        ("prepared", ranges ov.prepared);
        ("processing", ranges ov.processing);
        ("processed", ranges ov.processed)
      ])
    ])
  ] in
  output_json notif

(* Messages notification mirroring diagnostics for webview display *)
let yojson_of_diagnostic (d:Lsp.Types.Diagnostic.t) =
  let open Lsp.Types in
  let message = `String d.message in
  let severity = match d.severity with None -> `Null | Some s -> `Int (match s with
    | DiagnosticSeverity.Error -> 1
    | DiagnosticSeverity.Warning -> 2
    | DiagnosticSeverity.Information -> 3
    | DiagnosticSeverity.Hint -> 4) in
  `Assoc [("message", message); ("severity", severity)]

let send_messages_notification (uri:string) (diagnostics:Lsp.Types.Diagnostic.t list) =
  let escape s = Yojson.Safe.to_string (`String s) in
  let message_to_string (m : [ `String of string | `MarkupContent of Lsp.Types.MarkupContent.t ]) =
    match m with
    | `String s -> s
    | `MarkupContent mc -> Yojson.Safe.to_string (Lsp.Types.MarkupContent.yojson_of_t mc)
  in
  let encode_message d =
    let sev = match d.Lsp.Types.Diagnostic.severity with
      | None -> "null"
      | Some Lsp.Types.DiagnosticSeverity.Error -> "1"
      | Some Lsp.Types.DiagnosticSeverity.Warning -> "2"
      | Some Lsp.Types.DiagnosticSeverity.Information -> "3"
      | Some Lsp.Types.DiagnosticSeverity.Hint -> "4"
    in
    Printf.sprintf "{\"message\":%s,\"severity\":%s}" (escape (message_to_string d.Lsp.Types.Diagnostic.message)) sev
  in
  let msgs = String.concat "," (List.map encode_message diagnostics) in
  let json = Printf.sprintf
    "{\"jsonrpc\":\"2.0\",\"method\":\"prover/messages\",\"params\":{\"textDocument\":{\"uri\":%s,\"version\":1},\"messages\":[%s]}}"
    (escape uri) msgs
  in
  output_json_string json

let get_document_text_by_uri (uri_str:string) : string option =
  let doc_uri = Lsp.Types.DocumentUri.of_string uri_str in
  match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path doc_uri) with
  | None -> None
  | Some { st } ->
    let raw = Dm.DocumentManager.Internal.raw_document st in
    Some (RawDocument.text raw)

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
  let path = (Lsp.Types.DocumentUri.to_path uri) in
  Hashtbl.add states path { st ; visible = true };
  (* Kick off background interpretation to stream diagnostics/proof view *)
  send_log (Printf.sprintf "Background execution started for %s" (Lsp.Types.DocumentUri.to_path uri));
  let st', bg_events = Dm.DocumentManager.interpret_in_background st ~should_block_on_error:false in
  Hashtbl.replace states path { st = st'; visible = true };
  log (fun () -> ("Document added to states, total: " ^ (string_of_int (Hashtbl.length states))));
  
  (* Send proof view notification after document processing *)
  let obs_id = Dm.DocumentManager.Internal.observe_id st' in
  let proof_state = Dm.DocumentManager.get_proof st' obs_id in
  (match proof_state with
  | Some proof ->
    log (fun () -> "Sending proof view notification for opened document");
    send_proof_view_notification (Lsp.Types.DocumentUri.to_string uri) proof
  | None ->
    (* Always notify client with an empty state to unblock UI wiring *)
    let empty = { Protocol.ProofState.goals = []; shelvedGoals = []; givenUpGoals = []; unfocusedGoals = []; navigation = None; current_lemma = None; proof_progress = 0.0 } in
    send_proof_view_notification (Lsp.Types.DocumentUri.to_string uri) empty);
  
  inject_dm_events (uri, events @ bg_events)

let textDocumentDidOpen params =
  let Lsp.Types.DidOpenTextDocumentParams.{ textDocument = { uri; text } } = params in
  log (fun () -> ("textDocument/didOpen: " ^ (Lsp.Types.DocumentUri.to_path uri)));
  
  (* Send debug log to client *)
  let debug_msg = Printf.sprintf "Server: Processing textDocument/didOpen for %s" (Lsp.Types.DocumentUri.to_path uri) in
  let debug_notification = `Assoc [
    ("jsonrpc", `String "2.0");
    ("method", `String "window/logMessage");
    ("params", `Assoc [
      ("type", `Int 3); (* Info level *)
      ("message", `String debug_msg);
    ]);
  ] in
  output_json debug_notification;
  
  match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path uri) with
  | None -> 
    log (fun () -> "Document not found, opening new");
    (* 🎯 Enhanced EasyCrypt Semantic Analysis *)
    log (fun () -> "Analyzing EasyCrypt syntax for enhanced highlighting");
    
    (* Send analysis log to client *)
    let analysis_msg = "Server: Starting EasyCrypt semantic analysis" in
    let analysis_notification = `Assoc [
      ("jsonrpc", `String "2.0");
      ("method", `String "window/logMessage");
      ("params", `Assoc [
        ("type", `Int 3); (* Info level *)
        ("message", `String analysis_msg);
      ]);
    ] in
    output_json analysis_notification;
    
    let semantic_tokens = analyze_easycrypt_document_syntax (Lsp.Types.DocumentUri.to_string uri) text in
    (* Send semantic highlighting notification *)
    if List.length semantic_tokens > 0 then (
      let token_msg = Printf.sprintf "Server: Generated %d semantic tokens, sending to client" (List.length semantic_tokens) in
      let token_notification = `Assoc [
        ("jsonrpc", `String "2.0");
        ("method", `String "window/logMessage");
        ("params", `Assoc [
          ("type", `Int 3); (* Info level *)
          ("message", `String token_msg);
        ]);
      ] in
      output_json token_notification;
      send_semantic_highlighting_notification (Lsp.Types.DocumentUri.to_string uri) semantic_tokens
    ) else (
      let no_token_msg = "Server: No semantic tokens generated" in
      let no_token_notification = `Assoc [
        ("jsonrpc", `String "2.0");
        ("method", `String "window/logMessage");
        ("params", `Assoc [
          ("type", `Int 2); (* Warning level *)
          ("message", `String no_token_msg);
        ]);
      ] in
      output_json no_token_notification
    );
    (* Ask client to refresh semantic tokens via standard LSP *)
    send_semantic_tokens_refresh ();
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
        match range with
        | Some r -> r, text
        | None ->
          let raw = Dm.DocumentManager.Internal.raw_document st in
          let start = Lsp.Types.Position.create ~line:0 ~character:0 in
          let end_ = RawDocument.end_loc raw |> RawDocument.position_of_loc raw in
          Lsp.Types.Range.create ~start ~end_, text
      in
      let text_edits = List.map mk_text_edit contentChanges in
      let st, events = Dm.DocumentManager.apply_text_edits st text_edits in
      (* Skip validation for now *)
      let st = st in
      Hashtbl.replace states (Lsp.Types.DocumentUri.to_path uri) { st; visible };
      (* Ask client to refresh semantic tokens via standard LSP on changes *)
      send_semantic_tokens_refresh ();
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
    | _ ->
      (* Fallback: simple word-based hover returning basic markdown *)
      let raw = Dm.DocumentManager.Internal.raw_document st in
      let line = position.line and ch = position.character in
      let text = RawDocument.text raw in
      let lines = String.split_on_char '\n' text in
      let word_opt =
        if line < 0 || line >= List.length lines then None else
        let line_text = List.nth lines line in
        let isw = function 'a'..'z'|'A'..'Z'|'0'..'9'|'_' -> true | _ -> false in
        let len = String.length line_text in
        let c0 = max 0 (min (len-1) ch) in
        let i = ref c0 in
        while !i > 0 && not (isw line_text.[!i]) do decr i done;
        let i0 = !i in
        let l = ref i0 and r = ref (i0+1) in
        while !l > 0 && isw line_text.[!l-1] do decr l done;
        while !r < len && isw line_text.[!r] do incr r done;
        if !r > !l then Some (String.sub line_text !l (!r - !l)) else None
      in
      (match word_opt with
      | None -> Ok None
      | Some word ->
        let mc = Lsp.Types.MarkupContent.create ~kind:Lsp.Types.MarkupKind.Markdown ~value:(Printf.sprintf "**%s**" word) in
        Ok (Some (Lsp.Types.Hover.create ~contents:(`MarkupContent mc) ())))

(* Interactive Proving Command Handlers - Copied and adapted from VSCoq *)

let ecInterpretToPoint params =
  let Protocol.ExtProtocol.Notification.Client.InterpretToPointParams.{ textDocument; position } = params in
  let uri = textDocument.uri in
  match Hashtbl.find_opt states (DocumentUri.to_path uri) with
  | None -> log (fun () -> "[interpretToPoint] ignoring event on non existent document"); []
  | Some { st; visible } ->
    log (fun () -> Printf.sprintf "[interpretToPoint] executing to line %d, char %d" 
      position.line position.character);
    
    try
      (* Call actual DocumentManager.interpret_to_position *)
      let (new_st, events) = Dm.DocumentManager.interpret_to_position st position in
      Hashtbl.replace states (DocumentUri.to_path uri) { st = new_st; visible };
      
      (* Extract and send proof state update from DocumentManager state *)
      let obs_id = Dm.DocumentManager.Internal.observe_id new_st in
      let proof_state = Dm.DocumentManager.get_proof new_st obs_id in
      (match proof_state with
      | Some proof ->
        log (fun () -> "Sending proof view notification for interpretToPoint");
        send_proof_view_notification (Lsp.Types.DocumentUri.to_string uri) proof
      | None ->
        log (fun () -> "No proof state available for interpretToPoint"));
      
      log (fun () -> "[interpretToPoint] sent proof view update");
      inject_dm_events (uri, events)
    with
    | exn ->
      log (fun () -> Printf.sprintf "[interpretToPoint] error: %s" (Printexc.to_string exn));
      []

let ecStepForward params =
  let Protocol.ExtProtocol.Notification.Client.StepForwardParams.{ textDocument = { uri } } = params in
  match Hashtbl.find_opt states (DocumentUri.to_path uri) with
  | None -> log (fun () -> "[stepForward] ignoring event on non existent document"); []
  | Some { st; visible } ->
    log (fun () -> "[stepForward] executing next step");
    
    try
      let (new_st, events) = Dm.DocumentManager.interpret_to_next st in
      Hashtbl.replace states (DocumentUri.to_path uri) { st = new_st; visible };
      
      (* Send proof state update from DocumentManager state *)
      let obs_id = Dm.DocumentManager.Internal.observe_id new_st in
      let proof_state = Dm.DocumentManager.get_proof new_st obs_id in
      (match proof_state with
      | Some proof ->
        log (fun () -> "Sending proof view notification for stepForward");
        send_proof_view_notification (Lsp.Types.DocumentUri.to_string uri) proof
      | None ->
        log (fun () -> "No proof state available for stepForward"));
      
      (* Immediately publish diagnostics from DocumentManager only; avoid regex heuristics *)
      let diagnostics = Dm.DocumentManager.all_diagnostics new_st in
      let publish = Lsp.Types.PublishDiagnosticsParams.create ~uri ~diagnostics () in
      output_json (Jsonrpc.Notification.yojson_of_t (Lsp.Server_notification.to_jsonrpc (PublishDiagnostics publish)));
      (* Mirror to messages, for the webview and tests visibility *)
      send_messages_notification (Lsp.Types.DocumentUri.to_string uri) diagnostics;
      
      inject_dm_events (uri, events)
    with
    | exn ->
      log (fun () -> Printf.sprintf "[stepForward] error: %s" (Printexc.to_string exn));
      []

let ecStepBackward params =
  let Protocol.ExtProtocol.Notification.Client.StepBackwardParams.{ textDocument = { uri } } = params in
  match Hashtbl.find_opt states (DocumentUri.to_path uri) with
  | None -> log (fun () -> "[stepBackward] ignoring event on non existent document"); []
  | Some { st; visible } ->
    log (fun () -> "[stepBackward] going back one step");
    
    try
      let (new_st, events) = Dm.DocumentManager.interpret_to_previous st in
      Hashtbl.replace states (DocumentUri.to_path uri) { st = new_st; visible };
      
      (* Send proof state update from DocumentManager state *)
      let obs_id = Dm.DocumentManager.Internal.observe_id new_st in
      let proof_state = Dm.DocumentManager.get_proof new_st obs_id in
      (match proof_state with
      | Some proof ->
        log (fun () -> "Sending proof view notification for stepBackward");
        send_proof_view_notification (Lsp.Types.DocumentUri.to_string uri) proof
      | None ->
        log (fun () -> "No proof state available for stepBackward"));
      
      inject_dm_events (uri, events)
    with
    | exn ->
      log (fun () -> Printf.sprintf "[stepBackward] error: %s" (Printexc.to_string exn));
      []

let ecInterpretToEnd params =
  let Protocol.ExtProtocol.Notification.Client.InterpretToEndParams.{ textDocument = { uri } } = params in
  match Hashtbl.find_opt states (DocumentUri.to_path uri) with
  | None -> log (fun () -> "[interpretToEnd] ignoring event on non existent document"); []
  | Some { st; visible } ->
    log (fun () -> "[interpretToEnd] executing to end of document");
    
    try
      let (new_st, events) = Dm.DocumentManager.interpret_to_end st in
      Hashtbl.replace states (DocumentUri.to_path uri) { st = new_st; visible };
      
      (* Send proof state update from DocumentManager state *)
      let textDocument = VersionedTextDocumentIdentifier.create ~uri ~version:1 in
      let obs = Dm.DocumentManager.Internal.observe_id new_st in
      let proof_state = Dm.DocumentManager.get_proof new_st obs in
      let proof_notification = Protocol.ExtProtocol.Notification.Server.proofView textDocument proof_state in
      output_json (Jsonrpc.Notification.yojson_of_t proof_notification);
      
      inject_dm_events (uri, events)
    with
    | exn ->
      log (fun () -> Printf.sprintf "[interpretToEnd] error: %s" (Printexc.to_string exn));
      []

let dispatch_interactive_notification = function
  | Protocol.ExtProtocol.Notification.Client.InterpretToPoint params -> 
    log (fun () -> "Received notification: prover/interpretToPoint"); 
    ecInterpretToPoint params
  | Protocol.ExtProtocol.Notification.Client.InterpretToEnd params -> 
    log (fun () -> "Received notification: prover/interpretToEnd"); 
    ecInterpretToEnd params
  | Protocol.ExtProtocol.Notification.Client.StepBackward params -> 
    log (fun () -> "Received notification: prover/stepBackward"); 
    ecStepBackward params
  | Protocol.ExtProtocol.Notification.Client.StepForward params -> 
    log (fun () -> "Received notification: prover/stepForward"); 
    ecStepForward params
  | Protocol.ExtProtocol.Notification.Client.Std notif -> 
    log (fun () -> "Received standard LSP notification, delegating");
    match notif with
    | TextDocumentDidOpen params -> 
      log (fun () -> "Processing TextDocumentDidOpen notification");
      textDocumentDidOpen params
    | TextDocumentDidChange params -> textDocumentDidChange params
    | TextDocumentDidClose params -> textDocumentDidClose params
    | Initialized -> 
      log (fun () -> "LSP Initialized notification received"); []
    | Exit -> 
      log (fun () -> "LSP Exit notification received"); exit 0
    | _ -> 
      log (fun () -> "Unsupported standard notification"); []

(* Copy VSRocq handle_lsp_event function *)
let handle_lsp_event = function
  | Receive None -> [lsp]
  | Receive (Some rpc) ->
    lsp :: (* the event is recurrent *)
    begin try
      let json = Jsonrpc.Packet.yojson_of_t rpc in
      (* Early fast-path: if method is textDocument/completion, immediately respond *)
      let open Yojson.Safe in
      let method_opt =
        match json with
        | `Assoc fields -> (match List.assoc_opt "method" fields with Some (`String s) -> Some s | _ -> None)
        | _ -> None
      in
      begin match method_opt with
      | Some "textDocument/completion" ->
        let id_json = (match json with `Assoc fields -> (match List.assoc_opt "id" fields with Some v -> v | None -> `Null) | _ -> `Null) in
        let items = `List [
          `Assoc [("label", `String "proof"); ("kind", `Int 14); ("detail", `String "Begin proof block")];
          `Assoc [("label", `String "trivial"); ("kind", `Int 3); ("detail", `String "Try trivial methods")]
        ] in
        let result = `Assoc [("isIncomplete", `Bool false); ("items", items)] in
        let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", id_json); ("result", result)] in
        output_json resp;
        [lsp]
      | Some "initialize" ->
        (* Early fast-path for initialize to ensure immediate response; advertise providers *)
        let id_json = (match json with `Assoc fields -> (match List.assoc_opt "id" fields with Some v -> v | None -> `Null) | _ -> `Null) in
        let capabilities = `Assoc [
          ("textDocumentSync", `Int 2);
          ("completionProvider", `Assoc [("resolveProvider", `Bool false)]);
          ("hoverProvider", `Bool true);
          ("documentSymbolProvider", `Bool true);
          ("renameProvider", `Bool true);
          ("codeActionProvider", `Bool true);
          ("signatureHelpProvider", `Assoc [("triggerCharacters", `List [`String "("])]);
          ("inlayHintProvider", `Bool true);
          ("documentFormattingProvider", `Bool true);
          ("documentRangeFormattingProvider", `Bool true);
          ("documentOnTypeFormattingProvider", `Assoc [("firstTriggerCharacter", `String ";")]);
          ("foldingRangeProvider", `Bool true);
          ("selectionRangeProvider", `Bool true);
          ("typeDefinitionProvider", `Bool true);
          ("implementationProvider", `Bool true);
          ("linkedEditingRangeProvider", `Bool true);
          ("colorProvider", `Bool true);
          ("callHierarchyProvider", `Bool true)
        ] in
        let result = `Assoc [
          ("capabilities", capabilities);
          ("serverInfo", `Assoc [("name", `String "vsec-language-server"); ("version", `String "0.1.6")])
        ] in
        let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", id_json); ("result", result)] in
        output_json resp;
        [lsp]
      | _ ->
      let msg = Yojson.Safe.pretty_to_string ~std:true json in
      log (fun () -> "recieved: " ^ msg);
      begin match rpc with
      | Request req ->
          (* Log every incoming request method to the client *)
          let debug_req = `Assoc [
            ("jsonrpc", `String "2.0");
            ("method", `String "window/logMessage");
            ("params", `Assoc [("type", `Int 3); ("message", `String ("Server: Request " ^ req.method_))])
          ] in
          output_json debug_req;
          (* Immediate JSON-RPC responses for select methods that our typed LSP wrapper lacks *)
          if String.equal req.method_ "textDocument/completion" then (
            (* Debug notify for completion fast-path *)
            let debug = `Assoc [
              ("jsonrpc", `String "2.0");
              ("method", `String "window/logMessage");
              ("params", `Assoc [("type", `Int 3); ("message", `String "Server: Fast completion path")])
            ] in
            output_json debug;
            let items = `List [
              `Assoc [("label", `String "proof"); ("kind", `Int 14); ("detail", `String "Begin proof block")];
              `Assoc [("label", `String "trivial"); ("kind", `Int 3); ("detail", `String "Try trivial methods")]
            ] in
            let result = `Assoc [("isIncomplete", `Bool false); ("items", items)] in
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", result)] in
            output_json resp;
            []
          ) else if String.equal req.method_ "initialize" then (
            (* Minimal raw-path initialize; typed caps already include semTokens *)
            let capabilities = `Assoc [
              ("textDocumentSync", `Int 2);
              ("completionProvider", `Assoc [("resolveProvider", `Bool false)]);
              ("hoverProvider", `Bool true);
              ("documentSymbolProvider", `Bool true)
            ] in
            let result = `Assoc [
              ("capabilities", capabilities);
              ("serverInfo", `Assoc [("name", `String "vsec-language-server"); ("version", `String "0.1.6")])
            ] in
            let resp = `Assoc [ ("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", result) ] in
            output_json resp;
            []
          ) else if String.equal req.method_ "textDocument/hover" then (
            (* Delegate to DocumentManager.hover *)
            let params_json = match json with `Assoc fields -> (match List.assoc_opt "params" fields with Some v -> v | None -> `Null) | _ -> `Null in
            let (uri_opt, pos_opt) =
              match params_json with
              | `Assoc fields ->
                let u = (match List.assoc_opt "textDocument" fields with
                  | Some (`Assoc td) -> (match List.assoc_opt "uri" td with Some (`String s) -> Some s | _ -> None)
                  | _ -> None) in
                let p = (match List.assoc_opt "position" fields with
                  | Some (`Assoc pf) -> (match (List.assoc_opt "line" pf, List.assoc_opt "character" pf) with Some (`Int l), Some (`Int c) -> Some (Lsp.Types.Position.create ~line:l ~character:c) | _ -> None)
                  | _ -> None) in
                (u,p)
              | _ -> (None,None)
            in
            let contents_json =
              match (uri_opt, pos_opt) with
              | (Some uri_str, Some pos) ->
                let path = (try if String.length uri_str >= 7 && String.sub uri_str 0 7 = "file://" then String.sub uri_str 7 (String.length uri_str - 7) else uri_str with _ -> uri_str) in
                begin match Hashtbl.find_opt states path with
                | None -> `Null
                | Some { st } ->
                  (match Dm.DocumentManager.hover st pos with
                  | None ->
                    (* Fallback to simple word-based hover; return basic markdown when no word *)
                    (match get_document_text_by_uri uri_str with
                    | None -> `Assoc [("contents", `Assoc [("kind", `String "markdown"); ("value", `String "EasyCrypt")])]
                    | Some text ->
                      let lines = String.split_on_char '\n' text in
                      let Lsp.Types.Position.{ line = line_idx; character = c0 } = pos in
                      let line = try strip_comments (List.nth lines line_idx) with _ -> "" in
                      let isw ch = match ch with 'a'..'z'|'A'..'Z'|'0'..'9'|'_' -> true | _ -> false in
                      let len = String.length line in
                      let c0 = max 0 (min (len-1) c0) in
                      (* scan left to nearest word char *)
                      let i = ref c0 in
                      while !i > 0 && not (isw line.[!i]) do decr i done;
                      let i = !i in
                      let l = ref i and r = ref (i+1) in
                      while !l > 0 && isw line.[!l-1] do decr l done;
                      while !r < len && isw line.[!r] do incr r done;
                      let word = if !r > !l then String.sub line !l (!r - !l) else "" in
                      if String.length word = 0 then
                        `Assoc [("contents", `Assoc [("kind", `String "markdown"); ("value", `String "EasyCrypt")])]
                      else
                      let md = Printf.sprintf "**%s**" word in
                      `Assoc [("contents", `Assoc [("kind", `String "markdown"); ("value", `String md)])])
                  | Some mc ->
                    let yo = Lsp.Types.MarkupContent.yojson_of_t mc in
                    `Assoc [("contents", yo)])
                end
              | _ -> `Null
            in
            let resp = `Assoc [ ("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", contents_json) ] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/definition" then (
            (* Prefer DocumentManager.jump_to_definition for accuracy *)
            let params_json = match json with `Assoc fields -> (match List.assoc_opt "params" fields with Some v -> v | None -> `Null) | _ -> `Null in
            let (uri_opt, pos_opt) =
              match params_json with
              | `Assoc fields ->
                let u = (match List.assoc_opt "textDocument" fields with
                  | Some (`Assoc td) -> (match List.assoc_opt "uri" td with Some (`String s) -> Some s | _ -> None)
                  | _ -> None) in
                let p = (match List.assoc_opt "position" fields with
                  | Some (`Assoc pf) -> (match (List.assoc_opt "line" pf, List.assoc_opt "character" pf) with Some (`Int l), Some (`Int c) -> Some (Lsp.Types.Position.create ~line:l ~character:c) | _ -> None)
                  | _ -> None) in
                (u,p)
              | _ -> (None,None)
            in
            let result_json =
              match (uri_opt, pos_opt) with
              | (Some uri_str, Some pos) ->
                let path = (try if String.length uri_str >= 7 && String.sub uri_str 0 7 = "file://" then String.sub uri_str 7 (String.length uri_str - 7) else uri_str with _ -> uri_str) in
                begin match Hashtbl.find_opt states path with
                | None -> `Null
                | Some { st } ->
                  (match Dm.DocumentManager.jump_to_definition st pos with
                  | Some (range, _word) ->
                    let loc = Lsp.Types.Location.create ~uri:(Lsp.Types.DocumentUri.of_path uri_str) ~range in
                    `List [ Lsp.Types.Location.yojson_of_t loc ]
                  | None -> `Null)
                end
              | _ -> `Null
            in
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", result_json)] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/semanticTokens/full" then (
            (* Build full-document semantic tokens *)
            let params_json = match json with `Assoc fields -> (match List.assoc_opt "params" fields with Some v -> v | None -> `Null) | _ -> `Null in
            let uri_opt = match params_json with
              | `Assoc fields -> (match List.assoc_opt "textDocument" fields with
                | Some (`Assoc td) -> (match List.assoc_opt "uri" td with Some (`String s) -> Some s | _ -> None)
                | _ -> None)
              | _ -> None in
            let data = match uri_opt with
              | None -> []
              | Some uri_str ->
                begin match get_document_text_by_uri uri_str with
                | None -> []
                | Some text ->
                  let tokens = analyze_easycrypt_document_syntax uri_str text in
                  encode_semantic_tokens_data tokens
                end
            in
            let result = `Assoc [ ("data", `List (List.map (fun i -> `Int i) data)) ] in
            let resp = `Assoc [ ("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", result) ] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/semanticTokens/range" then (
            (* Build range-based semantic tokens *)
            let params_json = match json with `Assoc fields -> (match List.assoc_opt "params" fields with Some v -> v | None -> `Null) | _ -> `Null in
            let (uri_opt, range_opt) =
              match params_json with
              | `Assoc fields ->
                let u = (match List.assoc_opt "textDocument" fields with
                  | Some (`Assoc td) -> (match List.assoc_opt "uri" td with Some (`String s) -> Some s | _ -> None)
                  | _ -> None) in
                let r = (match List.assoc_opt "range" fields with
                  | Some (`Assoc rfields) ->
                    let get_pos name = match List.assoc_opt name rfields with
                      | Some (`Assoc pf) ->
                        (match (List.assoc_opt "line" pf, List.assoc_opt "character" pf) with
                          | (Some (`Int l), Some (`Int c)) -> Some (Lsp.Types.Position.create ~line:l ~character:c)
                          | _ -> None)
                      | _ -> None in
                    begin match (get_pos "start", get_pos "end") with
                      | (Some s, Some e) -> Some (Lsp.Types.Range.create ~start:s ~end_:e)
                      | _ -> None
                    end
                  | _ -> None) in
                (u, r)
              | _ -> (None, None)
            in
            let data = match (uri_opt, range_opt) with
              | (Some uri_str, Some range) ->
                begin match get_document_text_by_uri uri_str with
                | None -> []
                | Some text ->
                  let tokens = analyze_easycrypt_document_syntax uri_str text in
                  let filtered = filter_tokens_in_range tokens range in
                  encode_semantic_tokens_data filtered
                end
              | _ -> []
            in
            let result = `Assoc [ ("data", `List (List.map (fun i -> `Int i) data)) ] in
            let resp = `Assoc [ ("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", result) ] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/documentSymbol" then (
            (* Return DocumentSymbol[] for the current document *)
            let params_json = match json with `Assoc fields -> (match List.assoc_opt "params" fields with Some v -> v | None -> `Null) | _ -> `Null in
            let uri_opt = match params_json with
              | `Assoc fields -> (match List.assoc_opt "textDocument" fields with
                | Some (`Assoc td) -> (match List.assoc_opt "uri" td with Some (`String s) -> Some s | _ -> None)
                | _ -> None)
              | _ -> None in
            let symbols_json = match uri_opt with
              | None -> `List []
              | Some uri_str ->
                let path = (try if String.length uri_str >= 7 && String.sub uri_str 0 7 = "file://" then String.sub uri_str 7 (String.length uri_str - 7) else uri_str with _ -> uri_str) in
                begin match Hashtbl.find_opt states path with
                | None -> `List []
                | Some { st } ->
                  let syms = Dm.DocumentManager.get_document_symbols st in
                  `List (List.map Lsp.Types.DocumentSymbol.yojson_of_t syms)
                end
            in
            let resp = `Assoc [ ("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", symbols_json) ] in
            output_json resp; []
          ) else if String.equal req.method_ "workspace/symbol" then (
            (* Workspace symbol: simple filter over all tracked document symbols *)
            let params_json = match json with `Assoc fields -> (match List.assoc_opt "params" fields with Some v -> v | None -> `Null) | _ -> `Null in
            let query = match params_json with
              | `Assoc fields -> (match List.assoc_opt "query" fields with Some (`String s) -> s | _ -> "")
              | _ -> ""
            in
            let matches name =
              let q = String.lowercase_ascii query in
              let n = String.lowercase_ascii name in
              q = "" || (String.length q <= String.length n && String.sub n 0 (String.length q) = q)
            in
            let all = Hashtbl.fold (fun path { st; _ } acc ->
              let uri = Lsp.Types.DocumentUri.of_path path in
              let syms = Dm.DocumentManager.get_document_symbols st in
              let rec flat (s:Lsp.Types.DocumentSymbol.t) : Lsp.Types.SymbolInformation.t list =
                let open Lsp.Types in
                let info = SymbolInformation.create ~name:s.name ~kind:s.kind ~location:(Location.create ~uri ~range:s.range) () in
                let children = match s.children with None -> [] | Some ch -> List.concat (List.map flat ch) in
                info :: children
              in
              (List.concat (List.map flat syms)) @ acc
            ) states [] in
            let filtered = List.filter (fun (si:Lsp.Types.SymbolInformation.t) -> matches si.name) all in
            let result = `List (List.map Lsp.Types.SymbolInformation.yojson_of_t filtered) in
            let resp = `Assoc [ ("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", result) ] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/signatureHelp" then (
            let result = `Assoc [
              ("signatures", `List [`Assoc [("label", `String "f(x)"); ("parameters", `List [`Assoc [("label", `String "x")]])]]);
              ("activeSignature", `Int 0);
              ("activeParameter", `Int 0)
            ] in
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", result)] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/codeAction" then (
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", `List [])] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/inlayHint" then (
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", `List [])] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/formatting" then (
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", `List [])] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/rangeFormatting" then (
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", `List [])] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/onTypeFormatting" then (
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", `List [])] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/foldingRange" then (
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", `List [])] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/selectionRange" then (
            let params_json = match json with `Assoc fields -> (match List.assoc_opt "params" fields with Some v -> v | None -> `Null) | _ -> `Null in
            let positions = match params_json with
              | `Assoc fs -> (match List.assoc_opt "positions" fs with Some (`List l) -> l | _ -> [])
              | _ -> [] in
            let mk_range_of_pos = function
              | `Assoc pf -> (match (List.assoc_opt "line" pf, List.assoc_opt "character" pf) with
                  | (Some (`Int l), Some (`Int c)) ->
                      `Assoc [("range", `Assoc [("start", `Assoc [("line", `Int l); ("character", `Int c)]);
                                                  ("end", `Assoc [("line", `Int l); ("character", `Int c)])])]
                  | _ -> `Assoc [("range", `Assoc [("start", `Assoc [("line", `Int 0); ("character", `Int 0)]);
                                                  ("end", `Assoc [("line", `Int 0); ("character", `Int 0)])])])
              | _ -> `Assoc [("range", `Assoc [("start", `Assoc [("line", `Int 0); ("character", `Int 0)]);
                                              ("end", `Assoc [("line", `Int 0); ("character", `Int 0)])])]
            in
            let result = `List (List.map mk_range_of_pos positions) in
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", result)] in
            output_json resp; []
          ) else if String.equal req.method_ "workspace/executeCommand" then (
            let params_json = match json with `Assoc fields -> (match List.assoc_opt "params" fields with Some v -> v | None -> `Null) | _ -> `Null in
            let (cmd_opt, args_opt) =
              match params_json with
              | `Assoc fs ->
                let c = (match List.assoc_opt "command" fs with Some (`String s) -> Some s | _ -> None) in
                let a = (match List.assoc_opt "arguments" fs with Some (`List l) -> Some l | _ -> None) in
                (c, a)
              | _ -> (None, None)
            in
            let uri_of_arg = function
              | `Assoc fields ->
                (match List.assoc_opt "textDocument" fields with
                | Some (`Assoc td) -> (match List.assoc_opt "uri" td with Some (`String s) -> Some s | _ -> None)
                | _ -> (match List.assoc_opt "uri" fields with Some (`String s) -> Some s | _ -> None))
              | _ -> None
            in
            let pos_of_arg = function
              | `Assoc fields ->
                (match List.assoc_opt "position" fields with
                | Some (`Assoc pf) -> (match (List.assoc_opt "line" pf, List.assoc_opt "character" pf) with Some (`Int l), Some (`Int c) -> Some (Lsp.Types.Position.create ~line:l ~character:c) | _ -> None)
                | _ -> None)
              | _ -> None
            in
            let handle_ok () =
              let result = `Null in
              let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", result)] in
              output_json resp; []
            in
            begin match cmd_opt, args_opt with
            | Some "easycrypt.stepForward", Some (arg0 :: _) ->
              (match uri_of_arg arg0 with
              | None -> handle_ok ()
              | Some uri_str ->
                let uri = Lsp.Types.DocumentUri.of_string uri_str in
                begin match Hashtbl.find_opt states (DocumentUri.to_path uri) with
                | None -> handle_ok ()
                | Some { st; visible } ->
                  (try
                    let (new_st, events) = Dm.DocumentManager.interpret_to_next st in
                    Hashtbl.replace states (DocumentUri.to_path uri) { st = new_st; visible };
                    let obs_id = Dm.DocumentManager.Internal.observe_id new_st in
                    let proof_state = Dm.DocumentManager.get_proof new_st obs_id in
                    (match proof_state with Some proof -> send_proof_view_notification (DocumentUri.to_string uri) proof | None -> ());
                    let diagnostics = Dm.DocumentManager.all_diagnostics new_st in
                    let publish = Lsp.Types.PublishDiagnosticsParams.create ~uri ~diagnostics () in
                    output_json (Jsonrpc.Notification.yojson_of_t (Lsp.Server_notification.to_jsonrpc (PublishDiagnostics publish)));
                    send_messages_notification (DocumentUri.to_string uri) diagnostics;
                    handle_ok ()
                  with _ -> handle_ok ())
                end)
            | Some "easycrypt.stepBackward", Some (arg0 :: _) ->
              (match uri_of_arg arg0 with
              | None -> handle_ok ()
              | Some uri_str ->
                let uri = Lsp.Types.DocumentUri.of_string uri_str in
                begin match Hashtbl.find_opt states (DocumentUri.to_path uri) with
                | None -> handle_ok ()
                | Some { st; visible } ->
                  (try
                    let (new_st, events) = Dm.DocumentManager.interpret_to_previous st in
                    Hashtbl.replace states (DocumentUri.to_path uri) { st = new_st; visible };
                    let obs_id = Dm.DocumentManager.Internal.observe_id new_st in
                    let proof_state = Dm.DocumentManager.get_proof new_st obs_id in
                    (match proof_state with Some proof -> send_proof_view_notification (DocumentUri.to_string uri) proof | None -> ());
                    handle_ok ()
                  with _ -> handle_ok ())
                end)
            | Some "easycrypt.interpretToPoint", Some (arg0 :: _) ->
              (match uri_of_arg arg0, pos_of_arg arg0 with
              | Some uri_str, Some pos ->
                let uri = Lsp.Types.DocumentUri.of_string uri_str in
                begin match Hashtbl.find_opt states (DocumentUri.to_path uri) with
                | None -> handle_ok ()
                | Some { st; visible } ->
                  (try
                    let (new_st, events) = Dm.DocumentManager.interpret_to_position st pos in
                    Hashtbl.replace states (DocumentUri.to_path uri) { st = new_st; visible };
                    let obs_id = Dm.DocumentManager.Internal.observe_id new_st in
                    let proof_state = Dm.DocumentManager.get_proof new_st obs_id in
                    (match proof_state with Some proof -> send_proof_view_notification (DocumentUri.to_string uri) proof | None -> ());
                    handle_ok ()
                  with _ -> handle_ok ())
                end
              | _ -> handle_ok ())
            | Some "easycrypt.interpretToEnd", Some (arg0 :: _) ->
              (match uri_of_arg arg0 with
              | None -> handle_ok ()
              | Some uri_str ->
                let uri = Lsp.Types.DocumentUri.of_string uri_str in
                begin match Hashtbl.find_opt states (DocumentUri.to_path uri) with
                | None -> handle_ok ()
                | Some { st; visible } ->
                  (try
                    let (new_st, events) = Dm.DocumentManager.interpret_to_end st in
                    Hashtbl.replace states (DocumentUri.to_path uri) { st = new_st; visible };
                    handle_ok ()
                  with _ -> handle_ok ())
                end)
            | Some "easycrypt.cancel", Some (arg0 :: _) ->
              (match uri_of_arg arg0 with
              | None -> handle_ok ()
              | Some uri_str ->
                let uri = Lsp.Types.DocumentUri.of_string uri_str in
                begin match Hashtbl.find_opt states (DocumentUri.to_path uri) with
                | None -> handle_ok ()
                | Some { st; visible } ->
                  Dm.DocumentManager.Internal.cancel st;
                  handle_ok ()
                end)
            | _ -> handle_ok ()
            end
          ) else if String.equal req.method_ "textDocument/typeDefinition" then (
            (* Reuse definition logic *)
            let params_json = match json with `Assoc fields -> (match List.assoc_opt "params" fields with Some v -> v | None -> `Null) | _ -> `Null in
            let (uri_opt, pos_opt) =
              match params_json with
              | `Assoc fields ->
                let u = (match List.assoc_opt "textDocument" fields with
                  | Some (`Assoc td) -> (match List.assoc_opt "uri" td with Some (`String s) -> Some s | _ -> None)
                  | _ -> None) in
                let p = (match List.assoc_opt "position" fields with
                  | Some (`Assoc pf) -> (match (List.assoc_opt "line" pf, List.assoc_opt "character" pf) with Some (`Int l), Some (`Int c) -> Some (Lsp.Types.Position.create ~line:l ~character:c) | _ -> None)
                  | _ -> None) in
                (u,p)
              | _ -> (None,None)
            in
            let result_json =
              match (uri_opt, pos_opt) with
              | (Some uri_str, Some pos) ->
                let path = (try if String.length uri_str >= 7 && String.sub uri_str 0 7 = "file://" then String.sub uri_str 7 (String.length uri_str - 7) else uri_str with _ -> uri_str) in
                begin match Hashtbl.find_opt states path with
                | None -> `Null
                | Some { st } ->
                  (match Dm.DocumentManager.jump_to_definition st pos with
                  | Some (range, _word) ->
                    let loc = Lsp.Types.Location.create ~uri:(Lsp.Types.DocumentUri.of_path uri_str) ~range in
                    `List [ Lsp.Types.Location.yojson_of_t loc ]
                  | None -> `Null)
                end
              | _ -> `Null
            in
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", result_json)] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/implementation" then (
            (* Reuse definition logic *)
            let params_json = match json with `Assoc fields -> (match List.assoc_opt "params" fields with Some v -> v | None -> `Null) | _ -> `Null in
            let (uri_opt, pos_opt) =
              match params_json with
              | `Assoc fields ->
                let u = (match List.assoc_opt "textDocument" fields with
                  | Some (`Assoc td) -> (match List.assoc_opt "uri" td with Some (`String s) -> Some s | _ -> None)
                  | _ -> None) in
                let p = (match List.assoc_opt "position" fields with
                  | Some (`Assoc pf) -> (match (List.assoc_opt "line" pf, List.assoc_opt "character" pf) with Some (`Int l), Some (`Int c) -> Some (Lsp.Types.Position.create ~line:l ~character:c) | _ -> None)
                  | _ -> None) in
                (u,p)
              | _ -> (None,None)
            in
            let result_json =
              match (uri_opt, pos_opt) with
              | (Some uri_str, Some pos) ->
                let path = (try if String.length uri_str >= 7 && String.sub uri_str 0 7 = "file://" then String.sub uri_str 7 (String.length uri_str - 7) else uri_str with _ -> uri_str) in
                begin match Hashtbl.find_opt states path with
                | None -> `Null
                | Some { st } ->
                  (match Dm.DocumentManager.jump_to_definition st pos with
                  | Some (range, _word) ->
                    let loc = Lsp.Types.Location.create ~uri:(Lsp.Types.DocumentUri.of_path uri_str) ~range in
                    `List [ Lsp.Types.Location.yojson_of_t loc ]
                  | None -> `Null)
                end
              | _ -> `Null
            in
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", result_json)] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/linkedEditingRange" then (
            let params_json = match json with `Assoc fields -> (match List.assoc_opt "params" fields with Some v -> v | None -> `Null) | _ -> `Null in
            let (uri_opt, pos_opt) =
              match params_json with
              | `Assoc fields ->
                let u = (match List.assoc_opt "textDocument" fields with
                  | Some (`Assoc td) -> (match List.assoc_opt "uri" td with Some (`String s) -> Some s | _ -> None)
                  | _ -> None) in
                let p = (match List.assoc_opt "position" fields with
                  | Some (`Assoc pf) -> (match (List.assoc_opt "line" pf, List.assoc_opt "character" pf) with Some (`Int l), Some (`Int c) -> Some (Lsp.Types.Position.create ~line:l ~character:c) | _ -> None)
                  | _ -> None) in
                (u,p)
              | _ -> (None,None)
            in
            let result_json =
              match (uri_opt, pos_opt) with
              | (Some uri_str, Some pos) ->
                let path = (try if String.length uri_str >= 7 && String.sub uri_str 0 7 = "file://" then String.sub uri_str 7 (String.length uri_str - 7) else uri_str with _ -> uri_str) in
                begin match Hashtbl.find_opt states path with
                | None -> `Null
                | Some { st } ->
                  let raw = Dm.DocumentManager.Internal.raw_document st in
                  (match RawDocument.word_at_position raw pos with
                  | None -> `Null
                  | Some _ ->
                    let range = Dm.DocumentManager.get_previous_range st pos |> Option.value ~default:(Lsp.Types.Range.create ~start:pos ~end_:pos) in
                    `Assoc [("ranges", `List [ Lsp.Types.Range.yojson_of_t range ])])
                end
              | _ -> `Null
            in
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", result_json)] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/documentColor" then (
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", `List [])] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/colorPresentation" then (
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", `List [])] in
            output_json resp; []
          ) else if String.equal req.method_ "textDocument/prepareCallHierarchy" then (
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", `List [])] in
            output_json resp; []
          ) else if String.equal req.method_ "callHierarchy/incomingCalls" then (
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", `List [])] in
            output_json resp; []
          ) else if String.equal req.method_ "callHierarchy/outgoingCalls" then (
            let resp = `Assoc [("jsonrpc", `String "2.0"); ("id", Jsonrpc.Id.yojson_of_t req.id); ("result", `List [])] in
            output_json resp; []
          ) else (
          log (fun () -> "About to call Request.Client.t_of_jsonrpc");
          (* Standard decode & dispatch *)
          (* DEBUG: Add more logging *)
          log (fun () -> "DEBUG: Starting request decode");
          let decode_result = try
            Request.Client.t_of_jsonrpc req
          with 
          | exn -> 
            log (fun () -> "Exception in Request.Client.t_of_jsonrpc: " ^ Printexc.to_string exn);
            Error "Exception during request decode"
          in
          log (fun () -> "Request.Client.t_of_jsonrpc completed");
          begin match decode_result with

          | Error(e) -> 
            log (fun () -> "Error decoding request: " ^ e);
            []
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
              output_json @@ `Assoc [
                ("jsonrpc", `String "2.0");
                ("id", Jsonrpc.Id.yojson_of_t req.id);
                ("error", `Assoc [
                  ("code", `Int (-32603));
                  ("message", `String message)
                ])
              ]
            | Ok resp ->
              log (fun () -> "Request succeeded - sending response");
              let resp = Request.Client.yojson_of_result r resp in
              log (fun () -> "Response JSON created - calling output_json");
              output_json @@ Jsonrpc.Response.(yojson_of_t @@ ok req.id resp);
              log (fun () -> "Response sent")
            end;
            events
          end
          )
      | Notification notif ->
          log (fun () -> "ui notification - trying interactive proving first");
          begin match Protocol.ExtProtocol.Notification.Client.of_jsonrpc notif with
          | Ok interactive_notif -> 
            log (fun () -> "Successfully decoded as interactive proving notification");
            dispatch_interactive_notification interactive_notif
          | Error e -> 
            log (fun () -> "Not an interactive proving notification, trying standard LSP");
            begin match Lsp.Client_notification.of_jsonrpc notif with
            | Ok (TextDocumentDidOpen params) -> 
              log (fun () -> "Processing TextDocumentDidOpen notification");
              textDocumentDidOpen params
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
          end
      | Response resp ->
          log (fun () -> "got unknown response");
          []
      | Batch_response _ -> log (fun () -> "Unsupported batch response received"); []
      | Batch_call _ -> log (fun () -> "Unsupported batch call received"); []
      end
      end
    with Ppx_yojson_conv_lib__Yojson_conv.Of_yojson_error(exn,json) ->
      log (fun () -> "error parsing json: " ^ Yojson.Safe.pretty_to_string json);
      []
    | exn ->
      (* Catch-all to prevent the server from crashing on unexpected exceptions *)
      log (fun () -> "unhandled exception in handle_lsp_event: " ^ Printexc.to_string exn);
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
          (* Publish diagnostics from DocumentManager only; no regex heuristics *)
          let diagnostics = Dm.DocumentManager.all_diagnostics st in
          let publish = Lsp.Types.PublishDiagnosticsParams.create ~uri ~diagnostics () in
          output_json (Jsonrpc.Notification.yojson_of_t (Lsp.Server_notification.to_jsonrpc (PublishDiagnostics publish)));
          send_messages_notification (Lsp.Types.DocumentUri.to_string uri) diagnostics;
          (* Progress update log *)
          let exec_st = Dm.DocumentManager.Internal.execution_state st in
          let ov = Dm.ExecutionManager.overview exec_st in
          let processed = List.length ov.processed and processing = List.length ov.processing and prepared = List.length ov.prepared in
          send_log (Printf.sprintf "Progress: processed=%d processing=%d prepared=%d" processed processing prepared);
          (* Also send execution overview as a structured notification *)
          send_execution_overview_notification (Lsp.Types.DocumentUri.to_string uri) ov;
          let obs = Dm.DocumentManager.Internal.observe_id st in
          let proof_state = Dm.DocumentManager.get_proof st obs in
          (match proof_state with
          | Some proof ->
            send_proof_view_notification (Lsp.Types.DocumentUri.to_string uri) proof
          | None -> ())
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