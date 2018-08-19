type 'a t

val make : ('a -> Json.t) -> 'a t

val null : unit t
val string : string t
val float : float t
val int : int t
val bool : bool t
val char : char t

val list : 'a t -> 'a list t

val int32 : int32 t
val int64 : int64 t
