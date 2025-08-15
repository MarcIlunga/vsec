(**************************************************************************)
(*                                                                        *)
(*                                 VSec                                   *)
(*                                                                        *)
(*                     EasyCrypt Parser Adapter (skeleton)                *)
(*                                                                        *)
(*   Goal: Centralize all parsing via EcLib when available,               *)
(*         with safe fallbacks to current logic.                          *)
(*                                                                        *)
(*   This adapter intentionally avoids direct references to EcLib parser   *)
(*   entry points for now to keep the code buildable in environments       *)
(*   without EasyCrypt development headers. It provides a single API the   *)
(*   Document Manager can call. Later we will route these to EcLib.        *)
(*                                                                        *)
(**************************************************************************)

open Types

val find_sentence_end_and_classify
  :  text:string
  -> start:int
  -> (int * EasyCryptClassification.classification * string list)
(** Given the full document text and a starting offset, returns:
    (end_offset, classification, tokens)
    - end_offset is an absolute index in [text] for the sentence terminator
    - classification is an EasyCrypt command class
    - tokens is a lightweight token list (temporary placeholder)

    Fallback behavior: robustly finds a period outside strings/comments. *)

val _parse_one_prog : string -> int -> (int * EcLib.EcParsetree.prog option)
(** Parse one EcParsetree.prog starting at [start] and return new absolute
    position and optional parsed AST. Experimental; subject to change. *)


