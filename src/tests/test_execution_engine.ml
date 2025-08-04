(* Test EasyCrypt execution engine integration *)
open Dm
open Types
open Scheduler

let create_test_sentence id ast =
  { Scheduler.id = Stateid.fresh ();
    ast;
    synterp = EcLib.EcScope.empty;
    error_recovery = RSkip }

let%test_unit "execute_skip_task" =
  (* Test skipping execution *)
  let initial_state = ExecutionManager.init EcLib.EcScope.empty in
  let id = Stateid.fresh () in
  let task = PSkip id in
  let vs = EcLib.EcScope.empty in
  let st, new_vs, _, interrupted = 
    ExecutionManager.execute initial_state (vs, [], false) task in
  (* Should mark as success *)
  assert (ExecutionManager.is_executed st id);
  (* State should not change *)
  assert (new_vs == vs);
  (* Should not be interrupted *)
  assert (not interrupted)

let%test_unit "execute_query" =
  (* Test executing a query *)
  let initial_state = ExecutionManager.init EcLib.EcScope.empty in
  let ast = 
    let open EcLib.EcParsetree in
    { gl_action = EcLib.EcLocation.mk_loc EcLib.EcLocation.dummy 
        (Gprint (Pr_any (EcLib.EcLocation.mk_loc EcLib.EcLocation.dummy ([], "test"))));
      gl_debug = None } in
  let sentence = create_test_sentence (Stateid.fresh ()) ast in
  let task = PQuery sentence in
  let vs = EcLib.EcScope.empty in
  let st, new_vs, _, interrupted = 
    ExecutionManager.execute initial_state (vs, [], false) task in
  (* Should mark as success *)
  assert (ExecutionManager.is_executed st sentence.id);
  (* State should not change for queries *)
  assert (new_vs == vs);
  assert (not interrupted)

let%test_unit "execute_with_error" =
  (* Test execution that produces an error *)
  let initial_state = ExecutionManager.init EcLib.EcScope.empty in
  let ast = 
    let open EcLib.EcParsetree in
    (* Create an invalid global that will cause an error *)
    { gl_action = EcLib.EcLocation.mk_loc EcLib.EcLocation.dummy 
        (Glemma []); (* Empty lemma list should cause error *)
      gl_debug = None } in
  let sentence = create_test_sentence (Stateid.fresh ()) ast in
  let task = PExec sentence in
  let vs = EcLib.EcScope.empty in
  let st, new_vs, _, interrupted = 
    ExecutionManager.execute initial_state (vs, [], false) task in
  (* Should be executed (even if with error) *)
  assert (ExecutionManager.is_executed st sentence.id);
  (* Check that we have an error *)
  let errors = ExecutionManager.errors st in
  assert (List.exists (fun (id, _) -> id = sentence.id) errors);
  assert (not interrupted)

let%test_unit "build_tasks_for_sentence" =
  (* Test building tasks for a sentence *)
  let initial_state = ExecutionManager.init EcLib.EcScope.empty in
  let id = Stateid.fresh () in
  let ast = 
    let open EcLib.EcParsetree in
    { gl_action = EcLib.EcLocation.mk_loc EcLib.EcLocation.dummy 
        (Gtype []);
      gl_debug = None } in
  let ex_sentence = { Scheduler.id; ast; synterp = EcLib.EcScope.empty; error_recovery = RSkip } in
  let schedule = { document_scope = [id]; proof_blocks = [] } in
  let sch = SM.singleton id (None, Exec ex_sentence) in
  let vs, tasks = ExecutionManager.build_tasks_for sch initial_state id in
  (* Should have one task *)
  assert (List.length tasks = 1);
  (* Should start from initial state *)
  assert (vs == initial_state.initial)

let%test_unit "interrupted_execution" =
  (* Test that interrupted execution doesn't process *)
  let initial_state = ExecutionManager.init EcLib.EcScope.empty in
  let id = Stateid.fresh () in
  let task = PSkip id in
  let vs = EcLib.EcScope.empty in
  let st, new_vs, _, interrupted = 
    ExecutionManager.execute initial_state (vs, [], true) task in (* interrupted = true *)
  (* Should not mark as executed *)
  assert (not (ExecutionManager.is_executed st id));
  (* Should remain interrupted *)
  assert interrupted

let%test_unit "invalidate_executed_sentence" =
  (* Test invalidating an executed sentence *)
  let initial_state = ExecutionManager.init EcLib.EcScope.empty in
  let id = Stateid.fresh () in
  (* First execute *)
  let task = PSkip id in
  let vs = EcLib.EcScope.empty in
  let st, _, _, _ = ExecutionManager.execute initial_state (vs, [], false) task in
  assert (ExecutionManager.is_executed st id);
  (* Now invalidate *)
  let schedule = { document_scope = [id]; proof_blocks = [] } in
  let st' = ExecutionManager.invalidate schedule id st in
  assert (not (ExecutionManager.is_executed st' id))

let%test_unit "feedback_collection" =
  (* Test that feedback is collected *)
  let initial_state = ExecutionManager.init EcLib.EcScope.empty in
  let id = Stateid.fresh () in
  (* Add some feedback *)
  Queue.add (id, (Severity.Warning, None, "Test warning")) initial_state.sel_feedback_queue;
  (* Process local feedback event *)
  let event = ExecutionManager.LocalFeedback (id, (Severity.Warning, None, "Test warning")) in
  let st = match event with
    | LocalFeedback (sid, msg) ->
      let st = initial_state in
      { st with of_sentence = 
        SM.update sid (function
          | None -> (Done (Success None), [msg])
          | Some (status, msgs) -> (status, msg :: msgs)) st.of_sentence }
    | _ -> initial_state in
  (* Check feedback was recorded *)
  let feedback = ExecutionManager.feedback st in
  assert (List.exists (fun (fid, (sev, _, msg)) -> 
    fid = id && sev = Severity.Warning && msg = "Test warning") feedback)

let%test_unit "proof_state_management" =
  (* Test classification of proof-related globals *)
  let open EcLib.EcParsetree in
  let make_global desc = 
    { gl_action = EcLib.EcLocation.mk_loc EcLib.EcLocation.dummy desc;
      gl_debug = None } in
  
  (* Lemma starts proof *)
  assert (Document.Internal.classify_global (make_global (Glemma [])) = VtStartProof);
  (* Tactics are proof steps *)
  assert (Document.Internal.classify_global (make_global (Gtactics `Proof)) = VtProofStep);
  (* Qed ends proof *)
  assert (Document.Internal.classify_global (make_global (Gsave (EcLib.EcLocation.mk_loc EcLib.EcLocation.dummy `Qed))) = VtQed VtKeepOpaque);
  (* Admit drops proof *)
  assert (Document.Internal.classify_global (make_global (Gsave (EcLib.EcLocation.mk_loc EcLib.EcLocation.dummy `Admit))) = VtQed VtDrop)