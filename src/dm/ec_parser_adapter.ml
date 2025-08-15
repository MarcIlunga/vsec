(**************************************************************************)
(*                                                                        *)
(*                                 VSec                                   *)
(*                                                                        *)
(*                     EasyCrypt Parser Adapter (skeleton)                *)
(*                                                                        *)
(*   Centralizes sentence boundary detection and basic classification.     *)
(*   Phase 1: robust fallback without EcLib.                               *)
(*   Phase 2: swap internals to EcLib.EcLexer/EcParser when wired.         *)
(*                                                                        *)
(**************************************************************************)

open Types

(* Minimal Menhir incremental parsing using EcLib.EcParser and EcLib.EcLexer *)
module P = EcLib.EcParser
module I = EcLib.EcParser.MenhirInterpreter

let is_word_char = function
  | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' | '\'' -> true
  | _ -> false

let sentence_terminator = '.'

let scan_sentence_end text start =
  let len = String.length text in
  let in_string = ref false in
  let comment_depth = ref 0 in
  let i = ref start in
  let next () = incr i in
  let peek k = if k < len then Some text.[k] else None in
  let rec loop () =
    if !i >= len then len else
    match (!in_string, !comment_depth, peek !i, peek (!i + 1)) with
    | false, 0, Some '"', _ -> in_string := true; next (); loop ()
    | true,  _, Some '"', _ -> in_string := false; next (); loop ()
    | false, d, Some '(', Some '*' -> comment_depth := d + 1; i := !i + 2; loop ()
    | false, d, Some '*', Some ')' when d > 0 -> comment_depth := d - 1; i := !i + 2; loop ()
    | false, 0, Some c, _ when c = sentence_terminator -> !i + 1
    | _,     _, Some _ , _ -> next (); loop ()
    | _,     _, None  , _ -> len
  in
  loop ()

let naive_tokenize (s : string) : string list =
  let re = Str.regexp "[ \t().,;:]+" in
  Str.split re s

let classify_sentence (s : string) : EasyCryptClassification.classification =
  EasyCryptClassification.classify_string s

let find_sentence_end_and_classify ~text ~start =
  let start = max 0 start in
  let stop = scan_sentence_end text start in
  let sent = String.sub text start (max 0 (stop - start)) |> String.trim in
  (* Try EcLib lexer-based classification first *)
  let classif =
    let open EasyCryptClassification in
    let classify_tokens (toks : EcLib.EcParser.token list) =
      let open EcLib.EcParser in
      let rec has p = function | [] -> false | x :: xs -> p x || has p xs in
      if has (function LEMMA | AXIOM -> true | _ -> false) toks then EcDefinition
      else if has (function MODULE | THEORY -> true | _ -> false) toks then EcModule
      else if has (function PROOF | QED | APPLY | REWRITE | SIMPLIFY | AUTO | SPLIT | LEFT | RIGHT | CASE | ELIM -> true | _ -> false) toks then EcProofStep
      else EcOther
    in
    try
      let toks = EcLib.EcLexer.main (Lexing.from_string sent) in
      classify_tokens toks
    with _ -> classify_sentence sent
  in
  let tokens = naive_tokenize sent in
  (stop, classif, tokens)

(* Parse one EcParsetree.prog node starting at [start] using Menhir incremental API. *)
let _parse_one_prog (_text : string) (start : int) : (int * EcLib.EcParsetree.prog option) =
  let slice = String.sub _text start (String.length _text - start) in
  let lexbuf = Lexing.from_string slice in
  let rec loop checkpoint =
    match checkpoint with
    | I.InputNeeded _env ->
        let token = EcLib.EcLexer.main lexbuf in
        begin match token with
        | [] ->
            (* Provide EOF to finish if no tokens *)
            let (tok, sp, ep) = (P.EOF, Lexing.lexeme_start_p lexbuf, Lexing.lexeme_end_p lexbuf) in
            loop (I.offer checkpoint (tok, sp, ep))
        | tok :: _ ->
            (* Feed single token; lexer already advanced lexbuf *)
            let sp = Lexing.lexeme_start_p lexbuf in
            let ep = Lexing.lexeme_end_p lexbuf in
            loop (I.offer checkpoint (tok, sp, ep))
        end
    | I.Shifting _ | I.AboutToReduce _ -> loop (I.resume checkpoint)
    | I.Accepted ast ->
        let consumed = lexbuf.Lexing.lex_curr_p.Lexing.pos_cnum in
        (start + consumed, Some ast)
    | I.HandlingError _ ->
        let consumed = lexbuf.Lexing.lex_curr_p.Lexing.pos_cnum in
        (start + consumed, None)
    | I.Rejected -> (start, None)
  in
  loop (P.Incremental.prog lexbuf.Lexing.lex_curr_p)


