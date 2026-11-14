(* Name resolution and type checking. Annotates the AST in place.

   Every error is reported and checking goes on. Something whose error has
   been reported gets the type [Err], which every check accepts silently. So
   one mistake is reported once, and nothing that depends on it is reported
   again.

   Typing is bidirectional: [check_expr] takes the type the context expects,
   if any, so that a literal like '5' can become a u8 or an f64. *)

open Ast

type checker = {
  file : string;
  funcs : (string, func) Hashtbl.t;
  structs : (string, struct_decl) Hashtbl.t;
  consts : (string, const_decl) Hashtbl.t;
  (* Every parameter and local visible at this point. With no shadowing, one
     table is enough: a name is in it at most once. *)
  locals : (string, symbol) Hashtbl.t;
  (* The names declared in each open block, innermost first, so they can be
     removed when the block ends. *)
  mutable scopes : string list list;
  (* Symbols of this function whose block has ended, most recent first, so an
     undeclared name can point at one. *)
  mutable ended : symbol list;
  mutable next_id : int;
  mutable cur_func : func option; (* the function whose body is being checked *)
}

let sprintf = Printf.sprintf

(* ---- Building diagnostics ---- *)

let no_shadowing_note = "Slick does not allow shadowing"

let plural n word =
  if n = 1 then "1 " ^ word else string_of_int n ^ " " ^ word ^ "s"

(* "a", "a and b", "a, b and c". *)
let rec and_list items =
  match items with
  | [] -> ""
  | [ a ] -> a
  | [ a; b ] -> a ^ " and " ^ b
  | a :: rest -> a ^ ", " ^ and_list rest

(* A secondary label at a function's name, if it has a definition. *)
let with_function_label d f_opt text =
  match f_opt with Some f -> Diag.with_label d f.f_name_span text | None -> d

(* The span of the first character of [s], for a unary operator. *)
let first_char (s : Diag.span) =
  { s with end_line = s.start_line; end_col = s.start_col + 1 }

(* The point just after the first character of [s]: where 'mut ' goes in
   '*T' or '&x'. *)
let after_first_char (s : Diag.span) =
  {
    s with
    start_col = s.start_col + 1;
    end_line = s.start_line;
    end_col = s.start_col + 1;
  }

let quoted_source (s : Diag.span) =
  match Report.span_text s with Some text -> text | None -> "..."

let this_is t = "This is " ^ ty_name t

(* Whether two types disagree, counting [Err] as agreeing with anything. *)
let mismatch a b = a <> b && a <> Err && b <> Err

(* Whether [t] is known and is not [want]. *)
let is_not t want = t <> want && t <> Err

(* "Did you mean 'x'?", replacing the name at [span]. *)
let with_suggestion d span suggestion =
  match suggestion with
  | Some s ->
      Diag.with_help d (sprintf "Did you mean '%s'?" s) [ Diag.edit span s ]
  | None -> d

(* Wraps [e] in 'cast(T, ...)'. *)
let cast_help d (e : expr) target text =
  Diag.with_help d text
    [
      Diag.edit (Diag.point_before e.span)
        (sprintf "cast(%s, " (ty_name target));
      Diag.edit (Diag.point_after e.span) ")";
    ]

(* ---- Integer ranges ---- *)

let article_for k = if is_signed k then "An" else "A"

let int_min_text k =
  match k with
  | I8 -> "-128"
  | I16 -> "-32768"
  | I32 -> "-2147483648"
  | I64 -> "-9223372036854775808"
  | U8 | U16 | U32 | U64 -> "0"

let int_max_text k =
  match k with
  | I8 -> "127"
  | I16 -> "32767"
  | I32 -> "2147483647"
  | I64 -> "9223372036854775807"
  | U8 -> "255"
  | U16 -> "65535"
  | U32 -> "4294967295"
  | U64 -> "18446744073709551615"

let range_note k =
  sprintf "%s %s holds values from %s to %s" (article_for k) (int_kind_name k)
    (int_min_text k) (int_max_text k)

(* The largest magnitude a literal of kind [k] can have, read as unsigned. *)
let max_magnitude k neg =
  let bits = int_bits k in
  if is_signed k then
    let m = Int64.shift_left 1L (bits - 1) in
    if neg then m else Int64.sub m 1L
  else if neg then 0L
  else if bits = 64 then -1L
  else Int64.sub (Int64.shift_left 1L bits) 1L

let fits k (lit : int_lit) =
  Int64.unsigned_compare lit.value (max_magnitude k lit.neg) <= 0

let int_lit_text (lit : int_lit) =
  (if lit.neg then "-" else "") ^ Printf.sprintf "%Lu" lit.value

let float_lit_text (lit : float_lit) = (if lit.fneg then "-" else "") ^ lit.text

(* Whether the literal stays finite in type [k]. Rounding to f32 is done by
   going through its bits. *)
let float_fits k (lit : float_lit) =
  match float_of_string_opt lit.text with
  | None -> true
  | Some v -> (
      match k with
      | F64 -> Float.is_finite v
      | F32 -> Float.is_finite (Int32.float_of_bits (Int32.bits_of_float v)))

let report_range (e : expr) lit k =
  let name = int_kind_name k in
  let label =
    if lit.neg && not (is_signed k) then name ^ " cannot be negative"
    else if lit.neg then "Too small for " ^ name
    else "Too large for " ^ name
  in
  Report.report
    (Diag.with_note
       (Diag.error e.span
          (sprintf "Integer literal %s does not fit in %s" (int_lit_text lit)
             name)
          label)
       (range_note k))

let check_int_lit e lit expected =
  match expected with
  | Some (Int_ty k) ->
      if not (fits k lit) then report_range e lit k;
      Int_ty k
  | Some (Float_ty k) -> Float_ty k
  | _ ->
      if not (fits I32 lit) then report_range e lit I32;
      i32

let check_float_lit (e : expr) lit expected =
  let k = match expected with Some (Float_ty k) -> k | _ -> F32 in
  if not (float_fits k lit) then
    Report.report
      (Diag.error e.span
         (sprintf "Float literal %s does not fit in %s" (float_lit_text lit)
            (float_kind_name k))
         ("Too large for " ^ float_kind_name k));
  Float_ty k

(* ---- Conversions ---- *)

(* The lossless widenings, which happen implicitly. *)
let widens from target =
  match (from, target) with
  | Int_ty a, Int_ty b ->
      int_bits b > int_bits a && ((not (is_signed a)) || is_signed b)
  | Float_ty F32, Float_ty F64 -> true
  | _ -> false

(* '*mut T' becomes '*T'. It loses nothing and is not a number conversion,
   so it never warns. *)
let ptr_coerces from target =
  match (from, target) with
  | Ptr (true, a), Ptr (false, b) -> a = b
  | _ -> false

(* Records an implicit conversion of [e], for the emitter, and warns about
   it if asked to. *)
let convert (e : expr) from target =
  e.conv <- Some target;
  if Options.v.warn_implicit then
    Report.report
      (Diag.with_note
         (cast_help
            (Diag.warning e.span
               (sprintf "Implicit conversion from %s to %s" (ty_name from)
                  (ty_name target))
               ("Converted to " ^ ty_name target))
            e target "Write it explicitly")
         "Reported because of --warn-implicit-conversions")

(* At a place where a value of type [t] must become a [target]: an
   assignment, an argument, a return and so on. Returns whether that is
   fine; the caller reports the error otherwise, in its own words, and adds
   [explain]. *)
let coerce e t target =
  if t = Err || target = Err || t = target then true
  else if widens t target then begin
    convert e t target;
    true
  end
  else ptr_coerces t target

let conversion_note from target =
  let names = (ty_name from, ty_name target) in
  match (from, target) with
  | Int_ty a, Int_ty b ->
      if is_signed a && not (is_signed b) then
        Some
          (sprintf "Converting %s to %s could lose the sign" (fst names)
             (snd names))
      else
        Some
          (sprintf "Converting %s to %s could lose information" (fst names)
             (snd names))
  | Float_ty _, Float_ty _ ->
      Some
        (sprintf "Converting %s to %s could lose precision" (fst names)
           (snd names))
  | Int_ty _, Float_ty _ | Float_ty _, Int_ty _ ->
      Some "Integers and floats do not convert implicitly"
  | Ptr (false, a), Ptr (true, b) when a = b ->
      Some "A pointer to read-only data cannot become a '*mut'"
  | _ -> None

(* Why a value of type [from] cannot become a [target], and for numbers,
   how to convert it explicitly. *)
let explain d (e : expr) from target =
  match conversion_note from target with
  | Some note -> (
      let d = Diag.with_note d note in
      if is_number from && is_number target then
        cast_help d e target "Convert it explicitly"
      else
        match e.kind with
        | Addr_of (false, _) ->
            Diag.with_help d "Take a mutable pointer"
              [ Diag.edit (after_first_char e.span) "mut " ]
        | _ -> d)
  | None -> d

(* ---- Names ---- *)

let builtin_functions = [ "print"; "cast"; "bitcast" ]

let builtin_type name =
  match name with
  | "i8" -> Some (Int_ty I8)
  | "i16" -> Some (Int_ty I16)
  | "i32" -> Some (Int_ty I32)
  | "i64" -> Some (Int_ty I64)
  | "u8" -> Some (Int_ty U8)
  | "u16" -> Some (Int_ty U16)
  | "u32" -> Some (Int_ty U32)
  | "u64" -> Some (Int_ty U64)
  | "f32" -> Some (Float_ty F32)
  | "f64" -> Some (Float_ty F64)
  | "bool" -> Some Bool
  | "cstring" -> Some Cstring
  | _ -> None

let builtin_type_names =
  [
    "i8";
    "i16";
    "i32";
    "i64";
    "u8";
    "u16";
    "u32";
    "u64";
    "f32";
    "f64";
    "bool";
    "cstring";
  ]

let is_function c name =
  List.mem name builtin_functions || Hashtbl.mem c.funcs name

(* What a name already refers to, outside the locals. *)
type taken =
  | Free
  | Builtin_function
  | Builtin_type
  | Struct_name of struct_decl
  | Const_name of const_decl
  | Func_name of func

let global_meaning c name =
  if List.mem name builtin_functions then Builtin_function
  else if builtin_type name <> None then Builtin_type
  else
    match Hashtbl.find_opt c.structs name with
    | Some sd -> Struct_name sd
    | None -> (
        match Hashtbl.find_opt c.consts name with
        | Some cd -> Const_name cd
        | None -> (
            match Hashtbl.find_opt c.funcs name with
            | Some f -> Func_name f
            | None -> Free))

let choose_different d = Diag.with_help d "Choose a different name" []

let builtin_error span name what =
  Report.report
    (choose_different
       (Diag.error span
          (sprintf "'%s' is a built-in %s and cannot be redeclared" name what)
          ""))

(* Reports that [name] at [span] is already taken globally, if it is.
   Returns whether it was free. *)
let check_global_free c name span =
  match global_meaning c name with
  | Free -> true
  | Builtin_function ->
      builtin_error span name "function";
      false
  | Builtin_type ->
      builtin_error span name "type";
      false
  | Struct_name sd ->
      let d =
        Diag.error span
          (sprintf "'%s' is already declared as a struct" name)
          "Declared again here"
      in
      let d = Diag.with_label d sd.s_name_span "Struct defined here" in
      Report.report (choose_different (Diag.with_note d no_shadowing_note));
      false
  | Const_name cd ->
      let d =
        Diag.error span
          (sprintf "'%s' is already declared as a constant" name)
          "Declared again here"
      in
      let d = Diag.with_label d cd.c_name_span "Constant defined here" in
      Report.report (choose_different (Diag.with_note d no_shadowing_note));
      false
  | Func_name f ->
      let d =
        Diag.error span
          (sprintf "'%s' is already declared as a function" name)
          "Declared again here"
      in
      let d = Diag.with_label d f.f_name_span "Function defined here" in
      Report.report (choose_different (Diag.with_note d no_shadowing_note));
      false

(* ---- Types ---- *)

let rec struct_candidates (structs : struct_decl list) order acc =
  match structs with
  | [] -> acc
  | sd :: rest -> struct_candidates rest (order + 1) ((sd.s_name, order) :: acc)

let struct_candidate name (sd : struct_decl) acc =
  (name, 1000 + sd.s_name_span.start_line) :: acc

let rec numbered names order =
  match names with
  | [] -> []
  | n :: rest -> (n, order) :: numbered rest (order + 1)

let type_suggestion c name =
  match name with
  | "int" | "integer" | "long" -> Some (if name = "long" then "i64" else "i32")
  | "uint" -> Some "u32"
  | "char" | "byte" -> Some "u8"
  | "float" -> Some "f32"
  | "double" -> Some "f64"
  | "boolean" -> Some "bool"
  | _ ->
      Suggest.closest name
        (Hashtbl.fold struct_candidate c.structs
           (numbered builtin_type_names 0))

let rec resolve_type c ann =
  match ann.t_kind with
  | Pointer (m, inner) -> (
      match resolve_type c inner with Err -> Err | t -> Ptr (m, t))
  | Named name -> (
      match builtin_type name with
      | Some t -> t
      | None ->
          if Hashtbl.mem c.structs name then Struct name
          else begin
            let d =
              Diag.error ann.t_span
                (sprintf "Unknown type '%s'" name)
                "Not a type"
            in
            Report.report
              (match type_suggestion c name with
              | Some s ->
                  Diag.with_help d
                    (sprintf "Did you mean '%s'?" s)
                    [ Diag.edit ann.t_span s ]
              | None ->
                  Diag.with_note d
                    ("The built-in types are " ^ and_list builtin_type_names));
            Err
          end)

let rec find_field (fields : field list) name =
  match fields with
  | [] -> None
  | f :: rest -> if f.fd_name = name then Some f else find_field rest name

let rec field_names (fields : field list) =
  match fields with [] -> [] | f :: rest -> f.fd_name :: field_names rest

(* The field path to a pointer inside [t], if it holds one directly or in a
   struct it contains by value: [] for a pointer itself, ["owner"] for a
   struct with a pointer field 'owner'. [visited] guards against cycles,
   which are reported separately. *)
let rec pointer_path c t visited =
  match t with
  | Ptr _ | Cstring -> Some []
  | Struct name when not (List.mem name visited) -> (
      match Hashtbl.find_opt c.structs name with
      | Some sd -> fields_pointer_path c sd.s_fields (name :: visited)
      | None -> None)
  | _ -> None

and fields_pointer_path c fields visited =
  match fields with
  | [] -> None
  | f :: rest -> (
      match pointer_path c f.fd_ty visited with
      | Some path -> Some (f.fd_name :: path)
      | None -> fields_pointer_path c rest visited)

let pointer_note t path =
  match path with
  | [] when t = Cstring -> "A cstring points to text, so it cannot be zero"
  | [] ->
      sprintf "Its type %s is a pointer, and pointers cannot be zero"
        (ty_name t)
  | _ ->
      sprintf
        "Its type %s contains the pointer field '%s', and pointers cannot be \
         zero"
        (ty_name t) (String.concat "." path)

(* ---- Pass 1: structs ---- *)

let declare_struct c (sd : struct_decl) =
  match global_meaning c sd.s_name with
  | Struct_name prev ->
      Report.report
        (Diag.with_label
           (Diag.error sd.s_name_span
              (sprintf "Struct '%s' is already defined" sd.s_name)
              "Defined again here")
           prev.s_name_span "First defined here")
  | Free -> Hashtbl.replace c.structs sd.s_name sd
  | _ -> ignore (check_global_free c sd.s_name sd.s_name_span)

let rec check_struct_fields c (sd : struct_decl) = check_fields c [] sd.s_fields

and check_fields c (seen : field list) (fields : field list) =
  match fields with
  | [] -> ()
  | f :: rest ->
      f.fd_ty <- resolve_type c f.fd_ann;
      (match find_field seen f.fd_name with
      | Some prev ->
          Report.report
            (Diag.with_label
               (Diag.error f.fd_span
                  (sprintf "Field '%s' is declared twice" f.fd_name)
                  "Declared again here")
               prev.fd_span "First declared here")
      | None -> ());
      check_fields c (f :: seen) rest

(* The fields that lead from struct [name] back to [target] by value. *)
let rec cycle_path c target name visited =
  match Hashtbl.find_opt c.structs name with
  | None -> None
  | Some sd -> fields_cycle c target sd.s_fields visited

and fields_cycle c target (fields : field list) visited =
  match fields with
  | [] -> None
  | f :: rest -> (
      match f.fd_ty with
      | Struct n when n = target -> Some [ f ]
      | Struct n when not (List.mem n visited) -> (
          match cycle_path c target n (n :: visited) with
          | Some path -> Some (f :: path)
          | None -> fields_cycle c target rest visited)
      | _ -> fields_cycle c target rest visited)

let rec struct_of_field_types (path : field list) =
  match path with
  | [] -> []
  | f :: rest -> (
      match f.fd_ty with
      | Struct n -> n :: struct_of_field_types rest
      | _ -> struct_of_field_types rest)

let contains_label (f : field) =
  match f.fd_ty with Struct n -> sprintf "Contains '%s' by value" n | _ -> ""

let rec add_path_labels d (path : field list) =
  match path with
  | [] -> d
  | f :: rest ->
      add_path_labels (Diag.with_label d f.fd_span (contains_label f)) rest

(* A struct cannot contain itself by value: it would have no size. Each
   cycle is reported once, at the first struct in it. *)
let check_cycle c reported (sd : struct_decl) =
  let declared =
    match Hashtbl.find_opt c.structs sd.s_name with
    | Some s -> s == sd (* not a duplicate definition *)
    | None -> false
  in
  if declared && not (List.mem sd.s_name !reported) then
    match cycle_path c sd.s_name sd.s_name [ sd.s_name ] with
    | Some (first :: rest) ->
        reported := struct_of_field_types (first :: rest) @ !reported;
        let d =
          Diag.error first.fd_span
            (sprintf "Struct '%s' contains itself" sd.s_name)
            (contains_label first)
        in
        let d = add_path_labels d rest in
        let d =
          Diag.with_note d
            "A struct cannot contain itself, directly or through other \
             structs' fields"
        in
        Report.report
          (Diag.with_help d "Point to it instead, with a pointer field" [])
    | _ -> ()

(* ---- Pass 2: function signatures ---- *)

(* A function with a name already taken is reported and left out of the
   table; its body is still checked. *)
let resolve_param_type c prm = resolve_type c prm.p_ann

let declare_func c f =
  f.param_tys <- List.map (resolve_param_type c) f.params;
  f.ret_ty <-
    (match f.ret_ann with None -> Void | Some ann -> resolve_type c ann);
  if f.f_name = "main" && (f.params <> [] || f.ret_ann <> None) then begin
    let span =
      match (f.params, f.ret_ann) with
      | [], Some ann -> ann.t_span
      | _ -> f.params_span
    in
    Report.report
      (Diag.with_help
         (Diag.error span "'main' must take no parameters and return nothing" "")
         "Write it as 'main :: fn() { ... }'" [])
  end;
  if f.f_name = "main" && f.f_foreign <> None then
    Report.report
      (Diag.error f.f_name_span "'main' cannot be a foreign function" "");
  match global_meaning c f.f_name with
  | Func_name prev ->
      Report.report
        (Diag.with_label
           (Diag.error f.f_name_span
              (sprintf "Function '%s' is already defined" f.f_name)
              "Defined again here")
           prev.f_name_span "First defined here")
  | Free -> Hashtbl.replace c.funcs f.f_name f
  | _ -> ignore (check_global_free c f.f_name f.f_name_span)

(* ---- Scopes ---- *)

let open_scope c = c.scopes <- [] :: c.scopes

let end_name c name =
  match Hashtbl.find_opt c.locals name with
  | Some sym ->
      c.ended <- sym :: c.ended;
      Hashtbl.remove c.locals name
  | None -> ()

let close_scope c =
  match c.scopes with
  | names :: rest ->
      List.iter (end_name c) names;
      c.scopes <- rest
  | [] -> failwith "close_scope: no open scope"

(* No shadowing: a name cannot be declared while anything with that name is
   visible, including functions, structs and the built-in names. [init] is
   the new declaration's initial value, if it has one, for the "assign
   instead" suggestion.

   Returns whether to declare the name anyway. A name taken by something
   global is still declared as a local, so later uses do not report again. A
   name taken by another local is not: the first declaration stays. *)
let check_name_free c name span (init : expr option) =
  match Hashtbl.find_opt c.locals name with
  | Some sym ->
      let d =
        Diag.error span
          (sprintf "'%s' is already declared" name)
          "Declared again here"
      in
      let d = Diag.with_label d sym.sym_span "First declared here" in
      let d = Diag.with_note d no_shadowing_note in
      let help =
        match init with
        | Some e when sym.sym_mut ->
            sprintf "To change its value, assign to it: '%s = %s;'" name
              (quoted_source e.span)
        | _ -> "Choose a different name"
      in
      Report.report (Diag.with_help d help []);
      false
  | None ->
      ignore (check_global_free c name span);
      true

let add_local c name span type_span ty is_mut is_param mut_edit ptr_edit =
  let sym =
    {
      sym_name = name;
      sym_ty = ty;
      sym_mut = is_mut;
      sym_param = is_param;
      sym_span = span;
      sym_type_span = type_span;
      sym_mut_edit = mut_edit;
      sym_ptr_edit = ptr_edit;
      sym_id = c.next_id;
    }
  in
  c.next_id <- c.next_id + 1;
  Hashtbl.replace c.locals name sym;
  (match c.scopes with
  | names :: rest -> c.scopes <- (name :: names) :: rest
  | [] -> failwith "add_local: no open scope");
  sym

(* ---- Pass 3: bodies ---- *)

let rec find_ended name (syms : symbol list) =
  match syms with
  | [] -> None
  | sym :: rest ->
      if sym.sym_name = name then Some sym else find_ended name rest

(* Candidates for "did you mean", with the order they were declared in. *)
let local_candidate name sym acc = (name, sym.sym_id) :: acc

let function_candidate name f acc =
  (name, (f.f_name_span.start_line * 100000) + f.f_name_span.start_col) :: acc

let undeclared c span name =
  let d =
    Diag.error span (sprintf "Undeclared name '%s'" name) "Not declared"
  in
  Report.report
    (match find_ended name c.ended with
    | Some sym ->
        Diag.with_label d sym.sym_span
          "Declared here, in a block that has ended"
    | None ->
        with_suggestion d span
          (Suggest.closest name (Hashtbl.fold local_candidate c.locals [])));
  Err

let check_var c (e : expr) vr =
  match Hashtbl.find_opt c.locals vr.var_name with
  | Some sym ->
      vr.var_sym <- Some sym;
      sym.sym_ty
  | None -> (
      match global_meaning c vr.var_name with
      | Builtin_function | Func_name _ ->
          let f = Hashtbl.find_opt c.funcs vr.var_name in
          let d =
            Diag.error e.span
              (sprintf "'%s' is a function and cannot be used as a value yet"
                 vr.var_name)
              ""
          in
          let d = with_function_label d f "Function defined here" in
          let edits =
            match f with
            | Some f when f.params = [] ->
                [ Diag.edit (Diag.point_after e.span) "()" ]
            | _ -> []
          in
          Report.report (Diag.with_help d "To call it, add parentheses" edits);
          Err
      | Struct_name sd ->
          Report.report
            (Diag.with_label
               (Diag.error e.span
                  (sprintf "'%s' is a struct, not a value" vr.var_name)
                  "")
               sd.s_name_span "Struct defined here");
          Err
      | Builtin_type ->
          Report.report
            (Diag.error e.span
               (sprintf "'%s' is a type, not a value" vr.var_name)
               "");
          Err
      | Const_name _ -> failwith "check_var: constants go through check_name"
      | Free -> undeclared c e.span vr.var_name)

(* An operator applied to operands of the wrong types: the operator is the
   primary label, and each operand is labelled with its type. *)
let operand_error op_span msg (lhs : expr) lt (rhs : expr) rt =
  let d = Diag.error op_span msg "" in
  let d = Diag.with_label d lhs.span (ty_name lt) in
  Report.report (Diag.with_label d rhs.span (ty_name rt))

(* "Operator '+' expects numbers, found bool and i32". *)
let wrong_operands opname op_span want lhs lt rhs rt =
  operand_error op_span
    (sprintf "Operator '%s' expects %s, found %s and %s" opname want
       (ty_name lt) (ty_name rt))
    lhs lt rhs rt

let unary_error op_span msg (operand : expr) t =
  Diag.with_label (Diag.error op_span msg "") operand.span (ty_name t)

(* Whether [e] is made only of literals, so it takes its type from the other
   side of an operator. *)
let rec literal_like e =
  match e.kind with
  | Int _ | Float _ -> true
  | Unary ((Neg | Bnot), x) -> literal_like x
  | Binary b -> (
      match b.op with
      | Add | Sub | Mul | Div | Rem | Band | Bor | Bxor ->
          literal_like b.lhs && literal_like b.rhs
      | Shl | Shr -> literal_like b.lhs
      | Eq | Ne | Lt | Le | Gt | Ge | And | Or -> false)
  | _ -> false

let number_hint t = if is_number t then Some t else None

let hint_of expected =
  match expected with Some t when is_number t -> Some t | _ -> None

(* ---- Places ---- *)

(* What can be assigned to, or pointed to with '&mut'. *)
type place =
  | Not_place
  | Mutable_place
  | Immutable_var of symbol
  | Readonly_ptr of expr (* reached through this pointer to read-only data *)
  | Constant_place of const_decl (* a constant, or a field of one *)

let ptr_place (p : expr) =
  match p.ty with
  | Ptr (true, _) -> Mutable_place
  | Ptr (false, _) -> Readonly_ptr p
  | _ -> Mutable_place

(* Anything already reported counts as a mutable place, so it is not
   reported again. *)
let rec place_of e =
  match e.kind with
  | Var vr -> (
      match (vr.var_sym, vr.var_const) with
      | Some sym, _ -> if sym.sym_mut then Mutable_place else Immutable_var sym
      | None, Some cd -> Constant_place cd
      | None, None -> Mutable_place)
  | Field fa -> if fa.through_ptr then ptr_place fa.obj else place_of fa.obj
  | Deref p -> ptr_place p
  | _ -> if e.ty = Err then Mutable_place else Not_place

(* A symbol's declaration, labelled, with the help to make it 'mut'. *)
let with_declared_without_mut d sym =
  let d = Diag.with_label d sym.sym_span "Declared here without 'mut'" in
  Diag.with_help d "Declare it with 'mut'" [ sym.sym_mut_edit ]

(* For a pointer [p] to read-only data: where it was declared and how to
   make it a '*mut', when it is a plain name. *)
let with_ptr_help d (p : expr) =
  match p.kind with
  | Var { var_sym = Some sym; _ } -> (
      match sym.sym_ptr_edit with
      | Some edit ->
          let d =
            Diag.with_label d sym.sym_type_span
              (sprintf "Declared as %s here" (ty_name sym.sym_ty))
          in
          Diag.with_help d "Make it a mutable pointer" [ edit ]
      | None -> d)
  | _ -> d

let pointee_name (p : expr) =
  match p.ty with Ptr (_, t) -> ty_name t | t -> ty_name t

let report_assign_place (target : expr) place =
  match place with
  | Mutable_place -> ()
  | Not_place ->
      Report.report
        (Diag.with_note
           (Diag.error target.span "Cannot assign to this expression"
              "Not a place in memory")
           "Only variables, their fields, and what pointers point to can be \
            assigned to")
  | Immutable_var sym ->
      let msg =
        match target.kind with
        | Var _ ->
            sprintf "Cannot assign to %s'%s': it was declared without 'mut'"
              (if sym.sym_param then "parameter " else "")
              sym.sym_name
        | _ ->
            sprintf "Cannot assign to '%s': '%s' was declared without 'mut'"
              (quoted_source target.span)
              sym.sym_name
      in
      Report.report
        (with_declared_without_mut
           (Diag.error target.span msg "Cannot assign")
           sym)
  | Readonly_ptr p ->
      Report.report
        (with_ptr_help
           (Diag.error target.span
              (sprintf "Cannot assign through '%s': it points to a read-only %s"
                 (quoted_source p.span) (pointee_name p))
              "Cannot assign")
           p)
  | Constant_place cd ->
      let msg =
        match target.kind with
        | Var _ -> sprintf "Cannot assign to constant '%s'" cd.c_name
        | _ ->
            sprintf "Cannot assign to '%s': '%s' is a constant"
              (quoted_source target.span)
              cd.c_name
      in
      Report.report
        (Diag.with_label
           (Diag.error target.span msg "Cannot assign")
           cd.c_name_span "Constant defined here")

let report_addr_place (e : expr) (x : expr) is_mut place =
  match place with
  | Mutable_place -> ()
  | Not_place ->
      Report.report
        (Diag.with_help
           (Diag.error x.span "Cannot take the address of a temporary value"
              "Not stored anywhere")
           "Store it in a variable first" [])
  | Immutable_var sym when is_mut ->
      let msg =
        match x.kind with
        | Var _ ->
            sprintf
              "Cannot take a mutable pointer to '%s': it was declared without \
               'mut'"
              sym.sym_name
        | _ ->
            sprintf
              "Cannot take a mutable pointer to '%s': '%s' was declared \
               without 'mut'"
              (quoted_source x.span) sym.sym_name
      in
      Report.report
        (with_declared_without_mut (Diag.error e.span msg "Needs 'mut'") sym)
  | Readonly_ptr p when is_mut ->
      Report.report
        (with_ptr_help
           (Diag.error e.span
              (sprintf
                 "Cannot take a mutable pointer through '%s': it points to a \
                  read-only %s"
                 (quoted_source p.span) (pointee_name p))
              "Needs a '*mut'")
           p)
  | Constant_place cd ->
      Report.report
        (Diag.with_help
           (Diag.with_label
              (Diag.error x.span
                 (sprintf "Cannot take the address of constant '%s'" cd.c_name)
                 "A constant is not stored anywhere")
              cd.c_name_span "Constant defined here")
           "Store it in a variable first" [])
  | Immutable_var _ | Readonly_ptr _ -> ()

(* Whether [e] can be computed at compile time, as a constant's value must
   be. Each part that cannot is reported. *)
let not_constant (e : expr) what =
  Report.report
    (Diag.error e.span "A constant's value must be known at compile time" what);
  false

let rec constant_expr (e : expr) =
  match e.kind with
  | Int _ | Float _ | Bool_lit _ | String_lit _ | Var _ -> true
  | Unary (_, x) | Cast (_, _, x) -> constant_expr x
  | Field fa -> constant_expr fa.obj
  | Binary b ->
      let l = constant_expr b.lhs in
      let r = constant_expr b.rhs in
      l && r
  | Struct_lit sl -> constant_items sl.items
  | Call _ -> not_constant e "This is a function call"
  | Deref _ -> not_constant e "This reads through a pointer"
  | Addr_of _ -> not_constant e "This takes an address"

and constant_items (items : lit_item list) =
  match items with
  | [] -> true
  | item :: rest ->
      let first = constant_expr item.i_value in
      let others = constant_items rest in
      first && others

(* ---- Expressions ---- *)

let bytes t =
  match t with
  | Int_ty k -> int_bits k / 8
  | Float_ty k -> float_bits k / 8
  | _ -> 0

(* For 'bitcast(T, literal)': the literal's type, of T's size. *)
let bits_hint target (x : expr) =
  match (x.kind, target) with
  | Int _, Int_ty _ -> Some target
  | Int _, Float_ty F32 -> Some (Int_ty U32)
  | Int _, Float_ty F64 -> Some (Int_ty U64)
  | Float _, Float_ty _ -> Some target
  | Float _, Int_ty k when int_bits k = 64 -> Some (Float_ty F64)
  | _ -> None

let rec check_expr c e expected =
  let t =
    match e.kind with
    | Int lit -> check_int_lit e lit expected
    | Float lit -> check_float_lit e lit expected
    | Bool_lit _ -> Bool
    | Call call -> check_call c call
    | Var vr -> check_name c e vr
    | Unary (op, operand) -> check_unary c e op operand expected
    | Binary b -> check_binary c b expected
    | Field fa -> check_field c fa
    | Deref x -> check_deref c x
    | Addr_of (is_mut, x) -> check_addr_of c e is_mut x
    | Cast (kind, ann, x) -> check_cast c e kind ann x
    | Struct_lit sl -> check_struct_lit c e sl expected
    | String_lit _ -> Cstring
  in
  e.ty <- t;
  t

(* A name in an expression: a local, a constant, or something reported. *)
and check_name c (e : expr) vr =
  match
    ( Hashtbl.find_opt c.locals vr.var_name,
      Hashtbl.find_opt c.consts vr.var_name )
  with
  | None, Some cd ->
      vr.var_const <- Some cd;
      check_const c cd (Some e.span)
  | _ -> check_var c e vr

(* A constant's type, checking its value the first time. [use] is where it
   is used, for the error when a constant's value uses the constant itself.

   The value is checked with no locals in scope, since a constant can only
   see other top-level names. *)
and check_const c cd use =
  match cd.c_state with
  | Checked -> cd.c_ty
  | Broken -> Err
  | Checking ->
      let span = match use with Some s -> s | None -> cd.c_name_span in
      Report.report
        (Diag.with_label
           (Diag.error span
              (sprintf "Constant '%s' depends on itself" cd.c_name)
              "Used here, inside its own value")
           cd.c_name_span "Defined here");
      cd.c_state <- Broken;
      Err
  | Unchecked ->
      cd.c_state <- Checking;
      let before = Report.error_count () in
      let top =
        {
          c with
          locals = Hashtbl.create 1;
          scopes = [ [] ];
          ended = [];
          cur_func = None;
        }
      in
      let ann_ty =
        match cd.c_ann with
        | Some ann -> Some (resolve_type top ann)
        | None -> None
      in
      if constant_expr cd.c_value then begin
        let t = check_value top cd.c_value ann_ty in
        (match (ann_ty, cd.c_ann) with
        | Some at, Some ann ->
            if not (coerce cd.c_value t at) then
              Report.report
                (explain
                   (Diag.with_label
                      (Diag.error cd.c_value.span
                         (sprintf
                            "Constant '%s' of type %s cannot hold a value of \
                             type %s"
                            cd.c_name (ty_name at) (ty_name t))
                         (this_is t))
                      ann.t_span
                      (sprintf "Declared as %s here" (ty_name at)))
                   cd.c_value t at)
        | _ -> ());
        cd.c_ty <- (match ann_ty with Some at -> at | None -> t)
      end;
      if cd.c_state = Broken || Report.error_count () > before then begin
        cd.c_state <- Broken;
        Err
      end
      else begin
        cd.c_state <- Checked;
        cd.c_ty
      end

(* Like [check_expr], for positions that need a value. Only a call can be
   void. *)
and check_value c e expected =
  let t = check_expr c e expected in
  if t = Void then begin
    (match e.kind with
    | Call call ->
        let d =
          Diag.error e.span
            (sprintf "'%s' returns nothing, so it has no value to use"
               call.callee)
            ""
        in
        Report.report
          (with_function_label d
             (Hashtbl.find_opt c.funcs call.callee)
             "Declared here with no return type")
    | _ -> ());
    e.ty <- Err;
    Err
  end
  else t

and check_unary c e op operand expected =
  let op_span = first_char e.span in
  match op with
  | Neg -> (
      let t = check_value c operand (hint_of expected) in
      match t with
      | Int_ty k when not (is_signed k) ->
          Report.report
            (Diag.with_note
               (Diag.error operand.span
                  (sprintf "Cannot negate a value of type %s" (ty_name t))
                  (this_is t))
               (sprintf "%s has no negative values; '0 - %s' wraps around"
                  (ty_name t)
                  (quoted_source operand.span)));
          t
      | Int_ty _ | Float_ty _ | Err -> t
      | _ ->
          Report.report
            (unary_error op_span
               (sprintf "Operator '-' expects a number, found %s" (ty_name t))
               operand t);
          Err)
  | Bnot -> (
      let t = check_value c operand (hint_of expected) in
      match t with
      | Int_ty _ | Err -> t
      | _ ->
          let d =
            unary_error op_span
              (sprintf "Operator '~' expects an integer, found %s" (ty_name t))
              operand t
          in
          Report.report
            (if t = Bool then
               Diag.with_help d "For a logical not, use '!'"
                 [ Diag.edit op_span "!" ]
             else d);
          Err)
  | Not ->
      let t = check_value c operand None in
      if is_not t Bool then begin
        let d =
          unary_error op_span
            (sprintf "Operator '!' expects bool, found %s" (ty_name t))
            operand t
        in
        Report.report
          (if is_int t then
             Diag.with_help d
               (sprintf "To test for zero, compare it: '%s == 0'"
                  (quoted_source operand.span))
               []
           else d)
      end;
      Bool

and check_binary c b expected =
  let lt, rt =
    match b.op with
    | Shl | Shr ->
        let lt = check_value c b.lhs (hint_of expected) in
        (lt, check_value c b.rhs None)
    | And | Or -> (check_value c b.lhs None, check_value c b.rhs None)
    | _ ->
        let hint =
          match b.op with
          | Add | Sub | Mul | Div | Rem | Band | Bor | Bxor -> hint_of expected
          | _ -> None
        in
        (* A literal takes its type from the other side, so that side is
           checked first. *)
        if literal_like b.lhs && not (literal_like b.rhs) then
          let rt = check_value c b.rhs hint in
          (check_value c b.lhs (number_hint rt), rt)
        else
          let lt = check_value c b.lhs hint in
          (lt, check_value c b.rhs (number_hint lt))
  in
  binary_type (binop_text b.op) b.op b.op_span b.lhs lt b.rhs rt

(* The result type of [lhs op rhs], given their types. Also used for
   compound assignment, where [opname] is '+=' and so on. *)
and binary_type opname op op_span lhs lt rhs rt =
  let is_comparison =
    match op with Eq | Ne | Lt | Le | Gt | Ge | And | Or -> true | _ -> false
  in
  if lt = Err || rt = Err then if is_comparison then Bool else Err
  else
    match op with
    | Add | Sub | Mul | Div ->
        if is_number lt && is_number rt then unify opname lhs lt rhs rt
        else begin
          wrong_operands opname op_span "numbers" lhs lt rhs rt;
          Err
        end
    | Rem ->
        if is_int lt && is_int rt then unify opname lhs lt rhs rt
        else if is_number lt && is_number rt then begin
          let float_side = if is_float lt then lhs else rhs in
          let d =
            Diag.error op_span
              (sprintf "Operator '%s' does not work on floats" opname)
              ""
          in
          let d = Diag.with_label d float_side.span (this_is float_side.ty) in
          Report.report
            (Diag.with_note d "Float remainder is not supported yet");
          Err
        end
        else begin
          wrong_operands opname op_span "integers" lhs lt rhs rt;
          Err
        end
    | Band | Bor | Bxor ->
        if is_int lt && is_int rt then unify opname lhs lt rhs rt
        else if lt = Bool && rt = Bool then begin
          let what, replacement =
            match op with
            | Band -> ("For a logical and", "&&")
            | Bor -> ("For a logical or", "||")
            | _ -> ("To test whether they differ", "!=")
          in
          let d =
            Diag.error op_span
              (sprintf "Operator '%s' does not work on bool" opname)
              ""
          in
          (* In 'g |= false' the fix is not a one-token edit. *)
          let compound = opname <> binop_text op in
          Report.report
            (if compound then
               Diag.with_help d
                 (sprintf "%s, write '%s = %s %s %s'" what
                    (quoted_source lhs.span) (quoted_source lhs.span)
                    replacement (quoted_source rhs.span))
                 []
             else
               Diag.with_help d
                 (sprintf "%s, use '%s'" what replacement)
                 [ Diag.edit op_span replacement ]);
          Bool
        end
        else begin
          wrong_operands opname op_span "integers" lhs lt rhs rt;
          Err
        end
    | Shl | Shr ->
        if is_int lt && is_int rt then begin
          check_shift_amount rhs lt;
          lt
        end
        else begin
          wrong_operands opname op_span "integers" lhs lt rhs rt;
          Err
        end
    | Lt | Le | Gt | Ge ->
        (if is_number lt && is_number rt then
           ignore (unify opname lhs lt rhs rt)
         else
           match (lt, rt) with
           | Ptr _, Ptr _ ->
               Report.report
                 (Diag.with_note
                    (Diag.with_label
                       (Diag.with_label
                          (Diag.error op_span
                             (sprintf "Operator '%s' does not work on pointers"
                                opname)
                             "")
                          lhs.span (ty_name lt))
                       rhs.span (ty_name rt))
                    "Pointers can only be compared with '==' and '!='")
           | _ -> wrong_operands opname op_span "numbers" lhs lt rhs rt);
        Bool
    | Eq | Ne ->
        (if is_number lt && is_number rt then
           ignore (unify opname lhs lt rhs rt)
         else
           match (lt, rt) with
           | Struct _, Struct _ when lt = rt ->
               Report.report
                 (Diag.with_note
                    (Diag.error op_span
                       (sprintf "Cannot compare structs with '%s'" opname)
                       "")
                    "Compare their fields one by one")
           | Ptr (_, a), Ptr (_, b) when a = b -> ()
           | Bool, Bool -> ()
           | Cstring, Cstring ->
               Report.report
                 (Diag.with_note
                    (Diag.error op_span
                       (sprintf "Cannot compare cstrings with '%s'" opname)
                       "")
                    "It would compare their addresses, not their text")
           | _ ->
               operand_error op_span
                 (sprintf
                    "Operator '%s' needs both sides to have the same type, \
                     found %s and %s"
                    opname (ty_name lt) (ty_name rt))
                 lhs lt rhs rt);
        Bool
    | And | Or ->
        if lt <> Bool || rt <> Bool then
          wrong_operands opname op_span "bool operands" lhs lt rhs rt;
        Bool

(* Two number types meet at the wider one, when one widens to the other
   without loss. *)
and unify opname lhs lt rhs rt =
  if lt = rt then lt
  else if widens lt rt then begin
    convert lhs lt rt;
    rt
  end
  else if widens rt lt then begin
    convert rhs rt lt;
    lt
  end
  else begin
    let d =
      Diag.error rhs.span
        (sprintf "Mismatched types in '%s': %s and %s" opname (ty_name lt)
           (ty_name rt))
        (this_is rt)
    in
    let d = Diag.with_label d lhs.span (this_is lt) in
    let d =
      Diag.with_note d
        (if is_int lt = is_int rt then
           "Neither type converts to the other without losing information"
         else "Integers and floats do not convert implicitly")
    in
    (* An integer meeting a float is converted to the float, not the other
       way around. *)
    let side, target =
      if is_int lt && is_float rt then (lhs, rt) else (rhs, lt)
    in
    Report.report (cast_help d side target "Convert one side explicitly");
    Err
  end

and check_shift_amount (rhs : expr) lt =
  match (rhs.kind, lt) with
  | Int lit, Int_ty k ->
      let bits = int_bits k in
      if lit.neg && lit.value <> 0L then
        Report.report
          (Diag.error rhs.span "Shift amount cannot be negative" "Negative")
      else if Int64.unsigned_compare lit.value (Int64.of_int bits) >= 0 then
        Report.report
          (Diag.with_note
             (Diag.error rhs.span
                (sprintf "Shift amount %s is too large for %s"
                   (int_lit_text lit) (int_kind_name k))
                "Too large")
             (sprintf "%s %s can be shifted by 0 to %d" (article_for k)
                (int_kind_name k) (bits - 1)))
  | _ -> ()

(* The type of field [fa] of struct [name], reporting an unknown field. *)
and field_type c fa name =
  match Hashtbl.find_opt c.structs name with
  | None -> Err
  | Some sd -> (
      match find_field sd.s_fields fa.field with
      | Some f -> f.fd_ty
      | None ->
          let d =
            Diag.error fa.field_span
              (sprintf "Struct '%s' has no field '%s'" name fa.field)
              "Unknown field"
          in
          let names = field_names sd.s_fields in
          let suggestion = Suggest.closest fa.field (numbered names 0) in
          let d =
            match suggestion with
            | Some _ -> with_suggestion d fa.field_span suggestion
            | None ->
                Diag.with_note d
                  (if names = [] then sprintf "'%s' has no fields" name
                   else sprintf "Its fields are %s" (and_list names))
          in
          Report.report d;
          Err)

and check_field c fa =
  let ot = check_value c fa.obj None in
  match ot with
  | Err -> Err
  | Struct name -> field_type c fa name
  | Ptr (_, Struct name) ->
      fa.through_ptr <- true;
      field_type c fa name
  | Ptr (_, Ptr (_, Struct _)) ->
      Report.report
        (Diag.with_help
           (Diag.error fa.obj.span "Cannot access a field through two pointers"
              (this_is ot))
           "Dereference it first"
           [
             Diag.edit (Diag.point_before fa.obj.span) "(*";
             Diag.edit (Diag.point_after fa.obj.span) ")";
           ]);
      Err
  | t ->
      Report.report
        (Diag.error fa.obj.span
           (sprintf "A value of type %s has no fields" (ty_name t))
           (this_is t));
      Err

and check_deref c x =
  match check_value c x None with
  | Ptr (_, t) -> t
  | Err -> Err
  | t ->
      Report.report
        (Diag.error x.span
           (sprintf "Cannot dereference a value of type %s" (ty_name t))
           (this_is t));
      Err

and check_addr_of c e is_mut x =
  let t = check_value c x None in
  report_addr_place e x is_mut (place_of x);
  if t = Err then Err else Ptr (is_mut, t)

and check_cast c e kind ann x =
  let target = resolve_type c ann in
  let hint =
    match kind with Convert -> number_hint target | Bits -> bits_hint target x
  in
  let t = check_value c x hint in
  let name = match kind with Convert -> "cast" | Bits -> "bitcast" in
  (if target <> Err && t <> Err then
     if not (is_number target && is_number t) then
       Report.report
         (Diag.with_note
            (Diag.error x.span
               (sprintf "Cannot %s from %s to %s" name (ty_name t)
                  (ty_name target))
               (this_is t))
            (match kind with
            | Convert -> "'cast' converts between number types"
            | Bits ->
                "'bitcast' reinterprets the bits of one number type as another"))
     else if kind = Bits && bytes t <> bytes target then
       let keyword =
         {
           e.span with
           end_line = e.span.start_line;
           end_col = e.span.start_col + 7;
         }
       in
       Report.report
         (Diag.with_help
            (Diag.with_note
               (Diag.error x.span
                  (sprintf "Cannot bitcast from %s to %s: they differ in size"
                     (ty_name t) (ty_name target))
                  (sprintf "This is %d bytes" (bytes t)))
               (sprintf "%s is %d bytes" (ty_name target) (bytes target)))
            "To convert the value, use 'cast'"
            [ Diag.edit keyword "cast" ]));
  target

and check_struct_lit c e sl expected =
  let sd_opt =
    match sl.sl_name with
    | Some (name, span) -> (
        match Hashtbl.find_opt c.structs name with
        | Some sd -> Some sd
        | None ->
            not_a_struct c name span;
            None)
    | None -> (
        match expected with
        | Some (Struct name) -> Hashtbl.find_opt c.structs name
        | Some Err -> None
        | _ ->
            Report.report
              (Diag.with_help
                 (Diag.error sl.sl_open
                    "Cannot tell the type of this struct literal" "")
                 "Write the struct's name before '{'" []);
            None)
  in
  match sd_opt with
  | None ->
      check_items_only c sl.items;
      Err
  | Some sd ->
      check_items c e sl sd;
      Struct sd.s_name

and not_a_struct c name span =
  let d =
    Diag.error span (sprintf "'%s' is not a struct" name) "Not a struct"
  in
  match Hashtbl.find_opt c.locals name with
  | Some sym -> Report.report (Diag.with_label d sym.sym_span "Declared here")
  | None -> (
      match global_meaning c name with
      | Func_name f ->
          Report.report
            (Diag.with_label d f.f_name_span "Function defined here")
      | Const_name cd ->
          Report.report
            (Diag.with_label d cd.c_name_span "Constant defined here")
      | Builtin_type | Builtin_function -> Report.report d
      | Struct_name _ | Free ->
          Report.report
            (with_suggestion
               (Diag.error span
                  (sprintf "Unknown struct '%s'" name)
                  "Not defined")
               span
               (Suggest.closest name
                  (Hashtbl.fold struct_candidate c.structs []))))

and is_named (i : lit_item) = i.i_name <> None
and is_positional (i : lit_item) = i.i_name = None

and gives_field name (items : lit_item list) =
  match items with
  | [] -> false
  | { i_name = Some (n, _); _ } :: rest -> n = name || gives_field name rest
  | _ :: rest -> gives_field name rest

and check_items_only c (items : lit_item list) =
  match items with
  | [] -> ()
  | item :: rest ->
      ignore (check_value c item.i_value None);
      check_items_only c rest

and check_items c e sl sd =
  let named = List.filter is_named sl.items in
  let positional = List.filter is_positional sl.items in
  match (named, positional) with
  | _ :: _, first :: _ ->
      Report.report
        (Diag.error first.i_value.span
           "Struct literal mixes named and positional values" "Positional value");
      check_items_only c sl.items
  | [], _ :: _ ->
      let expected = List.length sd.s_fields in
      let found = List.length positional in
      if expected <> found then begin
        let d =
          Diag.error e.span
            (sprintf "Expected %s for '%s', found %d" (plural expected "value")
               sd.s_name found)
            ("Found " ^ plural found "value")
        in
        let d = Diag.with_label d sd.s_name_span "Struct defined here" in
        Report.report
          (if found < expected then
             Diag.with_note d
               "Positional values must give every field; name them to leave \
                some out"
           else d)
      end;
      check_positional c sd sd.s_fields positional
  | _, [] ->
      check_named c sd [] named;
      check_missing_pointers c sl sd sd.s_fields named

and check_field_value c sd (f : field) (value : expr) =
  let t = check_value c value (Some f.fd_ty) in
  if not (coerce value t f.fd_ty) then
    Report.report
      (explain
         (Diag.with_label
            (Diag.error value.span
               (sprintf "Field '%s' of '%s' has type %s, found %s" f.fd_name
                  sd.s_name (ty_name f.fd_ty) (ty_name t))
               (this_is t))
            f.fd_ann.t_span
            (sprintf "Declared as %s here" (ty_name f.fd_ty)))
         value t f.fd_ty)

and check_positional c sd (fields : field list) (items : lit_item list) =
  match (fields, items) with
  | _, [] -> ()
  | [], rest -> check_items_only c rest
  | f :: frest, item :: irest ->
      check_field_value c sd f item.i_value;
      check_positional c sd frest irest

and check_named c sd seen (items : lit_item list) =
  match items with
  | [] -> ()
  | item :: rest -> (
      let name, span =
        match item.i_name with Some n -> n | None -> ("", item.i_value.span)
      in
      match List.assoc_opt name seen with
      | Some first ->
          Report.report
            (Diag.with_label
               (Diag.error span
                  (sprintf "Field '%s' is given twice" name)
                  "Given again here")
               first "First given here");
          ignore (check_value c item.i_value None);
          check_named c sd seen rest
      | None ->
          (match find_field sd.s_fields name with
          | Some f -> check_field_value c sd f item.i_value
          | None ->
              Report.report
                (with_suggestion
                   (Diag.error span
                      (sprintf "Struct '%s' has no field '%s'" sd.s_name name)
                      "Unknown field")
                   span
                   (Suggest.closest name (numbered (field_names sd.s_fields) 0)));
              ignore (check_value c item.i_value None));
          check_named c sd ((name, span) :: seen) rest)

(* A field left out is zero, which a pointer cannot be. *)
and check_missing_pointers c sl sd (fields : field list) named =
  match fields with
  | [] -> ()
  | f :: rest ->
      (if not (gives_field f.fd_name named) then
         match pointer_path c f.fd_ty [ sd.s_name ] with
         | Some path ->
             Report.report
               (Diag.with_note
                  (Diag.error sl.sl_open
                     (sprintf "Field '%s' must be given a value" f.fd_name)
                     (sprintf "Missing '%s'" f.fd_name))
                  (match path with
                  | [] when f.fd_ty = Cstring ->
                      sprintf
                        "'%s' is a cstring, which points to text, so it cannot \
                         be zero"
                        f.fd_name
                  | [] ->
                      sprintf "'%s' is a pointer, and pointers cannot be zero"
                        f.fd_name
                  | _ ->
                      sprintf
                        "'%s' contains the pointer field '%s', and pointers \
                         cannot be zero"
                        f.fd_name (String.concat "." path)))
         | None -> ());
      check_missing_pointers c sl sd rest named

(* [params] is the function's parameter list. *)
and check_args c callee_name (args : expr list) expected params index =
  match (args, expected) with
  | [], _ | _, [] -> ()
  | arg :: rest, ty :: rest_tys ->
      let t = check_value c arg (Some ty) in
      if not (coerce arg t ty) then begin
        let d =
          Diag.error arg.span
            (sprintf "Argument %d of '%s' expects %s, found %s" index
               callee_name (ty_name ty) (ty_name t))
            (this_is t)
        in
        let d =
          match params with
          | prm :: _ ->
              Diag.with_label d prm.p_span
                (sprintf "Parameter '%s' is declared here" prm.p_name)
          | [] -> d
        in
        Report.report (explain d arg t ty)
      end;
      let rest_params = match params with _ :: ps -> ps | [] -> [] in
      check_args c callee_name rest rest_tys rest_params (index + 1)

(* Arguments of a call that is already wrong are still checked, for errors
   of their own. *)
and check_args_only c args = List.iter (check_arg_only c) args
and check_arg_only c arg = ignore (check_value c arg None)

(* print(x) takes a number or a bool; print(x, n) takes a float and the
   number of digits after the point. *)
and check_printed c (x : expr) =
  let t = check_value c x None in
  if t <> Err && not (is_number t || t = Bool || t = Cstring) then
    Report.report
      (Diag.error x.span "'print' takes a number, a bool or a cstring"
         (this_is t));
  t

and check_print c call =
  (match call.args with
  | [ x ] -> ignore (check_printed c x)
  | [ x; n ] ->
      let t = check_printed c x in
      let nt = check_value c n None in
      if is_int t || t = Bool || t = Cstring then
        Report.report
          (Diag.with_label
             (Diag.error n.span "A precision only applies to floats" "Precision")
             x.span (this_is t))
      else if
        match n.kind with Int lit -> lit.neg && lit.value <> 0L | _ -> false
      then
        Report.report
          (Diag.error n.span "Precision cannot be negative" "Negative")
      else if nt <> Err && not (is_int nt) then
        Report.report
          (Diag.error n.span
             (sprintf "The precision must be an integer, found %s" (ty_name nt))
             (this_is nt))
  | args ->
      let found = List.length args in
      Report.report
        (Diag.error call.args_span
           (sprintf "'print' expects 1 or 2 arguments, found %d" found)
           ("Found " ^ plural found "argument"));
      check_args_only c args);
  Void

and check_call c call =
  match Hashtbl.find_opt c.locals call.callee with
  | Some sym ->
      Report.report
        (Diag.with_label
           (Diag.error call.callee_span
              (sprintf "'%s' is not a function" call.callee)
              "")
           sym.sym_span
           (sprintf "'%s' is declared here as %s" call.callee
              (ty_name sym.sym_ty)));
      check_args_only c call.args;
      Err
  | None -> (
      if call.callee = "print" then check_print c call
      else
        match global_meaning c call.callee with
        | Func_name f ->
            let expected = List.length f.param_tys in
            let found = List.length call.args in
            if expected <> found then begin
              Report.report
                (Diag.with_label
                   (Diag.error call.args_span
                      (sprintf "'%s' expects %s, found %d" call.callee
                         (plural expected "argument")
                         found)
                      ("Found " ^ plural found "argument"))
                   f.params_span
                   (sprintf "'%s' is defined here" call.callee));
              check_args_only c call.args
            end
            else check_args c call.callee call.args f.param_tys f.params 1;
            f.ret_ty
        | Const_name cd ->
            Report.report
              (Diag.with_label
                 (Diag.error call.callee_span
                    (sprintf "'%s' is a constant, not a function" call.callee)
                    "")
                 cd.c_name_span "Constant defined here");
            check_args_only c call.args;
            Err
        | Struct_name sd ->
            Report.report
              (Diag.with_help
                 (Diag.with_label
                    (Diag.error call.callee_span
                       (sprintf "'%s' is a struct, not a function" call.callee)
                       "")
                    sd.s_name_span "Struct defined here")
                 (sprintf "To make one, write '%s{ ... }'" call.callee)
                 []);
            check_args_only c call.args;
            Err
        | _ ->
            let candidates =
              ("print", 0) :: Hashtbl.fold function_candidate c.funcs []
            in
            Report.report
              (with_suggestion
                 (Diag.error call.callee_span
                    (sprintf "Unknown function '%s'" call.callee)
                    "Not defined")
                 call.callee_span
                 (Suggest.closest call.callee candidates));
            check_args_only c call.args;
            Err)

(* ---- Statements ---- *)

(* How to make a declaration 'mut': 'x := v' becomes 'x : mut = v', and
   'x : T' becomes 'x : mut T'. *)
let decl_mut_edit d =
  if d.d_colon_eq then Diag.edit d.d_sep_span ": mut ="
  else
    match d.d_ann with
    | Some ann -> Diag.edit (Diag.point_before ann.t_span) "mut "
    | None -> Diag.edit (Diag.point_after d.d_sep_span) " mut"

(* For a read-only pointer: the 'mut ' to insert after the '*' of its
   written type, or after the '&' it was initialized with. *)
let ptr_edit ty (ann : type_ann option) (init : expr option) =
  match ty with
  | Ptr (false, _) -> (
      match (ann, init) with
      | Some ann, _ -> Some (Diag.edit (after_first_char ann.t_span) "mut ")
      | None, Some { kind = Addr_of (false, _); span; _ } ->
          Some (Diag.edit (after_first_char span) "mut ")
      | _ -> None)
  | _ -> None

(* 'x := 3000000000;' gets a help to give it a larger type. *)
let check_init c d (init : expr) ann_ty =
  match (ann_ty, init.kind) with
  | None, Int lit when not (fits I32 lit) ->
      let bigger =
        if fits I64 lit then Some I64
        else if fits U64 lit then Some U64
        else None
      in
      let d' =
        Diag.with_note
          (Diag.error init.span
             (sprintf "Integer literal %s does not fit in i32"
                (int_lit_text lit))
             "Too large for i32")
          (range_note I32)
      in
      let t =
        match bigger with
        | Some k ->
            Report.report
              (Diag.with_help d' "Give it a larger type"
                 [ Diag.edit d.d_sep_span (sprintf ": %s =" (int_kind_name k)) ]);
            Int_ty k
        | None ->
            Report.report d';
            i32
      in
      init.ty <- t;
      t
  | _ -> check_value c init ann_ty

let check_decl c d =
  (* The name is checked first, but declared only after the initializer, so
     'x := x + 1;' cannot read the 'x' it declares. *)
  let declare = check_name_free c d.d_name d.d_name_span d.d_init in
  let ann_ty =
    match d.d_ann with Some ann -> Some (resolve_type c ann) | None -> None
  in
  let init_ty =
    match d.d_init with
    | Some init -> Some (check_init c d init ann_ty)
    | None -> None
  in
  (match (ann_ty, d.d_ann, init_ty, d.d_init) with
  | Some t, Some ann, Some it, Some init ->
      if not (coerce init it t) then
        Report.report
          (explain
             (Diag.with_label
                (Diag.error init.span
                   (sprintf
                      "Cannot initialize '%s' of type %s with a value of type \
                       %s"
                      d.d_name (ty_name t) (ty_name it))
                   (this_is it))
                ann.t_span
                (sprintf "Declared as %s here" (ty_name t)))
             init it t)
  | Some t, _, None, None -> (
      match pointer_path c t [] with
      | Some path ->
          Report.report
            (Diag.with_note
               (Diag.error d.d_name_span
                  (sprintf "'%s' must be given an initial value" d.d_name)
                  "")
               (pointer_note t path))
      | None -> ())
  | _ -> ());
  let ty =
    match (ann_ty, init_ty) with
    | Some t, _ -> t
    | None, Some it -> it
    | None, None -> Err
  in
  let type_span =
    match d.d_ann with Some ann -> ann.t_span | None -> d.d_name_span
  in
  if declare then
    d.d_sym <-
      Some
        (add_local c d.d_name d.d_name_span type_span ty d.d_mut false
           (decl_mut_edit d)
           (ptr_edit ty d.d_ann d.d_init))

(* The target of an assignment. A function name gets its own error. *)
let check_target c (target : expr) =
  match target.kind with
  | Var vr
    when (not (Hashtbl.mem c.locals vr.var_name)) && is_function c vr.var_name
    ->
      Report.report
        (with_function_label
           (Diag.error target.span
              (sprintf "Cannot assign to function '%s'" vr.var_name)
              "")
           (Hashtbl.find_opt c.funcs vr.var_name)
           "Function defined here");
      target.ty <- Err;
      Err
  | _ -> check_value c target None

let with_target_decl d (target : expr) =
  match target.kind with
  | Var { var_sym = Some sym; _ } ->
      Diag.with_label d sym.sym_type_span
        (sprintf "'%s' is declared as %s here" sym.sym_name (ty_name sym.sym_ty))
  | _ -> d

let check_assign c a =
  let target = a.a_target in
  let tt = check_target c target in
  report_assign_place target (place_of target);
  match a.a_op with
  | None ->
      let vt = check_value c a.a_value (Some tt) in
      if not (coerce a.a_value vt tt) then
        Report.report
          (explain
             (with_target_decl
                (Diag.error a.a_value.span
                   (sprintf
                      "Cannot assign a value of type %s to '%s' of type %s"
                      (ty_name vt)
                      (quoted_source target.span)
                      (ty_name tt))
                   (this_is vt))
                target)
             a.a_value vt tt)
  | Some op ->
      let vt = check_value c a.a_value (number_hint tt) in
      let rt =
        binary_type (binop_text op ^ "=") op a.a_op_span target tt a.a_value vt
      in
      if mismatch rt tt then
        Report.report
          (Diag.with_label
             (Diag.with_label
                (Diag.error a.a_op_span
                   (sprintf
                      "Operator '%s=' gives a value of type %s, which cannot \
                       be stored in '%s' of type %s"
                      (binop_text op) (ty_name rt)
                      (quoted_source target.span)
                      (ty_name tt))
                   "")
                target.span (ty_name tt))
             a.a_value.span (ty_name vt))

(* A secondary label at the function's return type, if it has one. *)
let with_return_label d f =
  match f.ret_ann with
  | Some ann ->
      Diag.with_label d ann.t_span
        (sprintf "Declared to return %s here" (ty_name f.ret_ty))
  | None -> d

let rec check_stmt c s =
  match s.skind with
  | Call_stmt e -> ignore (check_expr c e None)
  | Decl d -> check_decl c d
  | Assign a -> check_assign c a
  | Block b -> check_block c b
  | If ifs -> check_if c ifs
  | While w ->
      check_cond c "while" w.w_cond;
      check_block c w.w_body
  | Return r -> check_return c r

and check_return c r =
  let f =
    match c.cur_func with
    | Some f -> f
    | None -> failwith "check_return: outside a function"
  in
  match r.ret_value with
  | None ->
      if is_not f.ret_ty Void then
        Report.report
          (with_return_label
             (Diag.error r.ret_kw_span
                (sprintf "'%s' returns %s, but this 'return' has no value"
                   f.f_name (ty_name f.ret_ty))
                "Needs a value")
             f)
  | Some e ->
      if f.ret_ty = Void then begin
        Report.report
          (Diag.with_help
             (Diag.with_label
                (Diag.error e.span
                   (sprintf
                      "'%s' returns nothing, but this 'return' has a value"
                      f.f_name)
                   "")
                f.f_name_span "Declared here with no return type")
             (sprintf "Remove the value, or give '%s' a return type" f.f_name)
             []);
        ignore (check_expr c e None)
      end
      else
        let t = check_value c e (Some f.ret_ty) in
        if not (coerce e t f.ret_ty) then
          Report.report
            (explain
               (with_return_label
                  (Diag.error e.span
                     (sprintf
                        "'%s' returns %s, but this 'return' has a value of \
                         type %s"
                        f.f_name (ty_name f.ret_ty) (ty_name t))
                     (this_is t))
                  f)
               e t f.ret_ty)

and check_cond c keyword e =
  let t = check_value c e None in
  if is_not t Bool then begin
    let d =
      Diag.error e.span
        (sprintf "Condition of '%s' must be bool, found %s" keyword (ty_name t))
        "Expected bool"
    in
    Report.report
      (if is_int t then
         Diag.with_help d "To test for nonzero, compare it"
           [ Diag.edit (Diag.point_after e.span) " != 0" ]
       else d)
  end

and check_if c ifs =
  check_cond c "if" ifs.cond;
  check_block c ifs.then_block;
  match ifs.else_part with
  | No_else -> ()
  | Else_block b -> check_block c b
  | Else_if inner -> check_if c inner

and check_block c b =
  open_scope c;
  List.iter (check_stmt c) b.stmts;
  close_scope c

(* Whether every path through a block ends in a return. A deliberately simple
   rule: a block returns if any statement in it returns, and an 'if' returns
   only when it has an 'else' and every branch returns. Loops never count. *)
let rec block_returns b = List.exists stmt_returns b.stmts

and stmt_returns s =
  match s.skind with
  | Return _ -> true
  | Block b -> block_returns b
  | If ifs -> if_returns ifs
  | Decl _ | Assign _ | Call_stmt _ | While _ -> false

and if_returns ifs =
  block_returns ifs.then_block
  &&
  match ifs.else_part with
  | No_else -> false
  | Else_block b -> block_returns b
  | Else_if inner -> if_returns inner

(* Whether a 'return' appears anywhere inside a 'while' in this block, for
   the note on why it does not count. *)
let rec block_has_loop_return b = List.exists stmt_has_loop_return b.stmts

and stmt_has_loop_return s =
  match s.skind with
  | While w -> block_has_return w.w_body
  | Block b -> block_has_loop_return b
  | If ifs -> if_has_loop_return ifs
  | Decl _ | Assign _ | Call_stmt _ | Return _ -> false

and if_has_loop_return ifs =
  block_has_loop_return ifs.then_block
  ||
  match ifs.else_part with
  | No_else -> false
  | Else_block b -> block_has_loop_return b
  | Else_if inner -> if_has_loop_return inner

and block_has_return b = List.exists stmt_has_return b.stmts

and stmt_has_return s =
  match s.skind with
  | Return _ -> true
  | While w -> block_has_return w.w_body
  | Block b -> block_has_return b
  | If ifs -> if_has_return ifs
  | Decl _ | Assign _ | Call_stmt _ -> false

and if_has_return ifs =
  block_has_return ifs.then_block
  ||
  match ifs.else_part with
  | No_else -> false
  | Else_block b -> block_has_return b
  | Else_if inner -> if_has_return inner

let add_param c prm ty =
  if check_name_free c prm.p_name prm.p_span None then begin
    let mut_edit = Diag.edit (Diag.point_before prm.p_ann.t_span) "mut " in
    prm.p_sym <-
      Some
        (add_local c prm.p_name prm.p_span prm.p_ann.t_span ty prm.p_mut true
           mut_edit
           (ptr_edit ty (Some prm.p_ann) None))
  end

let rec add_params c params tys =
  match (params, tys) with
  | prm :: rest, ty :: rest_tys ->
      add_param c prm ty;
      add_params c rest rest_tys
  | _ -> ()

let missing_return f =
  let d =
    Diag.error f.body.close_span
      (sprintf "'%s' is missing a return: not every path returns a value"
         f.f_name)
      "Can reach the end without returning"
  in
  let d = with_return_label d f in
  Report.report
    (if block_has_loop_return f.body then
       Diag.with_note d
         "A 'return' inside a 'while' loop does not count, because the loop \
          might not run"
     else d)

let rec check_foreign_params (params : param list) =
  match params with
  | [] -> ()
  | prm :: rest ->
      if prm.p_mut then
        Report.report
          (Diag.error prm.p_span
             "Parameters of a foreign function cannot be 'mut'" "Declared 'mut'");
      check_foreign_params rest

let check_body c f =
  c.cur_func <- Some f;
  c.next_id <- 1;
  c.ended <- [];
  open_scope c;
  add_params c f.params f.param_tys;
  check_block c f.body;
  close_scope c;
  if is_not f.ret_ty Void && not (block_returns f.body) then missing_return f;
  f.nsyms <- c.next_id - 1;
  c.cur_func <- None

(* A foreign function has no body; only its signature is checked. *)
let check_func c f =
  if f.f_foreign <> None then check_foreign_params f.params else check_body c f

let declare_const c cd =
  match global_meaning c cd.c_name with
  | Const_name prev ->
      Report.report
        (Diag.with_label
           (Diag.error cd.c_name_span
              (sprintf "Constant '%s' is already defined" cd.c_name)
              "Defined again here")
           prev.c_name_span "First defined here")
  | Free -> Hashtbl.replace c.consts cd.c_name cd
  | _ -> ignore (check_global_free c cd.c_name cd.c_name_span)

let check_const_decl c cd = ignore (check_const c cd None)

let check_file (file : file) =
  let c =
    {
      file = file.path;
      funcs = Hashtbl.create 16;
      structs = Hashtbl.create 16;
      consts = Hashtbl.create 16;
      locals = Hashtbl.create 16;
      scopes = [];
      ended = [];
      next_id = 1;
      cur_func = None;
    }
  in
  List.iter (declare_struct c) file.structs;
  List.iter (declare_const c) file.consts;
  List.iter (check_struct_fields c) file.structs;
  let reported = ref [] in
  List.iter (check_cycle c reported) file.structs;
  List.iter (declare_func c) file.funcs;
  if not (Hashtbl.mem c.funcs "main") then
    Report.report
      (Diag.with_help
         (Diag.file_error c.file "No 'main' function found")
         "Add one, like 'main :: fn() { }'" []);
  (* Constants are checked on first use; this checks the unused ones, and
     those used only by other constants, in order. *)
  List.iter (check_const_decl c) file.consts;
  List.iter (check_func c) file.funcs
