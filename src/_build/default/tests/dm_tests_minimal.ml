open Base
open Dm
open Lsp
open Common

let uri = Uri.make ~scheme:"file" ~path:"foo" ()
let init text = openDoc uri ~text

let%test_unit "basic_test" =
  let st, events = init "Definition x := true." in
  let st = DocumentManager.validate_document st in
  check_no_diag st;