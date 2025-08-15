open Dm

let%test_unit "record_outline extracts definition name without punctuation" =
  let text = "lemma my_lemma: true.\n" in
  let gstate = EcLib.EcGState.create () in
  let scope = EcLib.EcScope.empty gstate in
  let doc0 = Document.create_document scope text in
  let doc1, events0 = Document.validate_document doc0 in
  let rec process doc evs =
    match evs with
    | [] -> doc
    | ev :: rest ->
      let doc', new_events, parsing_end = Document.handle_event doc ev in
      let doc_final = match parsing_end with
        | Some { parsed_document; _ } -> parsed_document
        | None -> doc'
      in
      let rest' = rest @ (List.map (fun e -> e) new_events) in
      process doc_final rest'
  in
  let parsed_doc = process doc1 events0 in
  let outline = Document.outline parsed_doc in
  let names = List.map (fun (e : Document.outline_element) -> e.name) outline in
  assert (List.exists ((=) "my_lemma") names)


