open Dm

let%test_unit "menhir incremental consumes bytes on lemma" =
  let text = "lemma y: true.\n" in
  let start = 0 in
  let stop, _ast = Ec_parser_adapter._parse_one_prog text start in
  assert (stop > start)


