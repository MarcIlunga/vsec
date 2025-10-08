(* High-ROI Type Safety: Numeric newtypes with validation *)

(* Line numbers (1-indexed, non-negative) *)
module Line = struct
  type t = private int
  
  let make (n: int) : t option =
    if n >= 1 then Some (Obj.magic n : t)
    else None
  
  let make_exn (n: int) : t =
    if n >= 1 then (Obj.magic n : t)
    else invalid_arg (Printf.sprintf "Line.make_exn: invalid line %d (must be >= 1)" n)
  
  let to_int (l: t) : int = (Obj.magic l : int)
  
  let zero : t = (Obj.magic 1 : t)  (* Lines are 1-indexed *)
  
  let compare (a: t) (b: t) : int = compare (to_int a) (to_int b)
  
  let equal (a: t) (b: t) : bool = to_int a = to_int b
  
  let pp fmt (l: t) = Format.fprintf fmt "L%d" (to_int l)
end

(* Column numbers (0-indexed, non-negative) *)
module Column = struct
  type t = private int
  
  let make (n: int) : t option =
    if n >= 0 then Some (Obj.magic n : t)
    else None
  
  let make_exn (n: int) : t =
    if n >= 0 then (Obj.magic n : t)
    else invalid_arg (Printf.sprintf "Column.make_exn: invalid column %d (must be >= 0)" n)
  
  let to_int (c: t) : int = (Obj.magic c : int)
  
  let zero : t = (Obj.magic 0 : t)
  
  let compare (a: t) (b: t) : int = compare (to_int a) (to_int b)
  
  let equal (a: t) (b: t) : bool = to_int a = to_int b
  
  let pp fmt (c: t) = Format.fprintf fmt "C%d" (to_int c)
end

(* Byte offsets (0-indexed, non-negative) *)
module Offset = struct
  type t = private int
  
  let make (n: int) : t option =
    if n >= 0 then Some (Obj.magic n : t)
    else None
  
  let make_exn (n: int) : t =
    if n >= 0 then (Obj.magic n : t)
    else invalid_arg (Printf.sprintf "Offset.make_exn: invalid offset %d (must be >= 0)" n)
  
  let to_int (o: t) : int = (Obj.magic o : int)
  
  let zero : t = (Obj.magic 0 : t)
  
  let add (o: t) (delta: int) : t option =
    let result = to_int o + delta in
    if result >= 0 then Some (Obj.magic result : t)
    else None
  
  let compare (a: t) (b: t) : int = compare (to_int a) (to_int b)
  
  let equal (a: t) (b: t) : bool = to_int a = to_int b
  
  let pp fmt (o: t) = Format.fprintf fmt "Off%d" (to_int o)
end

(* Sentence IDs (positive integers) *)
module SentenceId = struct
  type t = private int
  
  let make (n: int) : t option =
    if n > 0 then Some (Obj.magic n : t)
    else None
  
  let make_exn (n: int) : t =
    if n > 0 then (Obj.magic n : t)
    else invalid_arg (Printf.sprintf "SentenceId.make_exn: invalid id %d (must be > 0)" n)
  
  let to_int (id: t) : int = (Obj.magic id : int)
  
  let compare (a: t) (b: t) : int = compare (to_int a) (to_int b)
  
  let equal (a: t) (b: t) : bool = to_int a = to_int b
  
  let pp fmt (id: t) = Format.fprintf fmt "S%d" (to_int id)
end

(* Goal IDs (non-negative integers) *)
module GoalId = struct
  type t = private int
  
  let make (n: int) : t option =
    if n >= 0 then Some (Obj.magic n : t)
    else None
  
  let make_exn (n: int) : t =
    if n >= 0 then (Obj.magic n : t)
    else invalid_arg (Printf.sprintf "GoalId.make_exn: invalid goal id %d (must be >= 0)" n)
  
  let to_int (id: t) : int = (Obj.magic id : int)
  
  let zero : t = (Obj.magic 0 : t)
  
  let compare (a: t) (b: t) : int = compare (to_int a) (to_int b)
  
  let equal (a: t) (b: t) : bool = to_int a = to_int b
  
  let pp fmt (id: t) = Format.fprintf fmt "G%d" (to_int id)
end

(* Progress percentage (0.0 to 1.0) *)
module Progress = struct
  type t = private float
  
  let make (f: float) : t option =
    if f >= 0.0 && f <= 1.0 then Some (Obj.magic f : t)
    else None
  
  let make_exn (f: float) : t =
    if f >= 0.0 && f <= 1.0 then (Obj.magic f : t)
    else invalid_arg (Printf.sprintf "Progress.make_exn: invalid progress %f (must be in [0.0, 1.0])" f)
  
  let to_float (p: t) : float = (Obj.magic p : float)
  
  let zero : t = (Obj.magic 0.0 : t)
  let full : t = (Obj.magic 1.0 : t)
  
  let compare (a: t) (b: t) : int = compare (to_float a) (to_float b)
  
  let equal (a: t) (b: t) : bool = to_float a = to_float b
  
  let pp fmt (p: t) = Format.fprintf fmt "%.1f%%" (to_float p *. 100.0)
end
