let%test_unit "adapter AST identifies lemma name in global action" =
  let text = "lemma a: true.\n" in
  let stop, ast_opt = Dm.Ec_parser_adapter._parse_one_prog text 0 in
  assert (stop > 0);
  match ast_opt with
  | None -> assert false
  | Some prog ->
    let open EcLib in
    let open EcParsetree in
    match EcLocation.unloc prog with
    | P_Prog (g :: _, _) ->
      begin match EcLocation.unloc g.gl_action with
      | Gaxiom ax -> assert (EcLocation.unloc ax.pa_name = "a")
      | _ -> assert false
      end
    | _ -> assert false


