open Printf

let () =
  printf "🧪 Testing Document Parsing\n";
  printf "===========================\n\n";
  
  (* Configure load path *)
  let theories_paths = EcLib.EcDuneSites.Sites.theories in
  List.iter (fun theory ->
    let prelude = Filename.concat theory "prelude" in
    EcLib.EcCommands.addidir ~namespace:`System prelude;
    EcLib.EcCommands.addidir ~namespace:`System ~recursive:true theory
  ) theories_paths;
  printf "✅ Configured %d theory paths\n" (List.length theories_paths);
  
  (* Initialize EasyCrypt *)
  let checkmode = {
    EcLib.EcCommands.cm_checkall = false;
    cm_timeout = 5;
    cm_cpufactor = 1;
    cm_nprovers = 1;
    cm_provers = None;
    cm_profile = false;
    cm_iterate = false;
  } in
  
  let init_scope = EcLib.EcCommands.initial ~checkmode ~boot:false in
  printf "✅ Initial scope created\n";
  
  (* Test document parsing directly *)
  printf "\n📋 Test: Document Parsing\n";
  printf "-------------------------\n";
  
  let test_doc_text = "lemma test_hyp (P Q : bool): P => Q => P /\\ Q.\nproof.\n  move=> H_P H_Q.\nqed." in
  let uri = Lsp.Types.DocumentUri.of_string "file:///test.ec" in
  
  (* Create document manager state (which handles parsing automatically) *)
  let doc_st, events = Dm.DocumentManager.init init_scope uri ~text:test_doc_text in
  printf "✅ Document created with %d events\n" (List.length events);
  
  (* The initial events should trigger parsing automatically *)
  printf "✅ Initial events should trigger parsing\n";
  
  (* Check if document has sentences *)
  let sentences = Dm.Document.sentences doc_st.document in
  printf "   Sentences in document: %d\n" (List.length sentences);
  
  if List.length sentences = 0 then (
    printf "❌ Document parsing failed - no sentences found\n";
    printf "   This explains why step forward generates 0 events\n"
  ) else (
    printf "✅ Document parsing successful\n";
    List.iteri (fun i sent ->
      let text = Dm.Document.Internal.string_of_sentence sent in
      printf "   Sentence %d: %s\n" i (String.sub text 0 (min 50 (String.length text)))
    ) sentences
  );
  
  printf "\n🎉 Document Parsing Test Complete\n"
