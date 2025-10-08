(* High-ROI Type Safety: Numeric newtypes with validation *)

module Line : sig
  type t = private int
  val make : int -> t option
  val make_exn : int -> t
  val to_int : t -> int
  val zero : t
  val compare : t -> t -> int
  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit
end

module Column : sig
  type t = private int
  val make : int -> t option
  val make_exn : int -> t
  val to_int : t -> int
  val zero : t
  val compare : t -> t -> int
  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit
end

module Offset : sig
  type t = private int
  val make : int -> t option
  val make_exn : int -> t
  val to_int : t -> int
  val zero : t
  val add : t -> int -> t option
  val compare : t -> t -> int
  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit
end

module SentenceId : sig
  type t = private int
  val make : int -> t option
  val make_exn : int -> t
  val to_int : t -> int
  val compare : t -> t -> int
  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit
end

module GoalId : sig
  type t = private int
  val make : int -> t option
  val make_exn : int -> t
  val to_int : t -> int
  val zero : t
  val compare : t -> t -> int
  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit
end

module Progress : sig
  type t = private float
  val make : float -> t option
  val make_exn : float -> t
  val to_float : t -> float
  val zero : t
  val full : t
  val compare : t -> t -> int
  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit
end
