open Dm

let%test_unit "adapter finds end and classifies simple lemma" =
  let text = "lemma x: true.\n" in
  let start = 0 in
  let stop, _classif, tokens = Ec_parser_adapter.find_sentence_end_and_classify ~text ~start in
  assert (stop > start);
  assert (List.length tokens > 0);
  assert (_classif = Types.EasyCryptClassification.EcDefinition)


