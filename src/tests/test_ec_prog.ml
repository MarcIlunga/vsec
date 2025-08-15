let%test_unit "_parse_one_prog returns AST for lemma" =
  let text = "lemma z: true.\n" in
  let stop, ast_opt = Dm.Ec_parser_adapter._parse_one_prog text 0 in
  assert (stop > 0);
  assert (ast_opt <> None)


