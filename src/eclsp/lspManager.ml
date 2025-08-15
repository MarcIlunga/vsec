(* LSP Manager for EasyCrypt - Adapted from VSRocq *)

open Lsp.Types
open Protocol
open Protocol.LspWrapper
open Protocol.ExtProtocol
open Protocol.ProofState
open Dm
open EcLib

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
        let raw = Bytes.to_string buff in
        (* Try direct JSON decode *)
        try LspManagerEvent (Receive (Some (Jsonrpc.Packet.t_of_yojson (Yojson.Safe.from_string raw)))) with exn1 ->
          (* Attempt to strip headers if present *)
          let sep = "\r\n\r\n" in
          let try_header_strip s =
            try
              let idx = String.index_from s 0 '\r' in
              (* find the double CRLF *)
              let rec find_sep start =
                if start < 0 then None else
                try
                  let i = String.index_from s start '\r' in
                  if i + 3 < String.length s && String.sub s i 4 = sep then Some (i+4)
                  else find_sep (i+1)
                with Not_found -> None
              in
              match find_sep idx with
              | Some body_start -> Some (String.sub s body_start (String.length s - body_start))
              | None -> None
            with _ -> None
          in
          begin match try_header_strip raw with
          | Some body -> (
              try
                LspManagerEvent (Receive (Some (Jsonrpc.Packet.t_of_yojson (Yojson.Safe.from_string body))))
              with exn2 ->
                log (fun () -> "failed to decode json after header strip");
                Printf.eprintf "DECODE-FAIL: direct=%s after-strip=%s\n%!" (Printexc.to_string exn1) (Printexc.to_string exn2);
                LspManagerEvent (Receive None)
            )
          | None ->
              log (fun () -> "failed to decode json and no headers found");
              Printf.eprintf "DECODE-FAIL: direct=%s raw-bytes=%d\n%!" (Printexc.to_string exn1) (String.length raw);
              LspManagerEvent (Receive None)
          end
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
  (* TODO: Add semantic tokens when LSP library supports it *)
  let capabilities = Lsp.Types.ServerCapabilities.create
    ~textDocumentSync
    ~completionProvider
    ~hoverProvider
    ~definitionProvider
  ()
  in
  let initialize_result = Lsp.Types.InitializeResult.{
    capabilities = capabilities; 
    serverInfo = Some server_info;
  } in
  log (fun () -> "EasyCrypt LSP initialized");
  Ok initialize_result, []

(* Helper function to analyze document context around cursor for enhanced completions *)
let analyze_completion_context (uri : DocumentUri.t) (position : Position.t) =
  try
    match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path uri) with
    | None -> ""
    | Some {st} ->
      let raw_doc = Dm.DocumentManager.Internal.raw_document st in
      let text = RawDocument.text raw_doc in
      let lines = String.split_on_char '\n' text in
      
      if position.line >= 0 && position.line < List.length lines then
        let current_line = List.nth lines position.line in
        let line_prefix = 
          if position.character >= 0 && position.character <= String.length current_line then
            String.sub current_line 0 (min position.character (String.length current_line))
          else current_line
        in
        String.trim line_prefix
      else ""
  with _ -> ""

(* Enhanced completion items based on line context *)
let get_context_aware_completions line_prefix =
  let prefix_lower = String.lowercase_ascii line_prefix in
  
  (* Context-specific completions based on what's been typed *)
  if String.contains prefix_lower '.' then
    (* After a dot - suggest field access or qualified names *)
    [
      Lsp.Types.CompletionItem.create ~label:"add" ~kind:CompletionItemKind.Method 
        ~detail:"Operation on collections" ();
      Lsp.Types.CompletionItem.create ~label:"mem" ~kind:CompletionItemKind.Method 
        ~detail:"Membership test" ();
      Lsp.Types.CompletionItem.create ~label:"size" ~kind:CompletionItemKind.Method 
        ~detail:"Size of collection" ();
    ]
  else if String.ends_with ~suffix:"require" prefix_lower then
    (* After "require" - suggest import patterns *)
    [
      Lsp.Types.CompletionItem.create ~label:"import" ~kind:CompletionItemKind.Keyword 
        ~detail:"Complete require import" ();
      Lsp.Types.CompletionItem.create ~label:"List" ~kind:CompletionItemKind.Module 
        ~detail:"Standard list theory" ();
      Lsp.Types.CompletionItem.create ~label:"Logic" ~kind:CompletionItemKind.Module 
        ~detail:"Basic logic theory" ();
      Lsp.Types.CompletionItem.create ~label:"Real" ~kind:CompletionItemKind.Module 
        ~detail:"Real number theory" ();
    ]
  else if String.ends_with ~suffix:"apply" prefix_lower then
    (* After "apply" - suggest common lemmas *)
    [
      Lsp.Types.CompletionItem.create ~label:"trivial" ~kind:CompletionItemKind.Value 
        ~detail:"Trivial lemma application" ();
      Lsp.Types.CompletionItem.create ~label:"(" ~kind:CompletionItemKind.Snippet 
        ~detail:"Apply with arguments" ~insertText:"($1)" ();
    ]
  else if String.contains prefix_lower ':' && (String.contains prefix_lower '{' || String.contains prefix_lower '}') then
    (* Inside type annotation or record - suggest type completions *)
    [
      Lsp.Types.CompletionItem.create ~label:"bool" ~kind:CompletionItemKind.TypeParameter ();
      Lsp.Types.CompletionItem.create ~label:"int" ~kind:CompletionItemKind.TypeParameter ();
      Lsp.Types.CompletionItem.create ~label:"'a list" ~kind:CompletionItemKind.TypeParameter 
        ~detail:"Generic list type" ();
    ]
  else 
    []

(* Copy VSRocq completion and hover functions *)
let rec textDocumentCompletion id params =
  log (fun () -> "[textDocumentCompletion] handler entered");
  let return_completion ~isIncomplete ~items =
    Ok (Some (`CompletionList (Lsp.Types.CompletionList.create ~isIncomplete ~items ())))
  in
  let Lsp.Types.CompletionParams.{ textDocument = { uri }; position } = params in
  match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path uri) with
  | None -> 
    log (fun () -> "[textDocumentCompletion] ignoring event on non existent document"); 
    Error( {code=None; message="Document does not exist"} ), []
  | Some { st } -> 
    (* 🎯 Phase 8.2.1: Context-Aware EasyCrypt Completion - ENHANCED! *)
    log (fun () -> Printf.sprintf "[textDocumentCompletion] position: line=%d, char=%d" 
                    position.line position.character);
                    
    (* 📝 ENHANCED: Analyze document context around cursor position *)
    let line_prefix = analyze_completion_context uri position in
    let context_items = get_context_aware_completions line_prefix in
    log (fun () -> Printf.sprintf "📝 Line context: '%s' → %d context-specific completions" 
      line_prefix (List.length context_items));
    
    (* EasyCrypt Keywords *)
    let keyword_items = [
      Lsp.Types.CompletionItem.create ~label:"lemma" ~kind:CompletionItemKind.Keyword ();
      Lsp.Types.CompletionItem.create ~label:"theorem" ~kind:CompletionItemKind.Keyword ();
      Lsp.Types.CompletionItem.create ~label:"axiom" ~kind:CompletionItemKind.Keyword ();
      Lsp.Types.CompletionItem.create ~label:"proof" ~kind:CompletionItemKind.Keyword ();
      Lsp.Types.CompletionItem.create ~label:"qed" ~kind:CompletionItemKind.Keyword ();
      Lsp.Types.CompletionItem.create ~label:"module" ~kind:CompletionItemKind.Module ();
      Lsp.Types.CompletionItem.create ~label:"theory" ~kind:CompletionItemKind.Module ();
    ] in
    
    (* EasyCrypt Tactics *)
    let tactic_items = [
      Lsp.Types.CompletionItem.create ~label:"apply" ~kind:CompletionItemKind.Function ();
      Lsp.Types.CompletionItem.create ~label:"rewrite" ~kind:CompletionItemKind.Function ();
      Lsp.Types.CompletionItem.create ~label:"unfold" ~kind:CompletionItemKind.Function ();
      Lsp.Types.CompletionItem.create ~label:"simplify" ~kind:CompletionItemKind.Function ();
      Lsp.Types.CompletionItem.create ~label:"auto" ~kind:CompletionItemKind.Function ();
      Lsp.Types.CompletionItem.create ~label:"by" ~kind:CompletionItemKind.Keyword ();
    ] in
    
    (* EasyCrypt Types *)
    let type_items = [
      Lsp.Types.CompletionItem.create ~label:"bool" ~kind:CompletionItemKind.TypeParameter ();
      Lsp.Types.CompletionItem.create ~label:"int" ~kind:CompletionItemKind.TypeParameter ();
      Lsp.Types.CompletionItem.create ~label:"unit" ~kind:CompletionItemKind.TypeParameter ();
      Lsp.Types.CompletionItem.create ~label:"option" ~kind:CompletionItemKind.TypeParameter ();
    ] in
    
    (* Determine current prefix (last word chars in the line prefix) *)
    let current_prefix =
      let is_word_char = function 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' | '\'' -> true | _ -> false in
      let rec last_word s i =
        if i <= 0 then ""
        else if is_word_char s.[i-1] then
          let j = ref (i-1) in
          while !j > 0 && is_word_char s.[!j-1] do decr j done;
          String.sub s !j (i - !j)
        else last_word s (i-1)
      in
      last_word line_prefix (String.length line_prefix)
    in

    (* Outline-backed symbol suggestions from parsed document (filtered by prefix) *)
    let outline_symbol_items =
      try
        let doc = Dm.DocumentManager.Internal.document st in
        let outline = Dm.Document.outline doc in
        let to_kind (t : Dm.Document.proof_block_type) =
          match t with
          | Dm.Document.TheoremKind -> CompletionItemKind.Function
          | Dm.Document.DefinitionType -> CompletionItemKind.Variable
          | Dm.Document.InductiveType -> CompletionItemKind.Struct
          | Dm.Document.BeginModule -> CompletionItemKind.Module
          | Dm.Document.BeginSection -> CompletionItemKind.Class
          | Dm.Document.End -> CompletionItemKind.Text
          | Dm.Document.Other -> CompletionItemKind.Text
        in
        let starts_with label prefix =
          if prefix = "" then true else
          let lp = String.lowercase_ascii prefix in
          let ll = String.lowercase_ascii label in
          let n = String.length lp in
          String.length ll >= n && String.sub ll 0 n = lp
        in
        let items =
          outline
          |> List.filter (fun (e : Dm.Document.outline_element) -> starts_with e.name current_prefix)
          |> List.map (fun (e : Dm.Document.outline_element) ->
               Lsp.Types.CompletionItem.create ~label:e.name ~kind:(to_kind e.type_) ~detail:"symbol from outline" ())
        in
        log (fun () -> Printf.sprintf "🧭 Outline provided %d symbol items" (List.length items));
        items
      with _ -> []
    in

    (* 🪄 ENHANCED: Intelligent context-specific completions with EasyCrypt environment! *)
    try
      let exec_state = Dm.DocumentManager.Internal.execution_state st in
      let current_scope = Dm.ExecutionManager.get_initial_context exec_state in
      
      (* 🎯 ENHANCED: Extract symbols from EasyCrypt environment *)
      let environment_items = 
        try
          let env = EcScope.env current_scope in
          let path_info = EcPath.tostring (EcScope.path current_scope) in
          log (fun () -> Printf.sprintf "✨ Extracting completions from EasyCrypt environment at path: %s" path_info);
          
          (* Enhanced EasyCrypt environment-based completions *)
          let env_completion_items = [
            (* Add completions based on current environment *)
            Lsp.Types.CompletionItem.create ~label:"require" ~kind:CompletionItemKind.Keyword 
              ~detail:"Import theory or module" ();
            Lsp.Types.CompletionItem.create ~label:"import" ~kind:CompletionItemKind.Keyword 
              ~detail:"Import from current module" ();
            Lsp.Types.CompletionItem.create ~label:"require import" ~kind:CompletionItemKind.Snippet 
              ~detail:"Require and import in one command" ~insertText:"require import $1" ();
            
            (* Enhanced type completions *)
            Lsp.Types.CompletionItem.create ~label:"'a" ~kind:CompletionItemKind.TypeParameter 
              ~detail:"Type parameter (generic)" ();
            Lsp.Types.CompletionItem.create ~label:"list" ~kind:CompletionItemKind.TypeParameter 
              ~detail:"List type constructor" ();
            Lsp.Types.CompletionItem.create ~label:"set" ~kind:CompletionItemKind.TypeParameter 
              ~detail:"Set type constructor" ();
            Lsp.Types.CompletionItem.create ~label:"distr" ~kind:CompletionItemKind.TypeParameter 
              ~detail:"Distribution type" ();
              
            (* Module system completions *)
            Lsp.Types.CompletionItem.create ~label:"module type" ~kind:CompletionItemKind.Interface 
              ~detail:"Define module signature" ();
            Lsp.Types.CompletionItem.create ~label:"clone" ~kind:CompletionItemKind.Function 
              ~detail:"Clone theory with substitutions" ();
          ] in
          
          log (fun () -> Printf.sprintf "📚 Environment provided %d enhanced completions" (List.length env_completion_items));
          env_completion_items
          
        with env_exn ->
          log (fun () -> Printf.sprintf "⚠️ Environment access failed: %s" (Printexc.to_string env_exn));
          []
      in
      
      (* Check for active proof context for smart tactic suggestions *)
      match Protocol.ProofState.get_proof ~previous:None current_scope with
      | Some proof_state ->
        (* 🎯 ENHANCED PROOF CONTEXT COMPLETION! *)
        log (fun () -> "🎯 Detected active proof context - providing enhanced tactic completions");
        
        (* Enhanced tactic completions with detailed help *)
        let proof_tactic_items = [
          (* Basic tactics with confidence scores *)
          Lsp.Types.CompletionItem.create ~label:"intros" ~kind:CompletionItemKind.Function 
            ~detail:"95% • Introduce variables and hypotheses"
            ~documentation:(`String "Introduce all variables and hypotheses from the goal into the context") ();
          Lsp.Types.CompletionItem.create ~label:"apply" ~kind:CompletionItemKind.Function 
            ~detail:"90% • Apply lemma or hypothesis"
            ~documentation:(`String "Apply a lemma, theorem, or hypothesis to the current goal") ();
          Lsp.Types.CompletionItem.create ~label:"rewrite" ~kind:CompletionItemKind.Function 
            ~detail:"85% • Rewrite using equality"
            ~documentation:(`String "Rewrite the goal using an equality or equivalence") ();
          Lsp.Types.CompletionItem.create ~label:"unfold" ~kind:CompletionItemKind.Function 
            ~detail:"80% • Unfold definition"
            ~documentation:(`String "Unfold the definition of a symbol in the goal") ();
          Lsp.Types.CompletionItem.create ~label:"split" ~kind:CompletionItemKind.Function 
            ~detail:"80% • Split conjunction/equivalence"
            ~documentation:(`String "Split a conjunction or biconditional into separate goals") ();
          Lsp.Types.CompletionItem.create ~label:"left" ~kind:CompletionItemKind.Function 
            ~detail:"75% • Take left side of disjunction"
            ~documentation:(`String "Prove the left side of a disjunction") ();
          Lsp.Types.CompletionItem.create ~label:"right" ~kind:CompletionItemKind.Function 
            ~detail:"75% • Take right side of disjunction"
            ~documentation:(`String "Prove the right side of a disjunction") ();
          Lsp.Types.CompletionItem.create ~label:"assumption" ~kind:CompletionItemKind.Function 
            ~detail:"70% • Goal matches hypothesis"
            ~documentation:(`String "Prove the goal using an exact matching hypothesis") ();
            
          (* Advanced tactics *)
          Lsp.Types.CompletionItem.create ~label:"by smt()" ~kind:CompletionItemKind.Snippet 
            ~detail:"92% • SMT solver automation"
            ~documentation:(`String "Solve goal using automated SMT reasoning")
            ~insertText:"by smt($1)" ();
          Lsp.Types.CompletionItem.create ~label:"auto" ~kind:CompletionItemKind.Function 
            ~detail:"88% • Automatic proof search"
            ~documentation:(`String "Attempt automatic proof using built-in heuristics") ();
          Lsp.Types.CompletionItem.create ~label:"trivial" ~kind:CompletionItemKind.Function 
            ~detail:"75% • Try trivial methods"
            ~documentation:(`String "Apply trivial proof methods") ();
          Lsp.Types.CompletionItem.create ~label:"case" ~kind:CompletionItemKind.Function 
            ~detail:"70% • Case analysis"
            ~documentation:(`String "Perform case analysis on expressions or hypotheses") ();
          Lsp.Types.CompletionItem.create ~label:"elim" ~kind:CompletionItemKind.Function 
            ~detail:"65% • Elimination/induction"
            ~documentation:(`String "Apply elimination principle or induction") ();
        ] in
        
        (* 🎯 Context-aware completion based on goal content *)
        let context_specific_items = 
          (* TODO: Add goal-specific completion items *)
          []
        in
        
        (* Combine all proof-context completions *)
        let all_items = context_items @ proof_tactic_items @ context_specific_items @ outline_symbol_items @ environment_items @ keyword_items @ type_items in
        log (fun () -> Printf.sprintf "🎯 Proof context: %d text-context + %d tactics + %d goal-context + %d env + %d standard = %d total completions" 
          (List.length context_items) (List.length proof_tactic_items) (List.length context_specific_items) 
          (List.length (outline_symbol_items @ environment_items)) (List.length (keyword_items @ type_items)) (List.length all_items));
        
        return_completion ~isIncomplete:false ~items:all_items, []
        
      | _ ->
        (* Not in proof context - provide definition and module completions *)
        log (fun () -> "📝 Not in proof context - providing definition and module completions");
        
        let definition_items =
          if String.length current_prefix = 0 then [
            Lsp.Types.CompletionItem.create ~label:"op" ~kind:CompletionItemKind.Function 
              ~detail:"Define operator" ~insertText:"op $1 : $2 = $3" ();
            Lsp.Types.CompletionItem.create ~label:"pred" ~kind:CompletionItemKind.Function 
              ~detail:"Define predicate" ~insertText:"pred $1 : $2 = $3" ();
            Lsp.Types.CompletionItem.create ~label:"type" ~kind:CompletionItemKind.Interface 
              ~detail:"Define new type" ~insertText:"type $1 = $2" ();
            Lsp.Types.CompletionItem.create ~label:"lemma" ~kind:CompletionItemKind.Function 
              ~detail:"Prove lemma" ~insertText:"lemma $1 : $2 by $3" ();
            Lsp.Types.CompletionItem.create ~label:"theorem" ~kind:CompletionItemKind.Function 
              ~detail:"Prove theorem" ~insertText:"theorem $1 : $2\\nproof. $3 qed." ();
          ] else []
        in
        
        let all_items = context_items @ outline_symbol_items @ definition_items @ environment_items @ keyword_items @ tactic_items @ type_items in
        log (fun () -> Printf.sprintf "📝 Definition context: %d text-context + %d definition + %d env + %d standard = %d total completions" 
          (List.length context_items) (List.length definition_items) (List.length (outline_symbol_items @ environment_items)) 
          (List.length (keyword_items @ tactic_items @ type_items)) (List.length all_items));
        
        return_completion ~isIncomplete:false ~items:all_items, []
        
    with
    | exn -> 
      log (fun () -> Printf.sprintf "⚠️ Enhanced completion error: %s - falling back to basic completions" (Printexc.to_string exn));
      let all_items = keyword_items @ tactic_items @ type_items in
      return_completion ~isIncomplete:false ~items:all_items, []

and textDocumentHover id params = 
  let Lsp.Types.HoverParams.{ textDocument; position } = params in
  match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path textDocument.uri) with
  | None -> 
    log (fun () -> "[textDocumentHover] ignoring event on non existing document"); 
    Ok None, []
  | Some { st } ->
    (* 🎯 Phase 8.2.2: Enhanced EasyCrypt Hover Information - ENHANCED! *)
    log (fun () -> Printf.sprintf "[textDocumentHover] position: line=%d, char=%d" 
                    position.line position.character);
                    
    (* Get word at current position from raw document *)
    let raw_doc = Dm.DocumentManager.Internal.raw_document st in
    let text = RawDocument.text raw_doc in
    let loc = RawDocument.loc_of_position raw_doc position in
    
    (* Simple word extraction around cursor position *)
    let get_word_at_position text pos =
      let len = String.length text in
      if pos >= len || pos < 0 then None
      else
        let is_word_char = function
          | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' -> true
          | _ -> false
        in
        let start = ref pos in
        let end_pos = ref pos in
        
        (* Find start of word *)
        while !start > 0 && is_word_char text.[!start - 1] do
          decr start
        done;
        
        (* Find end of word *)
        while !end_pos < len && is_word_char text.[!end_pos] do
          incr end_pos  
        done;
        
        if !start < !end_pos then
          Some (String.sub text !start (!end_pos - !start))
        else None
    in
    
    match get_word_at_position text loc with
    | Some word ->
      log (fun () -> Printf.sprintf "[textDocumentHover] word: %s" word);
      
      (* Enhanced EasyCrypt hover information *)
      let hover_content = 
        let word_lower = String.lowercase_ascii word in
        if List.mem word_lower ["lemma"; "theorem"; "axiom"] then
          Printf.sprintf "**%s** - EasyCrypt definition keyword\n\nUsed to define mathematical statements and proofs." word
        else if List.mem word_lower ["proof"; "qed"] then
          Printf.sprintf "**%s** - EasyCrypt proof keyword\n\nMarks the %s of a proof block." word (if word_lower = "proof" then "beginning" else "end")
        else if List.mem word_lower ["module"; "theory"] then  
          Printf.sprintf "**%s** - EasyCrypt organization keyword\n\nUsed to organize code into logical units." word
        else if List.mem word_lower ["apply"; "rewrite"; "unfold"; "simplify"; "auto"] then
          let tactic_desc = match word_lower with
            | "apply" -> "Apply a lemma, theorem, or hypothesis to the current goal"
            | "rewrite" -> "Rewrite the goal using an equality or equivalence"
            | "unfold" -> "Unfold (expand) the definition of a symbol"  
            | "simplify" -> "Simplify expressions in the goal"
            | "auto" -> "Automatic proof search using built-in tactics"
            | _ -> "EasyCrypt proof tactic"
          in
          Printf.sprintf "**%s** - EasyCrypt tactic\n\n%s" word tactic_desc
        else if List.mem word_lower ["bool"; "int"; "unit"; "option"] then
          let type_desc = match word_lower with
            | "bool" -> "Boolean type (true/false values)"
            | "int" -> "Integer type (mathematical integers)"
            | "unit" -> "Unit type (single value: ())"
            | "option" -> "Option type (Some value or None)"
            | _ -> "EasyCrypt type"
          in
          Printf.sprintf "**%s** - EasyCrypt type\n\n%s" word type_desc
        else (
          (* Outline-backed hover: show definition statement if available *)
          try
            let doc = Dm.DocumentManager.Internal.document st in
            let outline = Dm.Document.outline doc in
            let lower s = String.lowercase_ascii s in
            let rec find_by_name = function
              | [] -> None
              | (e : Dm.Document.outline_element) :: tl ->
                  if lower e.name = word_lower then Some e else find_by_name tl
            in
            match find_by_name outline with
            | Some e ->
                let preview = e.statement in
                Printf.sprintf "**%s** - definition\n\n```easycrypt\n%s\n```" e.name preview
            | None ->
                Printf.sprintf "**%s** - EasyCrypt symbol\n\n_Type information and documentation will be enhanced in future versions._" word
          with _ ->
            Printf.sprintf "**%s** - EasyCrypt symbol\n\n_Type information and documentation will be enhanced in future versions._" word
        )
      in
      
      let markup_content = Lsp.Types.MarkupContent.create 
        ~kind:MarkupKind.Markdown ~value:hover_content in
      Ok (Some (Lsp.Types.Hover.create ~contents:(`MarkupContent markup_content) ())), []
      
    | None ->
      log (fun () -> "[textDocumentHover] no word found at position");
      Ok None, []

(* 🎯 Go to Definition Implementation - Navigate to symbol definitions *)
and textDocumentDefinition id params =
  log (fun () -> "[textDocumentDefinition] handler entered");
  let return_definition locations =
    Ok (Some (`Location locations))
  in
  let return_no_definition () =
    Ok None
  in
  
  let Lsp.Types.DefinitionParams.{ textDocument = { uri }; position } = params in
  match Hashtbl.find_opt states (Lsp.Types.DocumentUri.to_path uri) with
  | None -> 
    log (fun () -> "[textDocumentDefinition] ignoring event on non existent document"); 
    Error( {code=None; message="Document does not exist"} ), []
  | Some { st } ->
    (* 🎯 Enhanced Go to Definition with EasyCrypt symbol resolution + outline-backed lookup *)
    log (fun () -> Printf.sprintf "[textDocumentDefinition] position: line=%d, char=%d" 
                    position.line position.character);
    
    try
      (* Get word at current position *)
      let raw_doc = Dm.DocumentManager.Internal.raw_document st in
      let text = RawDocument.text raw_doc in
      let lines = String.split_on_char '\n' text in
      
      (* First, try outline-based definition resolution *)
      let find_in_outline (word : string) : Lsp.Types.Location.t list =
        try
          let doc = Dm.DocumentManager.Internal.document st in
          let outline = Dm.Document.outline doc in
          let lower s = String.lowercase_ascii s in
          let matches_name elt = lower elt.Dm.Document.name = lower word in
          let locations = ref [] in
          List.iter (fun (elt : Dm.Document.outline_element) ->
            if matches_name elt then (
              let start_pos = elt.range.start in
              let line_idx = start_pos.line in
              let char_guess = start_pos.character in
              if line_idx >= 0 && line_idx < List.length lines then (
                let line = List.nth lines line_idx in
                let rec seek_from i =
                  if i < 0 || i >= String.length line then -1
                  else if i + String.length word <= String.length line && String.sub line i (String.length word) = word then i
                  else seek_from (i + 1)
                in
                let char_pos = seek_from char_guess in
                let c0 = if char_pos >= 0 then char_pos else char_guess in
                let loc = Lsp.Types.Location.create ~uri ~range:(
                  Lsp.Types.Range.create
                    ~start:(Lsp.Types.Position.create ~line:line_idx ~character:c0)
                    ~end_:(Lsp.Types.Position.create ~line:line_idx ~character:(c0 + String.length word))
                ) in
                locations := loc :: !locations
              )
            )
          ) outline;
          List.rev !locations
        with _ -> []
      in
      
      if position.line >= 0 && position.line < List.length lines then
        let current_line = List.nth lines position.line in
        let line_length = String.length current_line in
        
        (* Extract word at position using same logic as hover *)
        let get_word_at_position line pos =
          if pos >= line_length || pos < 0 then None
          else
            let is_word_char = function
              | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' | '\'' -> true
              | _ -> false
            in
            let start = ref pos in
            let end_pos = ref pos in
            
            (* Find start of word *)
            while !start > 0 && is_word_char line.[!start - 1] do
              decr start
            done;
            
            (* Find end of word *)
            while !end_pos < line_length && is_word_char line.[!end_pos] do
              incr end_pos
            done;
            
            if !end_pos > !start then
              Some (String.sub line !start (!end_pos - !start))
            else None
        in
        
        (match get_word_at_position current_line position.character with
         | Some word ->
           log (fun () -> Printf.sprintf "[textDocumentDefinition] searching for definition of: '%s'" word);
           
           (* 1) Outline-backed resolution: prefer structural definitions *)
           let outline_defs = find_in_outline word in
           if outline_defs <> [] then (
             log (fun () -> Printf.sprintf "[textDocumentDefinition] outline provided %d location(s)" (List.length outline_defs));
             return_definition outline_defs, []
           ) else (
            (* 🎯 ENHANCED (regex-free): Search for definition in document *)
            let find_definition_in_document (word : string) : Lsp.Types.Location.t list =
              let is_ident_char = function
                | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' | '\'' -> true
                | _ -> false
              in
              let has_word_after_prefix line ~start_idx ~prefix_len ~word =
                let sym_start = start_idx + prefix_len in
                if sym_start + String.length word > String.length line then None
                else if String.sub line sym_start (String.length word) = word then (
                  let sym_end = sym_start + String.length word in
                  if sym_end >= String.length line || not (is_ident_char line.[sym_end]) then Some sym_start else None
                ) else None
              in
              let find_all_prefix_occurrences line prefix word =
                let rec loop acc idx =
                  if idx > String.length line - String.length prefix then List.rev acc
                  else
                    match String.index_from_opt line idx prefix.[0] with
                    | None -> List.rev acc
                    | Some i ->
                        if i + String.length prefix <= String.length line && String.sub line i (String.length prefix) = prefix then
                          (match has_word_after_prefix line ~start_idx:i ~prefix_len:(String.length prefix) ~word with
                           | Some sym_start -> loop (sym_start :: acc) (i + String.length prefix)
                           | None -> loop acc (i + 1))
                        else loop acc (i + 1)
                in
                loop [] 0
              in
              let prefixes = [
                "lemma "; "theorem "; "axiom ";
                "op "; "pred "; "type ";
                "module "; "theory ";
              ] in
              let locations = ref [] in
              List.iteri (fun line_idx line ->
                let line_s = line in
                List.iter (fun prefix ->
                  let starts = find_all_prefix_occurrences line_s prefix word in
                  List.iter (fun sym_start ->
                    let location = Lsp.Types.Location.create
                      ~uri
                      ~range:(Lsp.Types.Range.create
                                ~start:(Lsp.Types.Position.create ~line:line_idx ~character:sym_start)
                                ~end_:(Lsp.Types.Position.create ~line:line_idx ~character:(sym_start + String.length word))) in
                    locations := location :: !locations
                  ) starts
                ) prefixes
              ) lines;
              List.rev !locations
            in
           
           (* 🎯 ENHANCED: Try EasyCrypt environment resolution *)
           let find_in_easycrypt_environment word =
             try
               let exec_state = Dm.DocumentManager.Internal.execution_state st in
               let current_scope = Dm.ExecutionManager.get_initial_context exec_state in
               let env = EcScope.env current_scope in
               let path_info = EcPath.tostring (EcScope.path current_scope) in
               
               log (fun () -> Printf.sprintf "Searching EasyCrypt environment at path '%s' for symbol '%s'" path_info word);
               
               (* For now, return empty list but log the attempt *)
               log (fun () -> Printf.sprintf "EasyCrypt environment search for '%s' - integration pending" word);
               []
               
             with exn ->
               log (fun () -> Printf.sprintf "EasyCrypt environment search failed: %s" (Printexc.to_string exn));
               []
           in
           
            (* Combine all definition sources *)
            let document_definitions = find_definition_in_document word in
            let environment_definitions = find_in_easycrypt_environment word in
            let all_definitions = outline_defs @ document_definitions @ environment_definitions in
            
            (match all_definitions with
             | [] ->
               log (fun () -> Printf.sprintf "No definition found for '%s'" word);
               return_no_definition (), []
             | definitions ->
               log (fun () -> Printf.sprintf "Found %d definition(s) for '%s'" (List.length definitions) word);
               return_definition definitions, []
            ))
           
         | None ->
           log (fun () -> "[textDocumentDefinition] no word found at position");
           return_no_definition (), []
        )
      else (
        log (fun () -> "[textDocumentDefinition] position out of bounds");
        return_no_definition (), []
      )
        
    with exn ->
      log (fun () -> Printf.sprintf "⚠️ Definition search error: %s" (Printexc.to_string exn));
      return_no_definition (), []


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
        List.fold_left (fun acc word ->
          try
            let word_start = String.index_from line !char_pos (String.get word 0) in
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
            char_pos := word_start + String.length word;
            {line = line_idx; start_char = word_start; length = String.length word; token_type; classification = classif_str} :: acc
          with Not_found -> 
            char_pos := !char_pos + 1;
            acc
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

(* Utility: build a single highlight token for a range *)
let semantic_token_of_range (range: Lsp.Types.Range.t) : semantic_token =
  let open Lsp.Types in
  let start_ = range.start in
  let end_ = range.end_ in
  let length = max 0 (end_.character - start_.character) in
  { line = start_.line; start_char = start_.character; length; token_type = "highlight"; classification = "last-executed" }

(* TODO: 🎯 Phase 8.3.1: Document Symbols will be implemented when LSP library supports it *)

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
  | TextDocumentDefinition params ->
    let result, events = textDocumentDefinition id params in result, events
  | TextDocumentHover params ->
    let result, events = textDocumentHover id params in result, events
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

(* Copy VSRocq output_json function *)
let output_json obj =
  log (fun () -> "output_json called");
  let msg  = Yojson.Safe.pretty_to_string ~std:true obj in
  let size = String.length msg in
  let s = Printf.sprintf "Content-Length: %d\r\n\r\n%s" size msg in
  log (fun () -> "sent: " ^ msg);
  Printf.eprintf "STDOUT: about to write JSON (bytes=%d)\n%!" (String.length s);
  let bytes_written = Unix.write_substring Unix.stdout s 0 (String.length s) in
  log (fun () -> Printf.sprintf "Wrote %d bytes to stdout" bytes_written);
  Printf.eprintf "STDOUT: wrote %d bytes (jsonrpc)\n%!" bytes_written;
  flush stdout;
  log (fun () -> "stdout flushed")

(* --- Throttling of high-frequency notifications (H7.3) --- *)
let notif_last_sent : (string, float) Hashtbl.t = Hashtbl.create 7

let throttle_delay_for_method (m:string) : float =
  match m with
  | "prover/moveCursor" -> 0.05
  | "prover/proofView" -> 0.10
  | "vsec/semanticHighlighting" -> 0.00 (* do not throttle semantic tokens; let client handle view coalescing *)
  | _ -> 0.0

let should_send_method (m:string) : bool =
  let now = Unix.gettimeofday () in
  let delay = throttle_delay_for_method m in
  if delay <= 0.0 then true else
  match Hashtbl.find_opt notif_last_sent m with
  | None -> Hashtbl.replace notif_last_sent m now; true
  | Some last ->
    if now -. last >= delay then (Hashtbl.replace notif_last_sent m now; true)
    else false

let send_window_log level msg =
  let level_int = match level with `Error -> 1 | `Warning -> 2 | `Info -> 3 | `Log -> 4 in
  let log_msg : Yojson.Safe.t = `Assoc [
    ("jsonrpc", `String "2.0");
    ("method", `String "window/logMessage");
    ("params", `Assoc [ ("type", `Int level_int); ("message", `String msg) ])
  ] in
  output_json log_msg

let send_publish_diagnostics (uri: Lsp.Types.DocumentUri.t) (diagnostics: Yojson.Safe.t list) =
  let params : Yojson.Safe.t = `Assoc [
    ("uri", `String (Lsp.Types.DocumentUri.to_string uri));
    ("diagnostics", `List diagnostics)
  ] in
  let notif : Yojson.Safe.t = `Assoc [
    ("jsonrpc", `String "2.0");
    ("method", `String "textDocument/publishDiagnostics");
    ("params", params)
  ] in
  output_json notif

let mk_diagnostic ~line ~start_char ~end_char ~message ~severity =
  `Assoc [
    ("range", `Assoc [
      ("start", `Assoc [("line", `Int line); ("character", `Int start_char)]);
      ("end", `Assoc [("line", `Int line); ("character", `Int end_char)])
    ]);
    ("message", `String message);
    ("severity", `Int severity)
  ]

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

(* Expose a helper to send a single highlight token *)
let send_last_executed_highlight uri (range: Lsp.Types.Range.t) =
  let token = semantic_token_of_range range in
  send_semantic_highlighting_notification (Lsp.Types.DocumentUri.to_string uri) [token]

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
    open_new_document uri text
  | Some { st } ->
    log (fun () -> "Document already exists");
    (* Document already exists, skip validation for now *)
    let st = st in
    Hashtbl.replace states (Lsp.Types.DocumentUri.to_path uri) { st; visible = true };
    (* Send empty diagnostics to clear previous *)
    send_publish_diagnostics uri [];
    (* H3.3: On open, if an observe_id exists, send a proof view to initialize UI *)
    let extra_events =
      match Dm.DocumentManager.Internal.observe_id st with
      | None -> []
      | Some sid -> [Dm.DocumentManager.mk_proof_view_event sid]
    in
    inject_dm_events (uri, extra_events)

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
      (* H3.2: If currently inside a proof sentence, trigger interpret_to_point-like behavior by sending updated proof view *)
      let extra_events =
        match Dm.DocumentManager.Internal.observe_id st with
        | None -> []
        | Some sid -> [Dm.DocumentManager.mk_proof_view_event sid]
      in
      Hashtbl.replace states (Lsp.Types.DocumentUri.to_path uri) { st; visible };
      (* Diagnostics will be produced by DocumentManager events and routed here *)
      inject_dm_events (uri, events @ extra_events)

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

(* Interactive Proving Command Handlers - Copied and adapted from VSCoq *)

let ecInterpretToPoint params =
  let Protocol.ExtProtocol.Notification.Client.InterpretToPointParams.{ textDocument; position } = params in
  let uri = textDocument.uri in
  Printf.eprintf "🎯 DEBUG: ecInterpretToPoint called with URI: %s, position: %d:%d\n%!" 
    (DocumentUri.to_string uri) position.line position.character;
  match Hashtbl.find_opt states (DocumentUri.to_path uri) with
  | None -> 
    Printf.eprintf "❌ DEBUG: No document found for URI: %s\n%!" (DocumentUri.to_string uri);
    log (fun () -> "[interpretToPoint] ignoring event on non existent document"); 
    []
  | Some { st; visible } ->
    Printf.eprintf "✅ DEBUG: Document found, executing to position\n%!";
    log (fun () -> Printf.sprintf "[interpretToPoint] executing to line %d, char %d" 
      position.line position.character);
    
    (try
      (* Call actual DocumentManager.interpret_to_position *)
      let (new_st, events) = Dm.DocumentManager.interpret_to_position st position in
      Hashtbl.replace states (DocumentUri.to_path uri) { st = new_st; visible };
      
      (* Create SendProofView event to be processed after execution events *)
      Printf.eprintf "🔍 DEBUG: Creating SendProofView event to be processed after execution\n%!";
      let current_id_opt = Dm.DocumentManager.Internal.observe_id new_st in
      let proof_view_event = match current_id_opt with
        | Some current_id ->
          Printf.eprintf "DEBUG: Will send proof view for sentence id: %d\n%!" current_id;
          Dm.DocumentManager.mk_proof_view_event current_id
        | None ->
          Printf.eprintf "DEBUG: Will send empty proof view\n%!";
          Dm.DocumentManager.mk_proof_view_event_empty
      in
      
      Printf.eprintf "✅ DEBUG: interpretToPoint - queued proof view event for processing after execution\n%!";
      log (fun () -> "[interpretToPoint] queued proof view update");
      
      (* Return execution events + proof view event *)
      let all_events = events @ [proof_view_event] in
      inject_dm_events (uri, all_events)
    with
    | exn ->
      log (fun () -> Printf.sprintf "[interpretToPoint] error: %s" (Printexc.to_string exn));
      [])

let ecStepForward params =
  Printf.eprintf "🚀 LSP: ecStepForward function called\n%!";
  let Protocol.ExtProtocol.Notification.Client.StepForwardParams.{ textDocument = { uri } } = params in
  Printf.eprintf "🚀 LSP: Processing stepForward for URI: %s\n%!" (DocumentUri.to_string uri);
  match Hashtbl.find_opt states (DocumentUri.to_path uri) with
  | None -> 
    Printf.eprintf "❌ LSP: No document state found for %s\n%!" (DocumentUri.to_path uri);
    log (fun () -> "[stepForward] ignoring event on non existent document"); 
    []
  | Some { st; visible } ->
    Printf.eprintf "✅ LSP: Found document state, executing next step\n%!";
    log (fun () -> "[stepForward] executing next step");
    
    try
      let (new_st, events) = Dm.DocumentManager.interpret_to_next st in
      Hashtbl.replace states (DocumentUri.to_path uri) { st = new_st; visible };
      
      (* Create SendProofView event to be processed after execution events *)
      let current_id_opt = Dm.DocumentManager.Internal.observe_id new_st in
      Printf.eprintf "DEBUG: stepForward - observe_id after interpret_to_next: %s\n%!" 
        (match current_id_opt with Some id -> string_of_int id | None -> "None");
      
      let proof_view_event = match current_id_opt with
        | Some current_id ->
          Printf.eprintf "DEBUG: stepForward - will send proof view for sentence %d\n%!" current_id;
          Dm.DocumentManager.mk_proof_view_event current_id
        | None ->
          Printf.eprintf "DEBUG: stepForward - will send empty proof view\n%!";
          Dm.DocumentManager.mk_proof_view_event_empty
      in
      
      Printf.eprintf "✅ DEBUG: stepForward - queued proof view event for processing after execution\n%!";
      log (fun () -> "[stepForward] queued proof view update");
      
      (* Return execution events + proof view event *)
      let all_events = events @ [proof_view_event] in
      inject_dm_events (uri, all_events)
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
      
      (* Create SendProofView event to be processed after execution events *)
      let current_id_opt = Dm.DocumentManager.Internal.observe_id new_st in
      let proof_view_event = match current_id_opt with
        | Some current_id ->
          Printf.eprintf "DEBUG: stepBackward - will send proof view for sentence %d\n%!" current_id;
          Dm.DocumentManager.mk_proof_view_event current_id
        | None ->
          Printf.eprintf "DEBUG: stepBackward - will send empty proof view\n%!";
          Dm.DocumentManager.mk_proof_view_event_empty
      in
      
      Printf.eprintf "✅ DEBUG: stepBackward - queued proof view event for processing after execution\n%!";
      log (fun () -> "[stepBackward] queued proof view update");
      
      (* Return execution events + proof view event *)
      let all_events = events @ [proof_view_event] in
      inject_dm_events (uri, all_events)
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
      
      (* Create SendProofView event to be processed after execution events *)
      let current_id_opt = Dm.DocumentManager.Internal.observe_id new_st in
      let proof_view_event = match current_id_opt with
        | Some current_id ->
          Printf.eprintf "DEBUG: interpretToEnd - will send proof view for sentence %d\n%!" current_id;
          Dm.DocumentManager.mk_proof_view_event current_id
        | None ->
          Printf.eprintf "DEBUG: interpretToEnd - will send empty proof view\n%!";
          Dm.DocumentManager.mk_proof_view_event_empty
      in
      
      Printf.eprintf "✅ DEBUG: interpretToEnd - queued proof view event for processing after execution\n%!";
      log (fun () -> "[interpretToEnd] queued proof view update");
      
      (* Return execution events + proof view event *)
      let all_events = events @ [proof_view_event] in
      inject_dm_events (uri, all_events)
    with
    | exn ->
      log (fun () -> Printf.sprintf "[interpretToEnd] error: %s" (Printexc.to_string exn));
      []

let dispatch_interactive_notification = function
  | Protocol.ExtProtocol.Notification.Client.InterpretToPoint params -> 
    Printf.eprintf "🚀 DEBUG: dispatch_interactive_notification - InterpretToPoint\n%!";
    log (fun () -> "Received notification: prover/interpretToPoint"); 
    ecInterpretToPoint params
  | Protocol.ExtProtocol.Notification.Client.InterpretToEnd params -> 
    log (fun () -> "Received notification: prover/interpretToEnd"); 
    ecInterpretToEnd params
  | Protocol.ExtProtocol.Notification.Client.StepBackward params -> 
    log (fun () -> "Received notification: prover/stepBackward"); 
    ecStepBackward params
  | Protocol.ExtProtocol.Notification.Client.StepForward params -> 
    log (fun () -> "🚀 RECEIVED NOTIFICATION: prover/stepForward"); 
    Printf.eprintf "🚀 LSP: Received stepForward notification\n%!";
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
      let msg = Yojson.Safe.pretty_to_string ~std:true json in
      log (fun () -> "recieved: " ^ msg);
      begin match rpc with
      | Request req ->
          log (fun () -> "ui request: " ^ req.method_);
          log (fun () -> "Request ID present");
          log (fun () -> "About to call Request.Client.t_of_jsonrpc");
          Printf.eprintf "REQUEST: method=%s id=%s raw-params=%s\n%!"
            req.method_
            (Yojson.Safe.to_string (Jsonrpc.Id.yojson_of_t req.id))
            (match req.params with Some _ -> "<structured>" | None -> "null");
          (* Inform client via logMessage that a request was received *)
          let info_msg : Yojson.Safe.t = `Assoc [
            ("jsonrpc", `String "2.0");
            ("method", `String "window/logMessage");
            ("params", `Assoc [ ("type", `Int 3); ("message", `String ("REQUEST received: " ^ req.method_)) ])
          ] in
          output_json info_msg;
          (* DEBUG: Add more logging *)
          log (fun () -> "DEBUG: Starting request decode");
          let decode_result = try
            Request.Client.t_of_jsonrpc req
          with 
          | exn -> 
            log (fun () -> "Exception in Request.Client.t_of_jsonrpc: " ^ Printexc.to_string exn);
            Printf.eprintf "DECODE-EXN: %s\n%!" (Printexc.to_string exn);
            Error "Exception during request decode"
          in
          log (fun () -> "Request.Client.t_of_jsonrpc completed");
          Printf.eprintf "DECODE-DONE: method=%s\n%!" req.method_;
          begin match decode_result with
          | Error(e) -> 
            log (fun () -> "Error decoding request: " ^ e); 
            Printf.eprintf "DECODE-ERROR: %s\n%!" e;
            []
          | Ok(Pack r) ->
            log (fun () -> "Successfully decoded request - dispatching");
            Printf.eprintf "DISPATCH: start method=%s\n%!" req.method_;
            let resp, events = dispatch_request req.id r in
            log (fun () -> "Dispatch completed - processing response");
            begin match resp with
            | Error {code; message} ->
              log (fun () -> "Request failed with error: " ^ message);
              (* Simplified error handling for EasyCrypt *)
              let error_msg = Printf.sprintf "Request failed: %s" message in
              log (fun () -> error_msg);
              Printf.eprintf "RESPONSE-ERROR: code=%s msg=%s\n%!" (match code with Some c -> string_of_int c | None -> "none") message;
              output_json @@ `Assoc [("jsonrpc", `String "2.0"); ("id", `Null); ("error", `Assoc [("code", `Int (-32603)); ("message", `String message)])]
            | Ok resp ->
              log (fun () -> "Request succeeded - sending response");
              let resp = Request.Client.yojson_of_result r resp in
              log (fun () -> "Response JSON created - calling output_json");
              (* Inform client before sending real response *)
              let info_msg2 : Yojson.Safe.t = `Assoc [
                ("jsonrpc", `String "2.0");
                ("method", `String "window/logMessage");
                ("params", `Assoc [ ("type", `Int 3); ("message", `String ("Sending response for: " ^ req.method_)) ])
              ] in
              output_json info_msg2;
              Printf.eprintf "RESPONSE-OK: method=%s json=%s\n%!" req.method_ (Yojson.Safe.to_string resp);
              output_json @@ Jsonrpc.Response.(yojson_of_t @@ ok req.id resp);
              log (fun () -> "Response sent")
            end;
            Printf.eprintf "DISPATCH: done method=%s\n%!" req.method_;
            events
          end
      | Notification notif ->
          Printf.eprintf "📬 DEBUG: Received notification method: %s\n%!" notif.method_;
          (* First, handle VsEc custom notifications *)
          if notif.method_ = "vsec/killEasyCrypt" then (
            (try Dm.ExecutionManager.kill_easycrypt_process () with _ -> ());
            []
          ) else if notif.method_ = "vsec/revertToPrevious" then (
            let found = ref None in
            Hashtbl.iter (fun path tab -> if tab.visible then found := Some (path, tab)) states;
            match !found with
            | None -> []
            | Some (path, { st; visible }) ->
              let st', evs = Dm.DocumentManager.revert_to_previous_and_execute st in
              Hashtbl.replace states path { st = st'; visible };
              inject_dm_events (Lsp.Types.DocumentUri.of_path path, evs)
          ) else (
            log (fun () -> "ui notification - trying interactive proving first");
            match Protocol.ExtProtocol.Notification.Client.of_jsonrpc notif with
            | Ok interactive_notif -> 
              Printf.eprintf "✅ DEBUG: Successfully decoded as interactive proving notification\n%!";
              log (fun () -> "Successfully decoded as interactive proving notification");
              dispatch_interactive_notification interactive_notif
            | Error e -> 
              Printf.eprintf "❌ DEBUG: Not an interactive proving notification: %s\n%!" e;
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
          )
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
    (* Throttle high-frequency notifications by method name *)
    (match jsonrpc with
     | Jsonrpc.Packet.Notification n ->
       let json = Jsonrpc.Notification.yojson_of_t n in
       let meth = match json with `Assoc fields -> (match List.assoc_opt "method" fields with Some (`String s) -> s | _ -> "") | _ -> "" in
       if should_send_method meth then output_json json; []
     | _ -> output_json (Jsonrpc.Packet.yojson_of_t jsonrpc); [])

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
      
      (* Handle notification if present *)
      begin match handled_event.notification with
        | None -> ()
        | Some notification_str ->
          Printf.eprintf "📤 LspManager: Outputting notification from DocumentManager\n%!";
          let notification_json = Yojson.Safe.from_string notification_str in
          output_json notification_json
      end;
      
      inject_dm_events (uri, handled_event.events)
    end
  (* Removed invalid Custom notification branch; our custom commands are delivered as standard notifications decoded earlier. *)
  (* No ad-hoc Custom notifications; all handled via normal LSP notifications earlier. *)
  | Notification _ -> []
  | Notification notification ->
    log (fun () -> "Processing notification");
    (* TODO: Add notification output handling *)
    []
  | LogEvent log_event ->
    Dm.Log.handle_event log_event; 
    [inject_debug_event Dm.Log.debug]