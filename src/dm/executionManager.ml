(**************************************************************************)
(*                                                                        *)
(*                                 VSCoq                                  *)
(*                                                                        *)
(*                   Copyright INRIA and contributors                     *)
(*       (see version control and README file for authors & dates)        *)
(*                                                                        *)
(**************************************************************************)
(*                                                                        *)
(*   This file is distributed under the terms of the MIT License.         *)
(*   See LICENSE file.                                                    *)
(*                                                                        *)
(**************************************************************************)

open Scheduler
open Types
open EcLib
open Lsp.LspData

let Log log = Log.mk_log "executionManager"

type execution_status =
  | Success of Vernacstate.t option
  | Error of string EcLocation.located * Vernacstate.t option (* State to use for resiliency *)

let success vernac_st = Success (Some vernac_st)
let error loc msg vernac_st = Error ({pl_loc = loc; pl_desc = msg},(Some vernac_st))

module SM = Map.Make (Stateid)

type feedback_message = Severity.t * EcLocation.t option * string

type sentence_state = Done of execution_status

let doc_id = ref (-1)
let fresh_doc_id () = incr doc_id; !doc_id

type document_id = int

type coq_feedback_listener = int

type state = {
  initial : Vernacstate.t;
  of_sentence : (sentence_state * feedback_message list) SM.t;

  (* ugly stuff to correctly dispatch Coq feedback *)
  doc_id : document_id; (* unique number used to interface with Coq's Feedback *)
  coq_feeder : coq_feedback_listener;
  sel_feedback_queue : (sentence_id * (Severity.t * EcLocation.t option * string)) Queue.t;
  sel_cancellation_handle : Sel.cancellation_handle;
}


type prepared_task =
  | PSkip of sentence_id
  | PExec of executable_sentence
  | PQuery of executable_sentence

module ProofJob = struct
  type update_request =
    | UpdateExecStatus of sentence_id * execution_status
    | AppendFeedback of Types.sentence_id * (Severity.t * EcLocation.t option * string)
  let appendFeedback sid fb = AppendFeedback(sid,fb)

  type t = {
    tasks : prepared_task list;
    initial_vernac_state : Vernacstate.t;
    doc_id : int;
    terminator_id : sentence_id;
  }
  let name = "proof"
  let binary_name = "vscoqtop_proof_worker.opt"
  let initial_pool_size = 1

end

type event =
  | LocalFeedback of sentence_id * (Severity.t * EcLocation.t option * string)
  | ProofEvent of ProofJob.t
type events = event Sel.event list
let pr_event = function
  | LocalFeedback _ -> "feedback"
  | ProofEvent _ -> "proof"

let inject_proof_event = Sel.map (fun x -> ProofEvent x)
let inject_proof_events st l =
  (st, List.map inject_proof_event l)

let update_all id v fl state =
  { state with of_sentence = SM.add id (v, fl) state.of_sentence }
;;
let update state id v =
  let fl = try snd (SM.find id state.of_sentence) with Not_found -> [] in
  update_all id (Done v) fl state
;;

let local_feedback feedback_queue : event Sel.event * Sel.cancellation_handle =
  let e, c = Sel.on_queue feedback_queue (fun (sid,msg) -> LocalFeedback(sid,msg)) in
  e |> Sel.name "feedback"
    |> Sel.make_recurring
    |> Sel.set_priority PriorityManager.feedback,
  c

let install_feedback_listener doc_id send = 0
  (* let open Feedback in
  add_feeder (fun fb ->
    match fb.contents with
    | _ -> () (* STM feedbacks are handled differently *)) *)

let init vernac_state =
  let doc_id = fresh_doc_id () in
  let sel_feedback_queue = Queue.create () in
  let coq_feeder = install_feedback_listener doc_id (fun x -> Queue.push x sel_feedback_queue) in
  let event, sel_cancellation_handle = local_feedback sel_feedback_queue in
  {
    initial = vernac_state;
    of_sentence = SM.empty;
    doc_id;
    coq_feeder;
    sel_feedback_queue;
    sel_cancellation_handle;
  },
  event

let handle_feedback id fb state =
  match fb with
  | (Severity.Info, _, _) -> state
  | (_, _, msg) ->
    begin match SM.find id state.of_sentence with
    | (s,fl) -> update_all id s (fb::fl) state
    | exception Not_found -> 
        log @@ "Received feedback on non-existing state id " ^ Stateid.to_string id ^ ": ";
        state
    end

let handle_event event state =
  match event with
  | LocalFeedback (id,fb) ->
      Some (handle_feedback id fb state), []
  | ProofEvent event -> 
    Some state, []

let find_fulfilled_opt x m =
  try
    let ss,_ = SM.find x m in
    match ss with
    | Done x -> Some x
  with Not_found -> None

let jobs : ProofJob.t Queue.t = Queue.create ()

let rec last = function
| [] -> failwith "List.last"
| hd :: [] -> hd
| _ :: tl -> last tl

let last_opt l = try Some (last l).id with Failure _ -> None

let prepare_task task : prepared_task list =
  match task with
  | Skip id -> [PSkip id]
  | Exec e -> [PExec e]
  | Query e -> [PQuery e]
  | OpaqueProof { terminator; opener_id; tasks} ->
    log "running the proof in master as per config";
    List.map (fun x -> PExec x) tasks @ [PExec terminator]

let id_of_prepared_task = function
  | PSkip id -> id
  | PExec ex -> ex.id
  | PQuery ex -> ex.id

let purge_state = function
  | Success _ -> Success None
  | Error(e,_) -> Error (e,None)

let execute (st : state) ((vs, events, interrupted) : Vernacstate.t * events * bool) (task : prepared_task)  =
  (st, vs, events, true)

let build_tasks_for sch st id =
  let rec build_tasks id tasks =
    begin match find_fulfilled_opt id st.of_sentence with
    | Some (Success (Some vs)) ->
      (* We reached an already computed state *)
      log @@ "Reached computed state " ^ Stateid.to_string id;
      vs, tasks
    | Some (Error(_,Some vs)) ->
      (* We try to be resilient to an error *)
      log @@ "Error resiliency on state " ^ Stateid.to_string id;
      vs, tasks
    | _ ->
      log @@ "Non (locally) computed state " ^ Stateid.to_string id;
      let (base_id, task) = task_for_sentence sch id in
      begin match base_id with
      | None -> (* task should be executed in initial state *)
        st.initial, task :: tasks
      | Some base_id ->
        build_tasks base_id (task::tasks)
      end
    end
  in
  let vs, tasks = build_tasks id [] in
  vs, List.concat_map prepare_task tasks

let errors st =
  List.fold_left (fun acc (id, (p,_)) ->
    match p with
    | Done (Error ({pl_loc; pl_desc},_st)) -> (id, (Some(pl_loc), pl_desc)) :: acc
    | _ -> acc)
    [] @@ SM.bindings st.of_sentence

let mk_feedback id (lvl,loc,msg) = (id,(lvl,loc,msg))

let feedback st =
  List.fold_left (fun acc (id, (_,l)) -> List.map (mk_feedback id) l @ acc) [] @@ SM.bindings st.of_sentence

let shift_locs st pos offset =
  (* FIXME shift loc in feedback *)
  let shift_error (p,r as orig) = match p with
  | Done (Error (loc,st)) ->
    (* let (start,stop) = EcLocation.unloc loc in
    if start >= pos then ((Done (Error ((Some (Loc.shift_loc offset offset loc),e),st))),r)
    else if stop >= pos then ((Done (Error ((Some (Loc.shift_loc 0 offset loc),e),st))),r)
    else  *)
      orig
  | _ -> orig
  in
  { st with of_sentence = SM.map shift_error st.of_sentence }

let executed_ids st =
  SM.fold (fun id (p,_) acc ->
    match p with
    | Done _ -> id :: acc) st.of_sentence []

let is_executed st id =
  match find_fulfilled_opt id st.of_sentence with
  | Some (Success (Some _) | Error (_,Some _)) -> true
  | _ -> false

let is_remotely_executed st id =
  match find_fulfilled_opt id st.of_sentence with
  | Some (Success None | Error (_,None)) -> true
  | _ -> false

let invalidate1 of_sentence id =
  try
    let p,_ = SM.find id of_sentence in
    match p with
    | _ -> SM.remove id of_sentence
  with Not_found -> of_sentence

let rec invalidate schedule id st =
  log @@ "Invalidating: " ^ Stateid.to_string id;
  let of_sentence = invalidate1 st.of_sentence id in
  let old_jobs = Queue.copy jobs in
  let removed = ref [] in
  Queue.clear jobs;
  Queue.iter (fun (({ ProofJob.terminator_id; tasks }) as job) ->
    if terminator_id != id then
      Queue.push job jobs
    else begin
      removed := tasks :: !removed
    end) old_jobs;
  let of_sentence = List.fold_left invalidate1 of_sentence
    List.(concat (map (fun tasks -> map id_of_prepared_task tasks) !removed)) in
  if of_sentence == st.of_sentence then st else
  let deps = Scheduler.dependents schedule id in
  StateidSet.fold (invalidate schedule) deps { st with of_sentence }

(* let get_proof st id =
  match find_fulfilled_opt id st.of_sentence with
  | None -> log "Cannot find state for proof"; None
  | Some (Error _) -> log "Proof requested in error state"; None
  | Some (Success None) -> log "Proof requested in a remotely checked state"; None
  | Some (Success (Some _)) -> log "Proof requested in a state with no proof"; None

let get_proofview st id = Option.map Proof.data (get_proof st id)

let get_lemmas sigma env =
  let open CompletionItems in
  let results = ref [] in
  let display ref _kind env c =
    results := mk_completion_item sigma ref env c :: results.contents;
  in
  Search.generic_search env display;
  results.contents

let get_context st id =
  match find_fulfilled_opt id st.of_sentence with
  | None -> log "Cannot find state for get_context"; None
  | Some (Error _) -> log "Context requested in error state"; None
  | Some (Success None) -> log "Context requested in a remotely checked state"; None
  | Some (Success (Some { interp = { Vernacstate.Interp.lemmas = Some st; _ } })) ->
    let open Declare in
    let open Vernacstate in
    st |> LemmaStack.with_top ~f:Proof.get_current_context |> Option.make
  | Some (Success (Some { interp = st })) ->
    Vernacstate.Interp.unfreeze_interp_state st;
    let env = Global.env () in
    let sigma = Evd.from_env env in
    Some (sigma, env)
 *)

