(* Extended Protocol for EasyCrypt - Adapted from VSRocq *)
open Lsp.Types
open LspWrapper

(* EasyCrypt-specific execution status *)
type execution_status = 
  | Executed
  | Parsing_Error of string
  | Execution_Error of string

(* EasyCrypt sentence status for navigation *)
type sentence_status = {
  id: int;
  status: execution_status;
}

(* Step forward request - EasyCrypt specific navigation *)
module StepForward = struct
  type params = {
    textDocument: TextDocumentIdentifier.t;
    position: Position.t;
  }

  type result = {
    newPosition: Position.t option;
    status: sentence_status;
  }
end

(* Step backward request *)
module StepBackward = struct
  type params = {
    textDocument: TextDocumentIdentifier.t;
    position: Position.t;
  }

  type result = {
    newPosition: Position.t option;
    status: sentence_status;
  }
end

(* Interpret to point request *)
module InterpretToPoint = struct
  type params = {
    textDocument: TextDocumentIdentifier.t;
    position: Position.t;
  }

  type result = {
    interpretedUntil: Position.t;
    statuses: sentence_status list;
  }
end