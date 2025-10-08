(* Non-empty list type for type-safe goal handling *)

type 'a t = 'a * 'a list

val make : 'a -> 'a list -> 'a t
val of_list : 'a list -> 'a t option
val of_list_exn : 'a list -> 'a t
val to_list : 'a t -> 'a list
val hd : 'a t -> 'a
val tl : 'a t -> 'a list
val length : 'a t -> int
val map : ('a -> 'b) -> 'a t -> 'b t
val iter : ('a -> unit) -> 'a t -> unit
val fold_left : ('acc -> 'a -> 'acc) -> 'acc -> 'a t -> 'acc
val cons : 'a -> 'a t -> 'a t
val append : 'a t -> 'a t -> 'a t
val rev : 'a t -> 'a t
