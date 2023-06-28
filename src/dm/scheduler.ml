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

open Types

let Log log = Log.mk_log "scheduler"

module SM = Map.Make (Stateid)

type vernac_keep_as = VtKeepAxiom | VtKeepDefined | VtKeepOpaque

type vernac_qed_type = VtKeep of vernac_keep_as | VtDrop

type vernac_classification =
  (* Start of a proof *)
  | VtStartProof 
  (* Command altering the global state, bad for parallel
     processing. *)
  | VtSideff 
  (* End of a proof *)
  | VtQed of vernac_qed_type
  (* A proof step *)
  | VtProofStep 
  (* Queries are commands assumed to be "pure", that is to say, they
     don't modify the interpretation state. *)
  | VtQuery

type error_recovery_strategy =
  | RSkip
  | RAdmitted

type executable_sentence = {
  id : sentence_id;
  ast : unit (* Synterp.vernac_control_entry *);
  synterp : unit(* Vernacstate.Synterp.t *);
  error_recovery : error_recovery_strategy;
}

type task =
  | Skip of sentence_id
  | Exec of executable_sentence
  | OpaqueProof of { terminator: executable_sentence;
                     opener_id: sentence_id;
                     tasks : executable_sentence list; (* non empty list *)
                   }
  | Query of executable_sentence

(*
  | SubProof of ast list
  | ModuleWithSignature of ast list
*)
type proof_block = {
  proof_sentences : executable_sentence list;
  opener_id : sentence_id;
}

type state = {
  document_scope : sentence_id list; (* List of sentences whose effect scope is the document that follows them *)
  proof_blocks : proof_block list; (* List of sentences whose effect scope ends with the Qed *)
  section_depth : int; (* Statically computed section nesting *)
}

let initial_state = {
  document_scope = [];
  proof_blocks = [];
  section_depth = 0;
}

type schedule = {
  tasks : (sentence_id option * task) SM.t;
  dependencies : StateidSet.t SM.t;
}

let initial_schedule = {
  tasks = SM.empty;
  dependencies = SM.empty;
}

let push_executable_proof_sentence ex_sentence block =
  { block with proof_sentences = ex_sentence :: block.proof_sentences }

let push_ex_sentence ex_sentence st =
  match st.proof_blocks with
  | [] -> { st with document_scope = ex_sentence.id :: st.document_scope }
  | l::q -> { st with proof_blocks = push_executable_proof_sentence ex_sentence l :: q }

(* Not sure what the base_id for nested lemmas should be, e.g.
Lemma foo : X.
Proof.
Definition x := True.
intros ...
Lemma bar : Y. <- What should the base_id be for this command? -> 83
*)
let base_id st =
  let rec aux = function
  | [] -> (match st.document_scope with hd :: _ -> Some hd | [] -> None)
  | block :: l ->
    begin match block.proof_sentences with
    | [] -> aux l
    | ex_sentence :: _ -> Some ex_sentence.id
    end
  in
  aux st.proof_blocks

let open_proof_block ex_sentence st =
  let st = push_ex_sentence ex_sentence st in
  let block = { proof_sentences = []; opener_id = ex_sentence.id } in
  { st with proof_blocks = block :: st.proof_blocks }

let extrude_side_effect ex_sentence st =
  let document_scope = ex_sentence.id :: st.document_scope in
  let proof_blocks = List.map (push_executable_proof_sentence ex_sentence) st.proof_blocks in
  { st with document_scope; proof_blocks }

let uniquize_key f l =
  let visited = Hashtbl.create 23 in
  let rec aux acc changed = function
    | h :: t ->
        let x = f h in
        if Hashtbl.mem visited x then aux acc true t else
          begin
            Hashtbl.add visited x x;
            aux (h :: acc) changed t
          end
    | [] -> if changed then List.rev acc else l
  in
  aux [] false l

let uniquize l = uniquize_key (fun x -> x) l

let flatten_proof_block st =
  match st.proof_blocks with
  | [] -> st
  | [block] ->
    let document_scope = uniquize @@ List.map (fun x -> x.id) block.proof_sentences @ st.document_scope in
    { st with document_scope; proof_blocks = [] }
  | block1 :: block2 :: tl -> (* Nested proofs. TODO check if we want to extrude one level or directly to document scope *)
    let proof_sentences = uniquize @@ block1.proof_sentences @ block2.proof_sentences in
    let block2 = { block2 with proof_sentences } in
    { st with proof_blocks = block2 :: tl }

let is_opaque_flat_proof terminator section_depth block = false

let push_state id ast synterp classif st = 
  (* let open Vernacextend in *)
  let ex_sentence = { id; ast; synterp; error_recovery = RSkip } in
  match classif with
  | VtStartProof ->
    base_id st, open_proof_block ex_sentence st, Exec ex_sentence
  | VtQed terminator_type ->
    log "scheduling a qed";
    begin match st.proof_blocks with
    | [] -> (* can happen on ill-formed documents *)
      base_id st, push_ex_sentence ex_sentence st, Exec ex_sentence
    | block :: pop ->
      (* TODO do not delegate if command with side effect inside the proof or nested lemmas *)
      if is_opaque_flat_proof terminator_type st.section_depth block then 
        begin 
          log "opaque proof";
          let terminator = { ex_sentence with error_recovery = RAdmitted } in
          let tasks = List.rev block.proof_sentences in
          let st = { st with proof_blocks = pop } in
          base_id st, push_ex_sentence ex_sentence st, OpaqueProof { terminator; opener_id = block.opener_id; tasks }
        end 
        else 
        begin
          log "not an opaque proof";
          let st = flatten_proof_block st in
          base_id st, push_ex_sentence ex_sentence st, Exec ex_sentence
        end
    end
  | VtQuery -> (* queries have no impact, we don't push them *)
    base_id st, st, Query ex_sentence
  | VtProofStep ->
    base_id st, push_ex_sentence ex_sentence st, Exec ex_sentence
  | VtSideff ->
    base_id st, extrude_side_effect ex_sentence st, Exec ex_sentence

  (*
let string_of_task (task_id,(base_id,task)) =
  let s = match task with
  | Skip id -> "Skip " ^ Stateid.to_string id
  | Exec (id, ast) -> "Exec " ^ Stateid.to_string id ^ " (" ^ (Pp.string_of_ppcmds @@ Ppvernac.pr_vernac ast) ^ ")"
  | OpaqueProof { terminator_id; tasks_ids } -> "OpaqueProof [" ^ Stateid.to_string terminator_id ^ " | " ^ String.concat "," (List.map Stateid.to_string tasks_ids) ^ "]"
  | Query(id,ast) -> "Query " ^ Stateid.to_string id
  in
  Format.sprintf "[%s] : [%s] -> %s" (Stateid.to_string task_id) (Option.cata Stateid.to_string "init" base_id) s
  *)

let _string_of_state st =
  let scopes = (List.map (fun b -> List.map (fun x -> x.id) b.proof_sentences) st.proof_blocks) @ [st.document_scope] in
  String.concat "|" (List.map (fun l -> String.concat " " (List.map Stateid.to_string l)) scopes)


let cata f a = function
  | Some c -> f c
  | None -> a

let schedule_sentence (id, (ast, classif, synterp_st)) st schedule =
  let base, st, task = 
      (* let open Vernacexpr in *)
      (* let (base, st, task) =  *) push_state id ast synterp_st classif st
      (* begin match ast.CAst.v.expr with
      | VernacSynterp (EVernacBeginSection _) ->
        (base, { st with section_depth = st.section_depth + 1 }, task)
      | VernacSynterp (EVernacEndSegment _) ->
        (base, { st with section_depth = max 0 (st.section_depth - 1) }, task)
      | _ -> (base, st, task)
      end *)
  in
(*
  log @@ "Scheduled " ^ (Stateid.to_string id) ^ " based on " ^ (match base with Some id -> Stateid.to_string id | None -> "no state");
  log @@ "New scheduler state: " ^ string_of_state st;
  *)
  let tasks = SM.add id (base, task) schedule.tasks in
  let add_dep deps x id =
    let upd = function
    | Some deps -> Some (StateidSet.add id deps)
    | None -> Some (StateidSet.singleton id)
    in
    SM.update x upd deps
  in
  let dependencies = cata (fun x -> add_dep schedule.dependencies x id) schedule.dependencies base in
  (* This new sentence impacts no sentence (yet) *)
  let dependencies = SM.add id StateidSet.empty dependencies in
  st, { tasks; dependencies }

exception SentenceScheduleError
exception DependentsError
let task_for_sentence schedule id =
  match SM.find_opt id schedule.tasks with
  | Some x -> x
  | None -> raise SentenceScheduleError

let dependents schedule id =
  match SM.find_opt id schedule.dependencies with
  | Some x -> x
  | None -> raise DependentsError

(** Dependency computation algo *)
(*
{}
1. Definition y := ...
{{1}}
2. Lemma x : T.
{{},{1,2}}
3. Proof using v.
{{3},{1,2}}
4. tac1.
{{3,4},{1,2}}
5. Definition f := Type.
{{3,4,5},{1,2,5}}
6. Defined.    ||     6. Qed.
{{1,2,3,4,5,6}}  ||     {{1,2,5,6}}
7. Check x.
*)

(*
let string_of_schedule schedule =
  "Task\n" ^
  String.concat "\n" @@ List.map string_of_task @@ SM.bindings schedule.tasks
  *)
