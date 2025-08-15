open Dm

let%test_unit "outline-backed completion basic" =
  let text = "lemma t: true.\n" in
  let gstate = EcLib.EcGState.create () in
  let scope = EcLib.EcScope.empty gstate in
  let doc0 = Document.create_document scope text in
  let doc1, events0 = Document.validate_document doc0 in
  (* Process parsing events to completion *)
  let rec process doc evs =
    match evs with
    | [] -> doc
    | ev :: rest ->
      let doc', new_events, parsing_end = Document.handle_event doc ev in
      let doc_final = match parsing_end with
        | Some { parsed_document; _ } -> parsed_document
        | None -> doc'
      in
      (* Flatten next events and continue *)
      let rest' = rest @ (List.map (fun e -> e) new_events) in
      process doc_final rest'
  in
  let parsed_doc = process doc1 events0 in
  let outline = Document.outline parsed_doc in
  let has_t = List.exists (fun (e : Document.outline_element) -> e.name = "t") outline in
  assert has_t


