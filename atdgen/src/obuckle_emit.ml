open Printf

type param =
  { deref
    : (Ocaml.Repr.t, Json.json_repr) Mapping.mapping
      -> (Ocaml.Repr.t, Json.json_repr) Mapping.mapping;
  }

let make_ocaml_bs_intf ~original_types:_ _buf _deref _defs =
  ()

let dummy_loc = (Lexing.dummy_pos, Lexing.dummy_pos)

let runtime_module = "Atdgen_codec_runtime"

let rec get_reader_name
    ?(paren = false)
    ?(name_f = fun s -> "read_" ^ s)
    p (x : Oj_mapping.oj_mapping) : string =
  let ident = sprintf "%s.%s" runtime_module in
  match x with
    Unit (_, Unit, Unit) -> ident "unit"
  | Bool (_, Bool, Bool) -> ident "bool"
  | Int (_, Int o, Int) -> ident "int"
  | Float (_, Float, Float _) -> ident "float"
  | String (_, String, String) -> ident "string"
  | Tvar (_, s) -> "read_" ^ Ox_emit.name_of_var s

  | Name (_, s, args, None, None) ->
      let l = List.map (get_reader_name ~paren:true p) args in
      let s = String.concat " " (name_f s :: l) in
      if paren && l <> [] then "(" ^ s ^ ")"
      else s

  | External (_, _, args,
              External (_, main_module, ext_name),
              External) ->
      let f = main_module ^ "." ^ name_f ext_name in
      let l = List.map (get_reader_name ~paren:true p) args in
      let s = String.concat " " (f :: l) in
      if paren && l <> [] then "(" ^ s ^ ")"
      else s

  | _ -> assert false

let rec make_reader p type_annot (x : Oj_mapping.oj_mapping) : Indent.t list =
  match x with
    Unit _
  | Bool _
  | Int _
  | Float _
  | String _
  | Name _
  | External _
  | Tvar _ -> [ `Line (get_reader_name p x) ]
  | Record (loc, a, Record o, Record j) ->
      (match o with
         Record -> ()
       | Object ->
           Error.error loc "Sorry, OCaml objects are not supported"
      );
      [
        `Annot ("fun", `Line "fun p lb ->");
        `Block (make_record_reader p type_annot loc a j)
      ]

  | _ -> failwith "TODO: make_reader"

and make_record_reader _p _type_annot _loc _a _json_options =
  let create_record = [] in
  [ `Line "("
  ; `Block create_record
  ; `Line ")"
  ]

let get_left_reader_name p name param =
  let args = List.map (fun s -> Mapping.Tvar (dummy_loc, s)) param in
  get_reader_name p (Mapping.Name (dummy_loc, name, args, None, None))

let get_left_of_string_name p name param =
  let name_f s = s ^ "_of_json" in
  let args = List.map (fun s -> Mapping.Tvar (dummy_loc, s)) param in
  get_reader_name ~name_f p (Mapping.Name (dummy_loc, name, args, None, None))

let make_ocaml_bs_reader p ~original_types is_rec let1 let2
    (def : (_, _) Mapping.def) =
  let x = match def.def_value with None -> assert false | Some x -> x in
  let name = def.def_name in
  let type_constraint = Ox_emit.get_type_constraint ~original_types def in
  let param = def.def_param in
  let read = get_left_reader_name p name param in
  let type_annot =
    match Ox_emit.needs_type_annot x with
    | true -> Some type_constraint
    | false -> None
  in
  let reader_expr = make_reader p type_annot x in
  let eta_expand = is_rec && not (Ox_emit.is_function reader_expr) in
  let extra_param, extra_args =
    if eta_expand then " p lb", " p lb"
    else "", ""
  in
  [
    `Line (sprintf "%s %s%s = (" let1 read extra_param);
    `Block (List.map Indent.strip reader_expr);
    `Line (sprintf ")%s" extra_args);
  ]

let make_ocaml_bs_impl
    ~original_types
    buf deref defs =
  let p = {deref = deref;} in
  let ll =
    List.map (
      fun (is_rec, l) ->
        let l = List.filter
            (fun (x : (Ocaml.Repr.t, Json.json_repr) Mapping.def) ->
               x.def_value <> None) l in
        let readers =
          Ox_emit.map (
            fun is_first def ->
              let let1, let2 = Ox_emit.get_let ~is_rec ~is_first in
              make_ocaml_bs_reader p ~original_types is_rec let1 let2 def
          ) l
        in
        List.flatten readers
    ) defs
  in
  Atd.Indent.to_buffer buf (List.flatten ll)

let make_ml
    ~header:_
    ~original_types
    _ocaml_typedefs deref defs =
  let buf = Buffer.create 1000 in
  make_ocaml_bs_impl ~original_types buf deref defs;
  Buffer.contents buf

let make_mli
    ~header:_
    ~original_types
    _ocaml_typedefs deref defs =
  let buf = Buffer.create 1000 in
  make_ocaml_bs_intf ~original_types buf deref defs;
  Buffer.contents buf

let make_ocaml_files
    ~all_rec
    ~pos_fname
    ~pos_lnum
    ~type_aliases
    atd_file out =
  let ((head, m0), _) =
    match atd_file with
      Some file ->
        Atd.Util.load_file
          ~expand:false ~inherit_fields:true ~inherit_variants:true
          ?pos_fname ?pos_lnum
          file
    | None ->
        Atd.Util.read_channel
          ~expand:false ~inherit_fields:true ~inherit_variants:true
          ?pos_fname ?pos_lnum
          stdin
  in

  let tsort =
    if all_rec then
      function m -> [ (true, m) ]
    else
      Atd.Util.tsort
  in
  let m1 = tsort m0 in
  let (m1', original_types) =
    Atd.Expand.expand_module_body ~keep_poly:true m0
  in
  let m2 = tsort m1' in
  (* m0 = original type definitions
     m1 = original type definitions after dependency analysis
     m2 = monomorphic type definitions after dependency analysis *)
  let ocaml_typedefs =
    Ocaml.ocaml_of_atd ~pp_convs:(Ppx []) ~target:Json ~type_aliases (head, m1) in
  let defs = Oj_mapping.defs_of_atd_modules m2 in
  let header =
    let src =
      match atd_file with
        None -> "stdin"
      | Some path -> sprintf "%S" (Filename.basename path)
    in
    sprintf {|(* Auto-generated from %s *)
              [@@@ocaml.warning "-27-32-35-39"]|} src
  in
  let ml =
    make_ml ~header ~original_types
      ocaml_typedefs (Mapping.make_deref defs) defs
  in
  let mli =
    make_mli ~header ~original_types
      ocaml_typedefs (Mapping.make_deref defs) defs
  in
  Ox_emit.write_ocaml out mli ml

let make_ocaml_files
    ~opens:_
    ~with_typedefs:_
    ~with_create:_
    ~with_fundefs:_
    ~all_rec
    ~pos_fname
    ~pos_lnum
    ~type_aliases
    ~force_defaults:_
    ~name_overlap:_
    ~ocaml_version:_
    ~pp_convs:_
    atd_file out =
  make_ocaml_files ~all_rec ~pos_fname ~pos_lnum ~type_aliases atd_file out
