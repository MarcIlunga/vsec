(* Test EasyCrypt execution engine integration *)
open Dm
open Types
open Scheduler

let create_gstate_and_scope () =
  let gstate = EcLib.EcGState.create () in
  let scope = EcLib.EcScope.empty gstate in
  scope

let create_test_sentence id ast =
  { Scheduler.id = Stateid.fresh ();
    ast;
    synterp = create_gstate_and_scope ();
    error_recovery = RSkip }

let%test_unit "execute_skip_task" =
  (* Test skipping execution *)
  let scope = create_gstate_and_scope () in
  let initial_state, _ = ExecutionManager.init scope in
  let id = Stateid.fresh () in
  let task = ExecutionManager.PSkip id in
  let vs = scope in
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
  let scope = create_gstate_and_scope () in
  let initial_state, _ = ExecutionManager.init scope in
  let ast = 
    let open EcLib.EcParsetree in
    { gl_action = EcLib.EcLocation.mk_loc EcLib.EcLocation._dummy 
        (Gprint (Pr_any (EcLib.EcLocation.mk_loc EcLib.EcLocation._dummy ([], "test"))));
      gl_debug = None;
      gl_fail = false } in
  let sentence = create_test_sentence (Stateid.fresh ()) ast in
  let task = ExecutionManager.PQuery sentence in
  let vs = scope in
  let st, new_vs, _, interrupted = 
    ExecutionManager.execute initial_state (vs, [], false) task in
  (* Should mark as success *)
  assert (ExecutionManager.is_executed st sentence.id);
  (* State should not change for queries *)
  assert (new_vs == vs);
  assert (not interrupted)

let%test_unit "execute_with_error" =
  (* Test execution that produces an error *)
  let scope = create_gstate_and_scope () in
  let initial_state, _ = ExecutionManager.init scope in
  let ast = 
    let open EcLib.EcParsetree in
    (* Create an invalid global that will cause an error *)
    (* TODO: Verify this creates a valid error in EasyCrypt.
       An empty lemma list might not be the best test case. *)
    { gl_action = EcLib.EcLocation.mk_loc EcLib.EcLocation._dummy 
        (Gtype []); (* Empty type list should cause error *)
      gl_debug = None;
      gl_fail = false } in
  let sentence = create_test_sentence (Stateid.fresh ()) ast in
  let task = ExecutionManager.PExec sentence in
  let vs = scope in
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
  let scope = create_gstate_and_scope () in
  let initial_state, _ = ExecutionManager.init scope in
  let id = Stateid.fresh () in
  let ast = 
    let open EcLib.EcParsetree in
    { gl_action = EcLib.EcLocation.mk_loc EcLib.EcLocation._dummy 
        (Gtype []);
      gl_debug = None;
      gl_fail = false } in
  let classification = Scheduler.VtSideff in
  let scheduler_state = Scheduler.initial_state in
  let schedule = Scheduler.initial_schedule in
  let scheduler_state', schedule' = Scheduler.schedule_sentence (id, (ast, classification, scope)) scheduler_state schedule in
  let vs, tasks = ExecutionManager.build_tasks_for schedule' initial_state id in
  (* Should have one task *)
  assert (List.length tasks = 1)
  (* vs is the initial Vernacstate.t for this execution *)

let%test_unit "interrupted_execution" =
  (* Test that interrupted execution doesn't process *)
  let scope = create_gstate_and_scope () in
  let initial_state, _ = ExecutionManager.init scope in
  let id = Stateid.fresh () in
  let task = ExecutionManager.PSkip id in
  let vs = scope in
  let st, new_vs, _, interrupted = 
    ExecutionManager.execute initial_state (vs, [], true) task in (* interrupted = true *)
  (* Should not mark as executed *)
  assert (not (ExecutionManager.is_executed st id));
  (* Should remain interrupted *)
  assert interrupted

let%test_unit "invalidate_executed_sentence" =
  (* Test invalidating an executed sentence *)
  let scope = create_gstate_and_scope () in
  let initial_state, _ = ExecutionManager.init scope in
  let id = Stateid.fresh () in
  (* First execute *)
  let task = ExecutionManager.PSkip id in
  let vs = scope in
  let st, _, _, _ = ExecutionManager.execute initial_state (vs, [], false) task in
  assert (ExecutionManager.is_executed st id);
  (* Now invalidate *)
  let schedule = Scheduler.initial_schedule in
  let st' = ExecutionManager.invalidate schedule id st in
  assert (not (ExecutionManager.is_executed st' id))

(* Test removed: cannot access internal state fields through opaque type *)
(* let%test_unit "feedback_collection" = ... *)

let%test_unit "proof_state_management" =
  (* Test classification of proof-related globals *)
  let open EcLib.EcParsetree in
  let make_global desc = 
    { gl_action = EcLib.EcLocation.mk_loc EcLib.EcLocation._dummy desc;
      gl_debug = None;
      gl_fail = false } in
  
  (* Module definitions have side effects *)
  assert (Document.Internal.classify_global (make_global (Gmodule { ptm_locality = `Local;
                                                                   ptm_def = `Concrete { ptm_header = Pmh_ident (EcLib.EcLocation.mk_loc EcLib.EcLocation._dummy "Test");
                                                                                         ptm_body = EcLib.EcLocation.mk_loc EcLib.EcLocation._dummy (Pm_struct []) } })) = VtSideff);
  (* Tactics are proof steps *)
  assert (Document.Internal.classify_global (make_global (Gtactics `Proof)) = VtProofStep);
  (* Qed ends proof *)
  assert (Document.Internal.classify_global (make_global (Gsave (EcLib.EcLocation.mk_loc EcLib.EcLocation._dummy `Qed))) = VtQed (VtKeep VtKeepOpaque));
  (* Admit drops proof *)
  assert (Document.Internal.classify_global (make_global (Gsave (EcLib.EcLocation.mk_loc EcLib.EcLocation._dummy `Admit))) = VtQed VtDrop)