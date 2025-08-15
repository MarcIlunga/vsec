(**************************************************************************)
(*                                                                        *)
(*                                 VSRocq                                 *)
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

module SM = Map.Make (Int) (* Using sentence_id as int instead of Stateid *)

type error_recovery_strategy =
  | RSkip
  | RAdmitted

type executable_sentence = {
  id : sentence_id;
  ast : string;
  classif : EasyCryptClassification.classification;
  synterp : EcLib.EcScope.scope;
  error_recovery : error_recovery_strategy;
  ec_prog : EcLib.EcParsetree.prog option;
}

type task =
  | Skip of { id: sentence_id; error: string option }
  | Block of { id: sentence_id; synterp : EcLib.EcScope.scope; error: (Types.EasyCryptLocation.t option * string) }
  | Exec of executable_sentence
  | OpaqueProof of { terminator: executable_sentence;
                     opener_id: sentence_id;
                     proof_using: string; (* simplified proof_using *)
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
  dependencies : SentenceIdSet.t SM.t;
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

let flatten_proof_block st =
  match st.proof_blocks with
  | [] -> st
  | [block] ->
    let ids = List.map (fun x -> x.id) block.proof_sentences @ st.document_scope in
    let document_scope = List.sort_uniq compare ids in (* replace List.uniquize *)
    { st with document_scope; proof_blocks = [] }
  | block1 :: block2 :: tl -> (* Nested proofs. TODO check if we want to extrude one level or directly to document scope *)
    let combined = block1.proof_sentences @ block2.proof_sentences in
    let proof_sentences = List.sort_uniq (fun a b -> compare a.id b.id) combined in
    let block2 = { block2 with proof_sentences } in
    { st with proof_blocks = block2 :: tl }

(*
[1] Lemma foo : XX.
[2] Proof.
[3] Definition y := True.
[4] Lemma bar : y.
[5] Proof.
[6] exact I.
[7] Qed.

[8] apply bar.

[9] Qed.

-> We don't delegate

8: Exec(127, Qed)
2: Exec(1, Lemma foo : XX)

--> We delegate only pure proofs
*)

(* FIXME handle commands with side effects followed by `Abort` *)

let find_proof_using (ast : string) =
  (* TODO: Replace with EasyCrypt proof_using analysis *)
  log (fun () -> "no ast for proof using, using default");
  "" (* simplified - return empty string instead of complex proof_using *)

(* TODO: There is also a #[using] annotation on the proof opener we should
   take into account (but it is not on a proof sentence, but rather
   on the proof opener). Ask maxime if the attribute is processed during
   synterp, and if so where its value is stored. *)
let find_proof_using_annotation { proof_sentences } =
  match List.rev proof_sentences with
  | ex_sentence :: _ -> find_proof_using ex_sentence.ast
  | _ -> ""



let is_opaque_flat_proof terminator section_depth block =
  let open EasyCryptClassification in
  let has_side_effect { classif } = match classif with
    | EcDefinition | EcModule -> true
    | EcProofStep | EcQuery -> false
    | EcOther -> false
  in
  if List.exists has_side_effect block.proof_sentences then None
  else
    (* For EasyCrypt, we simplify opaque proof logic *)
    Some (find_proof_using_annotation block)

let push_state id ast synterp classif ec_prog_opt st =
  let open EasyCryptClassification in
  let ex_sentence = { id; ast; classif; synterp; error_recovery = RSkip; ec_prog = ec_prog_opt } in
  match classif with
  | EcDefinition ->
    (* EasyCrypt lemmas/definitions that might start proofs *)
    if String.contains ast '.' then
      base_id st, push_ex_sentence ex_sentence st, Exec ex_sentence
    else
      base_id st, open_proof_block ex_sentence st, Exec ex_sentence
  | EcProofStep ->
    (* This handles qed, tactics, proof steps *)
    begin match st.proof_blocks with
    | [] -> (* can happen on ill-formed documents *)
      base_id st, push_ex_sentence ex_sentence st, Exec ex_sentence
    | block :: pop ->
      (* Check if this is a proof terminator like qed *)
      let is_qed =
        match ec_prog_opt with
        | Some prog ->
          let open EcLib in
          let open EcParsetree in
          begin match EcLocation.unloc prog with
          | P_Prog (g :: _, _) -> (match EcLocation.unloc g.gl_action with | Gsave s -> (EcLocation.unloc s = `Qed) | _ -> false)
          | _ -> false
          end
        | None ->
          let lower_ast = String.lowercase_ascii ast in
          String.length lower_ast >= 3 && (String.sub lower_ast 0 3 = "qed")
      in
      if is_qed then (
        log (fun () -> "scheduling a qed");
        match is_opaque_flat_proof "qed" st.section_depth block with
        | Some proof_using ->
          log (fun () -> "opaque proof");
          let terminator = { ex_sentence with error_recovery = RAdmitted } in
          let tasks = List.rev block.proof_sentences in
          let st = { st with proof_blocks = pop } in
          base_id st, push_ex_sentence ex_sentence st, OpaqueProof { terminator; opener_id = block.opener_id; tasks; proof_using }
        | None ->
          log (fun () -> "not an opaque proof");
          let st = flatten_proof_block st in
          base_id st, push_ex_sentence ex_sentence st, Exec ex_sentence
      ) else
        base_id st, push_ex_sentence ex_sentence st, Exec ex_sentence
    end
  | EcQuery -> (* queries have no impact, we don't push them *)
    base_id st, push_ex_sentence ex_sentence st, Query ex_sentence
  | EcModule ->
    base_id st, extrude_side_effect ex_sentence st, Exec ex_sentence
  | EcOther -> base_id st, push_ex_sentence ex_sentence st, Skip { id; error = Some ("Unsupported command") }

let string_of_task (task_id,(base_id,task)) =
  let s = match task with
  | Skip { id } -> Format.sprintf "Skip %d" id
  | Exec { id } -> Format.sprintf "Exec %d" id
  | OpaqueProof { terminator; tasks } -> Format.sprintf "OpaqueProof [%d | %s]" terminator.id (String.concat "," (List.map (fun task -> string_of_int task.id) tasks))
  | Query { id } -> Format.sprintf "Query %d" id
  | Block { id } -> Format.sprintf "Block %d" id
  in
  Format.sprintf "[%d] : [%s] -> %s" task_id (match base_id with Some id -> string_of_int id | None -> "init") s

let _string_of_state st =
  let scopes = (List.map (fun b -> List.map (fun x -> x.id) b.proof_sentences) st.proof_blocks) @ [st.document_scope] in
  String.concat "|" (List.map (fun l -> String.concat " " (List.map string_of_int l)) scopes)

let schedule_errored_sentence id error synterp schedule =
  let task = Block {id; synterp; error} in
  let tasks = SM.add id (None, task) schedule.tasks in
  let dependencies = SM.add id SentenceIdSet.empty schedule.dependencies in
  {tasks; dependencies}

let schedule_sentence (id, (ast, classif, synterp_st, ec_prog_opt)) st schedule =
  let base, st, task = 
      let (base, st, task) = push_state id ast synterp_st classif ec_prog_opt st in
      (* EasyCrypt section handling - simplified *)
      let lower_ast = String.lowercase_ascii ast in
      if String.length lower_ast >= 7 && String.sub lower_ast 0 7 = "section" then
        (base, { st with section_depth = st.section_depth + 1 }, task)
      else if String.length lower_ast >= 3 && String.sub lower_ast 0 3 = "end" then
        (base, { st with section_depth = max 0 (st.section_depth - 1) }, task)
      else
        (base, st, task)
  in
(*
  log (fun () -> "Scheduled " ^ (sentence_ido_string id) ^ " based on " ^ (match base with Some id -> sentence_ido_string id | None -> "no state"));
  log (fun () -> "New scheduler state: " ^ string_of_state st);
  *)
  let tasks = SM.add id (base, task) schedule.tasks in
  let add_dep deps x id =
    let upd = function
    | Some deps -> Some (SentenceIdSet.add id deps)
    | None -> Some (SentenceIdSet.singleton id)
    in
    SM.update x upd deps
  in
  let dependencies = match base with Some x -> add_dep schedule.dependencies x id | None -> schedule.dependencies in
  (* This new sentence impacts no sentence (yet) *)
  let dependencies = SM.add id SentenceIdSet.empty dependencies in
  st, { tasks; dependencies }

let task_for_sentence schedule id =
  match SM.find_opt id schedule.tasks with
  | Some x -> x
  | None -> failwith ("cannot find schedule for sentence " ^ string_of_int id)

let dependents schedule id =
  match SM.find_opt id schedule.dependencies with
  | Some x -> x
  | None -> failwith ("cannot find dependents for sentence " ^ string_of_int id)

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

let string_of_schedule schedule =
  "Task\n" ^
  String.concat "\n" @@ List.map string_of_task @@ SM.bindings schedule.tasks
