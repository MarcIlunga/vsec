(* Non-empty list type for type-safe goal handling *)

type 'a t = 'a * 'a list

let make (hd: 'a) (tl: 'a list) : 'a t = (hd, tl)

let of_list (lst: 'a list) : 'a t option =
  match lst with
  | [] -> None
  | hd :: tl -> Some (hd, tl)

let of_list_exn (lst: 'a list) : 'a t =
  match lst with
  | [] -> invalid_arg "NonEmpty.of_list_exn: empty list"
  | hd :: tl -> (hd, tl)

let to_list ((hd, tl): 'a t) : 'a list = hd :: tl

let hd ((h, _): 'a t) : 'a = h

let tl ((_, t): 'a t) : 'a list = t

let length ((_, tl): 'a t) : int = 1 + List.length tl

let map (f: 'a -> 'b) ((hd, tl): 'a t) : 'b t =
  (f hd, List.map f tl)

let iter (f: 'a -> unit) ((hd, tl): 'a t) : unit =
  f hd;
  List.iter f tl

let fold_left (f: 'acc -> 'a -> 'acc) (acc: 'acc) ((hd, tl): 'a t) : 'acc =
  List.fold_left f (f acc hd) tl

let cons (x: 'a) ((hd, tl): 'a t) : 'a t =
  (x, hd :: tl)

let append ((hd1, tl1): 'a t) ((hd2, tl2): 'a t) : 'a t =
  (hd1, tl1 @ (hd2 :: tl2))

let rev ((hd, tl): 'a t) : 'a t =
  match List.rev (hd :: tl) with
  | [] -> failwith "NonEmpty.rev: impossible"
  | h :: t -> (h, t)
