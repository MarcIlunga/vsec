(* Extended Protocol for EasyCrypt - Simplified from VSRocq *)

(* Copy VSRocq Request module *)
module Request = struct
  module Client = struct
    
    (* EasyCrypt-specific requests can be added here later *)
    type 'a t =
    | Std : 'a Lsp.Client_request.t -> 'a t
    
    type packed = Pack : 'a t -> packed
    
    let t_of_jsonrpc (Jsonrpc.Request.{ method_; params } as req) =
      let open Lsp.Import.Result.O in
      (* For now, handle everything as standard LSP *)
      let+ E req = Lsp.Client_request.of_jsonrpc req in
      Pack (Std req)
    
    let yojson_of_result : type a. a t -> a -> Yojson.Safe.t = fun req resp ->
      match req with
      | Std req -> Lsp.Client_request.yojson_of_result req resp
  end
end