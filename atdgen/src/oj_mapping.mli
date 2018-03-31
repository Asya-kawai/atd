(** The type signatures in this module are not yet for public consumption.

    Please don't rely on them in any way.*)

type oj_mapping =
    (Ocaml.Repr.t, Json.json_repr) Mapping.mapping

val defs_of_atd_modules
  : ('a *
     [< `Type of
          Atd.Ast.loc * (string * string list * Atd.Annot.t) * Atd.Ast.type_expr ]
       list
    ) list
  -> ('a * (Ocaml.Repr.t, Json.json_repr) Mapping.def list) list
