(* Turns the checked AST into C source text.

   Slick evaluates strictly left to right; C leaves the order of call
   arguments, operands and initializers unspecified. So [emit_expr] returns a
   C expression and may first write statements (declarations of temporaries)
   to the output, which fix the order:
   - every call that returns a value is stored in a temporary;
   - an operand is stored in a temporary before a later operand that has a
     side effect (a call, or an integer division that can panic) is
     evaluated;
   - the right side of && and ||, and the conditions of 'while' and 'else
     if', are emitted into a separate buffer first, so that any statements
     they need can be placed where they only run when they should.

   Every C expression has exactly the C type of its Slick type. C promotes
   types narrower than int, so arithmetic on them is cast back, and implicit
   conversions are written as casts. *)

open Ast

type emitter = {
  mutable out : Buffer.t;
  mutable indent : int;
  mutable next_tmp : int; (* temporaries continue the function's symbol ids *)
  (* The panic messages, as C definitions, in reverse. *)
  mutable sites : string list;
  mutable next_site : int;
  (* The runtime helpers the program uses, by name. *)
  mutable helpers : string list;
  structs : (string, struct_decl) Hashtbl.t;
  funcs : (string, func) Hashtbl.t;
}

let sprintf = Printf.sprintf

let line em s =
  Buffer.add_string em.out (String.make (4 * em.indent) ' ');
  Buffer.add_string em.out s;
  Buffer.add_char em.out '\n'

(* Redirects output to a fresh buffer, one level deeper. *)
let start_capture em =
  let saved = em.out in
  em.out <- Buffer.create 256;
  em.indent <- em.indent + 1;
  saved

(* Ends a capture and returns what was written. *)
let finish_capture em saved =
  let captured = Buffer.contents em.out in
  em.out <- saved;
  em.indent <- em.indent - 1;
  captured

(* A C string literal holding [s], for panic messages. *)
let c_string_literal s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  for i = 0 to String.length s - 1 do
    let ch = s.[i] in
    if ch = '"' then Buffer.add_string b "\\\""
    else if ch = '\\' then Buffer.add_string b "\\\\"
    else if ch = '\n' then Buffer.add_string b "\\n"
    else if Char.code ch < 32 || Char.code ch > 126 then
      Buffer.add_string b (sprintf "\\%03o" (Char.code ch))
    else Buffer.add_char b ch
  done;
  Buffer.add_char b '"';
  Buffer.contents b

(* ---- Types ---- *)

let c_int_type k =
  match k with
  | I8 -> "int8_t"
  | I16 -> "int16_t"
  | I32 -> "int32_t"
  | I64 -> "int64_t"
  | U8 -> "uint8_t"
  | U16 -> "uint16_t"
  | U32 -> "uint32_t"
  | U64 -> "uint64_t"

let unsigned_of k =
  match k with I8 -> U8 | I16 -> U16 | I32 -> U32 | I64 -> U64 | k -> k

let c_struct_name name = "slickT_" ^ name

(* '*T' is 'T const *', written with const on the right so that nested
   pointers compose: '*mut *T' is 'T const * *'. C is only emitted for
   programs with no errors, so [Err] never gets here. *)
let rec c_type t =
  match t with
  | Int_ty k -> c_int_type k
  | Float_ty F32 -> "float"
  | Float_ty F64 -> "double"
  | Bool -> "bool"
  | Void -> "void"
  | Ptr (true, t) -> c_type t ^ " *"
  | Ptr (false, t) -> c_type t ^ " const *"
  | Struct name -> c_struct_name name
  | Cstring -> "const char *"
  | Err -> failwith "emit: error type"

(* Field 'x' is 'f_x', which keeps it clear of C keywords and of macros
   such as 'bool'. *)
let c_field name = "f_" ^ name

(* An empty struct gets this field, since C has no empty structs. *)
let unused_field = "unused_"

let find_struct em name =
  match Hashtbl.find_opt em.structs name with
  | Some sd -> sd
  | None -> failwith ("emit: unknown struct " ^ name)

(* Every field is written out, so no C compiler warns about missing ones. *)
let rec c_zero em t =
  match t with
  | Int_ty _ -> "0"
  | Float_ty F32 -> "0.0f"
  | Float_ty F64 -> "0.0"
  | Bool -> "false"
  | Ptr _ -> "0" (* never needed: a pointer must be given a value *)
  | Cstring -> "\"\"" (* never needed, for the same reason *)
  | Struct name ->
      let sd = find_struct em name in
      "(" ^ c_type t ^ "){ " ^ zero_fields em sd.s_fields ^ " }"
  | Void | Err -> failwith "emit: no zero value"

and zero_fields em (fields : field list) =
  match fields with
  | [] -> "." ^ unused_field ^ " = 0"
  | _ -> String.concat ", " (List.map (zero_field em) fields)

and zero_field em (f : field) =
  "." ^ c_field f.fd_name ^ " = " ^ c_zero em f.fd_ty

let c_func_name name = "slick_" ^ name

(* A foreign function's C name. The linker sees its real symbol through an
   assembler label (see [foreign_prelude]). *)
let c_foreign_name name = "slickf_" ^ name

let c_callee em name =
  match Hashtbl.find_opt em.funcs name with
  | Some { f_foreign = Some _; _ } -> c_foreign_name name
  | _ -> c_func_name name

let starts_with s prefix =
  String.length s >= String.length prefix
  && String.sub s 0 (String.length prefix) = prefix

(* Locals are '<name>_<id>', which keeps them clear of C keywords and of the
   compiler's 'tmp_<id>' temporaries. A local starting with 'slick' gets a
   'u_' prefix so it can never equal a function's 'slick_<name>' or a
   struct's 'slickT_<name>'. *)
let c_local_name sym =
  let base = sym.sym_name ^ "_" ^ string_of_int sym.sym_id in
  if starts_with sym.sym_name "slick" then "u_" ^ base else base

let sym_of vr =
  match vr.var_sym with
  | Some sym -> sym
  | None -> failwith "emit: unresolved name"

(* ---- The runtime ---- *)

let includes =
  [
    "#include <inttypes.h>";
    "#include <stdbool.h>";
    "#include <stdint.h>";
    "#include <stdio.h>";
    "#include <stdlib.h>";
    "#include <string.h>";
  ]

let panic_text =
  "/* Prints a message the compiler rendered in advance, with the source line, \
   and exits. */\n\
   static _Noreturn void slickrt_panic(const char *msg) {\n\
  \    fflush(stdout);\n\
  \    fputs(msg, stderr);\n\
  \    exit(1);\n\
   }"

let int_print_format k =
  match k with
  | I8 -> "PRId8"
  | I16 -> "PRId16"
  | I32 -> "PRId32"
  | I64 -> "PRId64"
  | U8 -> "PRIu8"
  | U16 -> "PRIu16"
  | U32 -> "PRIu32"
  | U64 -> "PRIu64"

let print_int_text k =
  sprintf "static void slickrt_print_%s(%s v) { printf(\"%%\" %s \"\\n\", v); }"
    (int_kind_name k) (c_int_type k) (int_print_format k)

(* The shortest text that reads back as the same value: the fewest
   significant digits that round-trip, written out in full for moderate
   exponents and in exponent form otherwise, as Python does. *)
let put_float_text =
  "static void slickrt_put_float(double v, int max_digits, int single) {\n\
  \    char buf[64];\n\
  \    if (v != v) { puts(\"nan\"); return; }\n\
  \    if (v - v != 0) { puts(v < 0 ? \"-inf\" : \"inf\"); return; }\n\
  \    int digits = 1;\n\
  \    for (; digits < max_digits; digits++) {\n\
  \        snprintf(buf, sizeof buf, \"%.*e\", digits - 1, v);\n\
  \        if (single ? strtof(buf, NULL) == (float)v : strtod(buf, NULL) == \
   v) break;\n\
  \    }\n\
  \    snprintf(buf, sizeof buf, \"%.*e\", digits - 1, v);\n\
  \    int exp = atoi(strchr(buf, 'e') + 1);\n\
  \    if (exp >= -4 && exp < 16) {\n\
  \        int decimals = digits - 1 - exp;\n\
  \        snprintf(buf, sizeof buf, \"%.*f\", decimals < 0 ? 0 : decimals, v);\n\
  \        if (!strchr(buf, '.')) strcat(buf, \".0\");\n\
  \    }\n\
  \    puts(buf);\n\
   }"

let print_fixed_text =
  "/* print(x, n): n digits after the point. printf takes an int, so n is \
   capped. */\n\
   static void slickrt_print_fixed(double v, int64_t n, const char *site) {\n\
  \    if (n < 0) slickrt_panic(site);\n\
  \    if (n > 1000) n = 1000;\n\
  \    printf(\"%.*f\\n\", (int)n, v);\n\
   }"

(* INT_MIN / -1 overflows, which traps on x86; Slick wraps it. *)
let div_text k =
  let n = int_kind_name k in
  let t = c_int_type k in
  if is_signed k then
    let ut = c_int_type (unsigned_of k) in
    sprintf
      "static %s slickrt_div_%s(%s a, %s b, const char *site) {\n\
      \    if (b == 0) slickrt_panic(site);\n\
      \    if (b == -1) return (%s)(0u - (%s)a);\n\
      \    return (%s)(a / b);\n\
       }\n\n\
       static %s slickrt_rem_%s(%s a, %s b, const char *site) {\n\
      \    if (b == 0) slickrt_panic(site);\n\
      \    if (b == -1) return 0;\n\
      \    return (%s)(a %% b);\n\
       }"
      t n t t t ut t t n t t t
  else
    sprintf
      "static %s slickrt_div_%s(%s a, %s b, const char *site) {\n\
      \    if (b == 0) slickrt_panic(site);\n\
      \    return (%s)(a / b);\n\
       }\n\n\
       static %s slickrt_rem_%s(%s a, %s b, const char *site) {\n\
      \    if (b == 0) slickrt_panic(site);\n\
      \    return (%s)(a %% b);\n\
       }"
      t n t t t t n t t t

(* The bounds of each integer type as doubles. Both are powers of two, so
   they are exact. *)
let f2i_bounds k =
  match k with
  | I8 -> ("-128.0", "128.0")
  | I16 -> ("-32768.0", "32768.0")
  | I32 -> ("-2147483648.0", "2147483648.0")
  | I64 -> ("-9223372036854775808.0", "9223372036854775808.0")
  | U8 -> ("-1.0", "256.0")
  | U16 -> ("-1.0", "65536.0")
  | U32 -> ("-1.0", "4294967296.0")
  | U64 -> ("-1.0", "18446744073709551616.0")

let c_limit k suffix =
  String.uppercase_ascii
    (String.sub (c_int_type k) 0 (String.length (c_int_type k) - 2))
  ^ suffix

(* Float to integer saturates, as in Rust: C leaves out-of-range values
   undefined. *)
let f2i_text k =
  let lo, hi = f2i_bounds k in
  let min = if is_signed k then c_limit k "_MIN" else "0" in
  sprintf
    "static %s slickrt_f2i_%s(double v) {\n\
    \    if (v != v) return 0;\n\
    \    if (v <= %s) return %s;\n\
    \    if (v >= %s) return %s;\n\
    \    return (%s)v;\n\
     }"
    (c_int_type k) (int_kind_name k) lo min hi (c_limit k "_MAX") (c_int_type k)

(* The text of helper [name], if it is [prefix] followed by a kind. *)
let rec by_kind name prefix text kinds =
  match kinds with
  | [] -> None
  | k :: rest ->
      if name = prefix ^ int_kind_name k then Some (text k)
      else by_kind name prefix text rest

let helper_text name =
  match name with
  | "panic" -> panic_text
  | "print_bool" ->
      "static void slickrt_print_bool(bool v) { puts(v ? \"true\" : \
       \"false\"); }"
  | "print_cstring" ->
      "static void slickrt_print_cstring(const char *v) { puts(v); }"
  | "put_float" -> put_float_text
  | "print_f32" ->
      "static void slickrt_print_f32(float v) { slickrt_put_float(v, 9, 1); }"
  | "print_f64" ->
      "static void slickrt_print_f64(double v) { slickrt_put_float(v, 17, 0); }"
  | "print_fixed" -> print_fixed_text
  | _ -> (
      match by_kind name "print_" print_int_text all_int_kinds with
      | Some text -> text
      | None -> (
          match by_kind name "div_" div_text all_int_kinds with
          | Some text -> text
          | None -> (
              match by_kind name "f2i_" f2i_text all_int_kinds with
              | Some text -> text
              | None -> failwith ("emit: unknown helper " ^ name))))

let kind_helper prefix k = prefix ^ int_kind_name k

(* Every helper, in the order they are written out. *)
let helper_order =
  [ "panic"; "print_bool"; "print_cstring" ]
  @ List.map (kind_helper "print_") all_int_kinds
  @ [ "put_float"; "print_f32"; "print_f64"; "print_fixed" ]
  @ List.map (kind_helper "div_") all_int_kinds
  @ List.map (kind_helper "f2i_") all_int_kinds

let rec need em name =
  if not (List.mem name em.helpers) then begin
    em.helpers <- name :: em.helpers;
    if starts_with name "div_" || name = "print_fixed" then need em "panic";
    if name = "print_f32" || name = "print_f64" then need em "put_float"
  end

(* Renders a runtime panic at [span] and returns the name of the C string
   that holds it. *)
let panic_site em message (span : Diag.span) label =
  let d = { (Diag.error span message label) with severity = Diag.Panic } in
  let name = "slickrt_site_" ^ string_of_int em.next_site in
  em.next_site <- em.next_site + 1;
  em.sites <-
    sprintf "static const char %s[] = %s;" name
      (c_string_literal (Report.render_plain d))
    :: em.sites;
  name

(* ---- Expressions ---- *)

(* A C expression. [atomic]: usable as an operand without parentheses.
   [stable]: a literal, a temporary or a fixed address, whose value nothing
   can change, so it never needs to be saved before a later side effect. *)
type cexpr = { code : string; atomic : bool; stable : bool }

let atom code = { code; atomic = true; stable = false }
let compound code = { code; atomic = false; stable = false }
let literal code = { code; atomic = true; stable = true }

(* Every non-atomic operand is parenthesized, so C precedence never matters.
   The whole expression is not, since 'if ((a == b))' makes clang warn. *)
let operand ce = if ce.atomic then ce.code else "(" ^ ce.code ^ ")"

let is_narrow t =
  match t with Int_ty (I8 | I16 | U8 | U16) -> true | _ -> false

(* C computes in int for types narrower than int; this casts back. *)
let narrow t ce =
  if is_narrow t then compound ("(" ^ c_type t ^ ")(" ^ ce.code ^ ")") else ce

let c_binop op =
  match op with
  | Add -> "+"
  | Sub -> "-"
  | Mul -> "*"
  | Div -> "/"
  | Band -> "&"
  | Bor -> "|"
  | Bxor -> "^"
  | Eq -> "=="
  | Ne -> "!="
  | Lt -> "<"
  | Le -> "<="
  | Gt -> ">"
  | Ge -> ">="
  | And -> "&&"
  | Or -> "||"
  | Rem | Shl | Shr -> failwith "c_binop: handled separately"

(* The type of [e] after any implicit conversion. *)
let final_ty e = match e.conv with Some t -> t | None -> e.ty

(* Whether evaluating [e] can do something observable: call a function, or
   divide integers (which can panic). *)
let rec has_effect e =
  match e.kind with
  | Call _ -> true
  | Binary b ->
      ((b.op = Div || b.op = Rem) && is_int e.ty)
      || has_effect b.lhs || has_effect b.rhs
  | Unary (_, x) | Deref x | Addr_of (_, x) | Cast (_, _, x) -> has_effect x
  | Field fa -> has_effect fa.obj
  | Struct_lit sl -> List.exists item_has_effect sl.items
  | Var { var_const = Some c; _ } -> has_effect c.c_value
  | Int _ | Float _ | Bool_lit _ | String_lit _ | Var _ -> false

and item_has_effect (i : lit_item) = has_effect i.i_value

let item_value (i : lit_item) = i.i_value

(* A place whose address cannot change: a local, or a field of one. *)
let rec fixed_place e =
  match e.kind with
  | Var _ -> true
  | Field fa -> (not fa.through_ptr) && fixed_place fa.obj
  | _ -> false

let new_tmp em =
  let n = em.next_tmp in
  em.next_tmp <- n + 1;
  "tmp_" ^ string_of_int n

(* Writes 'T tmp = code;' now and returns the temporary. *)
let store em ty code =
  let t = new_tmp em in
  line em (c_type ty ^ " " ^ t ^ " = " ^ code ^ ";");
  { code = t; atomic = true; stable = true }

let int_literal t (lit : int_lit) =
  let mag = sprintf "%Lu" lit.value in
  let sign = if lit.neg then "-" else "" in
  match t with
  | Float_ty F32 -> sign ^ mag ^ ".0f"
  | Float_ty F64 -> sign ^ mag ^ ".0"
  (* In C, 2147483648 is a long, so the minimums are written by name. *)
  | Int_ty I32 when lit.neg && lit.value = 2147483648L -> "INT32_MIN"
  | Int_ty I64 when lit.neg && lit.value = Int64.min_int -> "INT64_MIN"
  | Int_ty I64 -> sign ^ "INT64_C(" ^ mag ^ ")"
  | Int_ty U32 -> mag ^ "u"
  | Int_ty U64 -> "UINT64_C(" ^ mag ^ ")"
  | _ -> sign ^ mag

let signed_literal code =
  if String.length code > 0 && code.[0] = '-' then
    { code; atomic = false; stable = true }
  else literal code

let shift_code op k l r =
  let bits = int_bits k in
  let t = c_int_type k in
  let amount = sprintf "(%s & %d)" (operand r) (bits - 1) in
  match op with
  | Shl when is_signed k ->
      (* Shifting a negative value left is undefined in C, so the shift is
         done in the unsigned type. *)
      compound
        (sprintf "(%s)((%s)%s << %s)" t
           (c_int_type (unsigned_of k))
           (operand l) amount)
  | Shl ->
      if bits < 32 then compound (sprintf "(%s)(%s << %s)" t (operand l) amount)
      else compound (sprintf "%s << %s" (operand l) amount)
  | _ ->
      if bits < 32 then compound (sprintf "(%s)(%s >> %s)" t (operand l) amount)
      else compound (sprintf "%s >> %s" (operand l) amount)

(* [l op r], where [ty] is the result type and [rhs] the right operand, for
   the panic message of a division. *)
let binary_code em op ty (rhs : expr) l r =
  match (op, ty) with
  | (Div | Rem), Int_ty k ->
      let n = int_kind_name k in
      need em ("div_" ^ n);
      let message =
        if op = Div then "Division by zero" else "Remainder by zero"
      in
      atom
        (sprintf "slickrt_%s_%s(%s, %s, %s)"
           (if op = Div then "div" else "rem")
           n l.code r.code
           (panic_site em message rhs.span "This is zero"))
  | (Shl | Shr), Int_ty k -> shift_code op k l r
  | (Eq | Ne | Lt | Le | Gt | Ge), _ ->
      compound (operand l ^ " " ^ c_binop op ^ " " ^ operand r)
  | _ -> narrow ty (compound (operand l ^ " " ^ c_binop op ^ " " ^ operand r))

let rec emit_expr em e =
  let ce = emit_raw em e in
  match e.conv with
  | None -> ce
  | Some t ->
      {
        code = "(" ^ c_type t ^ ")" ^ operand ce;
        atomic = false;
        stable = ce.stable;
      }

and emit_raw em e =
  match e.kind with
  | Int lit -> signed_literal (int_literal e.ty lit)
  | Float lit ->
      let sign = if lit.fneg then "-" else "" in
      let suffix = if e.ty = Float_ty F32 then "f" else "" in
      signed_literal (sign ^ lit.text ^ suffix)
  | Bool_lit b -> literal (if b then "true" else "false")
  | Var { var_const = Some c; _ } ->
      (* A constant's checked value, emitted in place. Nothing can change
         it. *)
      let ce = emit_expr em c.c_value in
      { code = operand ce; atomic = true; stable = true }
  | Var vr -> atom (c_local_name (sym_of vr))
  | String_lit s -> literal (c_string_literal s)
  | Call call -> store em e.ty (emit_call em call)
  | Unary (Neg, x) -> narrow e.ty (compound ("-" ^ operand (emit_expr em x)))
  | Unary (Bnot, x) -> narrow e.ty (compound ("~" ^ operand (emit_expr em x)))
  | Unary (Not, x) -> compound ("!" ^ operand (emit_expr em x))
  | Binary b -> (
      match b.op with
      | And | Or -> emit_short_circuit em b
      | _ -> emit_binary em e.ty b)
  | Field fa ->
      let o = emit_expr em fa.obj in
      atom
        (operand o ^ (if fa.through_ptr then "->" else ".") ^ c_field fa.field)
  | Deref x -> atom ("(*" ^ operand (emit_expr em x) ^ ")")
  | Addr_of (_, x) ->
      let ce = emit_expr em x in
      { code = "&" ^ operand ce; atomic = false; stable = fixed_place x }
  | Cast (kind, _, x) -> emit_cast em e.ty kind x
  | Struct_lit sl -> emit_struct_lit em e.ty sl

and emit_binary em ty b =
  let l = emit_expr em b.lhs in
  let l =
    if has_effect b.rhs && not l.stable then store em (final_ty b.lhs) l.code
    else l
  in
  let r = emit_expr em b.rhs in
  binary_code em b.op ty b.rhs l r

(* 'a && b': if b needs no statements, C's own && is right. Otherwise b's
   statements must only run when a is true:
     bool tmp = a; if (tmp) { <b's statements> tmp = b; }
   and the same with 'if (!tmp)' for ||. *)
and emit_short_circuit em b =
  let l = emit_expr em b.lhs in
  let saved = start_capture em in
  let r = emit_expr em b.rhs in
  let r_stmts = finish_capture em saved in
  if r_stmts = "" then
    compound (operand l ^ " " ^ c_binop b.op ^ " " ^ operand r)
  else begin
    let t = new_tmp em in
    line em ("bool " ^ t ^ " = " ^ l.code ^ ";");
    line em (if b.op = And then "if (" ^ t ^ ") {" else "if (!" ^ t ^ ") {");
    Buffer.add_string em.out r_stmts;
    em.indent <- em.indent + 1;
    line em (t ^ " = " ^ r.code ^ ";");
    em.indent <- em.indent - 1;
    line em "}";
    { code = t; atomic = true; stable = true }
  end

(* Each value is saved before a later value with a side effect runs. Used
   for call arguments and struct literal fields. *)
and emit_values em (values : expr list) acc =
  match values with
  | [] -> List.rev acc
  | v :: rest ->
      let ce = emit_expr em v in
      let ce =
        if List.exists has_effect rest && not ce.stable then
          store em (final_ty v) ce.code
        else ce
      in
      emit_values em rest (ce.code :: acc)

(* The call itself, as C text, after its arguments' statements. *)
and emit_call em call =
  if call.callee = "print" then emit_print em call
  else
    let args = emit_values em call.args [] in
    c_callee em call.callee ^ "(" ^ String.concat ", " args ^ ")"

and emit_print em call =
  let args = emit_values em call.args [] in
  match (call.args, args) with
  | [ x ], [ v ] ->
      let name =
        match x.ty with
        | Int_ty k -> "print_" ^ int_kind_name k
        | Float_ty k -> "print_" ^ float_kind_name k
        | Cstring -> "print_cstring"
        | _ -> "print_bool"
      in
      need em name;
      "slickrt_" ^ name ^ "(" ^ v ^ ")"
  | [ _; n ], [ v; nv ] ->
      need em "print_fixed";
      (* A literal precision cannot be negative: the checker made sure. *)
      let site =
        match n.kind with
        | Int _ -> "NULL"
        | _ ->
            panic_site em "Precision cannot be negative" n.span
              "This is negative"
      in
      sprintf "slickrt_print_fixed(%s, (int64_t)(%s), %s)" v nv site
  | _ -> failwith "emit: print with a wrong number of arguments"

and emit_cast em ty kind x =
  let ce = emit_expr em x in
  let from = final_ty x in
  if from = ty then ce
  else
    match (kind, from, ty) with
    | Convert, Float_ty _, Int_ty k ->
        need em ("f2i_" ^ int_kind_name k);
        atom (sprintf "slickrt_f2i_%s(%s)" (int_kind_name k) ce.code)
    | Convert, _, _ -> compound ("(" ^ c_type ty ^ ")" ^ operand ce)
    | Bits, _, _ ->
        (* A union compound literal reinterprets the bits, which C11 allows. *)
        atom
          (sprintf "((union { %s a; %s b; }){ .a = %s }).b" (c_type from)
             (c_type ty) ce.code)

(* A compound literal with every field written out, in declaration order.
   The values are computed first, in source order. *)
and emit_struct_lit em ty sl =
  let name =
    match ty with Struct n -> n | _ -> failwith "emit: struct type"
  in
  let sd = find_struct em name in
  let values = emit_values em (List.map item_value sl.items) [] in
  let given = name_values sd.s_fields sl.items values in
  let fields =
    match sd.s_fields with
    | [] -> "." ^ unused_field ^ " = 0"
    | _ -> String.concat ", " (List.map (field_init em given) sd.s_fields)
  in
  atom ("(" ^ c_type ty ^ "){ " ^ fields ^ " }")

(* '.f_x = value', with the value given in the literal, or zero. *)
and field_init em given (f : field) =
  let value =
    match List.assoc_opt f.fd_name given with
    | Some code -> code
    | None -> c_zero em f.fd_ty
  in
  "." ^ c_field f.fd_name ^ " = " ^ value

(* Pairs each value with its field's name; positional values go to the
   fields in order. *)
and name_values (fields : field list) (items : lit_item list) values =
  match (items, values) with
  | item :: irest, v :: vrest -> (
      match item.i_name with
      | Some (n, _) -> (n, v) :: name_values fields irest vrest
      | None -> (
          match fields with
          | f :: frest -> (f.fd_name, v) :: name_values frest irest vrest
          | [] -> []))
  | _ -> []

(* ---- Statements ---- *)

(* The C place an assignment writes to. The target is evaluated first, as
   left to right requires: a place that is not fixed and whose address
   could be affected, or is computed with a side effect, has its address
   saved in a temporary before the value is evaluated. *)
let emit_place em (a : assign) =
  let target = a.a_target in
  let place = emit_expr em target in
  if fixed_place target || not (has_effect target || has_effect a.a_value) then
    place.code
  else begin
    let t = new_tmp em in
    line em
      (c_type (Ptr (true, target.ty)) ^ " " ^ t ^ " = &" ^ operand place ^ ";");
    "(*" ^ t ^ ")"
  end

let rec emit_stmt em s =
  match s.skind with
  | Call_stmt e -> (
      match e.kind with
      | Call call -> line em (emit_call em call ^ ";")
      | _ -> failwith "emit_stmt: call statement without a call")
  | Decl d ->
      let sym =
        match d.d_sym with
        | Some sym -> sym
        | None -> failwith "emit: unchecked decl"
      in
      let value =
        match d.d_init with
        | Some init -> (emit_expr em init).code
        | None -> c_zero em sym.sym_ty
      in
      line em (c_type sym.sym_ty ^ " " ^ c_local_name sym ^ " = " ^ value ^ ";")
  | Assign a -> (
      let place = emit_place em a in
      match a.a_op with
      | None ->
          let value = emit_expr em a.a_value in
          line em (place ^ " = " ^ value.code ^ ";")
      | Some op ->
          (* 'x op= v' reads x, then evaluates v, then stores x op v. *)
          let ty = a.a_target.ty in
          let old = { code = place; atomic = true; stable = false } in
          let old =
            if has_effect a.a_value then store em ty old.code else old
          in
          let value = emit_expr em a.a_value in
          let result = binary_code em op ty a.a_value old value in
          line em (place ^ " = " ^ result.code ^ ";"))
  | Block b ->
      line em "{";
      emit_body em b;
      line em "}"
  | If ifs ->
      let cond = (emit_expr em ifs.cond).code in
      line em ("if (" ^ cond ^ ") {");
      emit_body em ifs.then_block;
      emit_else em ifs.else_part
  | While w -> emit_while em w
  | Return { ret_value = None; _ } -> line em "return;"
  | Return { ret_value = Some e; _ } ->
      let value = (emit_expr em e).code in
      line em ("return " ^ value ^ ";")

(* Emits from the '}' that closes the then-block onward. An 'else if' whose
   condition needs statements becomes 'else { <statements> if ... }', so the
   statements only run when the earlier branches were not taken. *)
and emit_else em else_part =
  match else_part with
  | No_else -> line em "}"
  | Else_block b ->
      line em "} else {";
      emit_body em b;
      line em "}"
  | Else_if inner ->
      let saved = start_capture em in
      let cond = (emit_expr em inner.cond).code in
      let cond_stmts = finish_capture em saved in
      if cond_stmts = "" then begin
        line em ("} else if (" ^ cond ^ ") {");
        emit_body em inner.then_block;
        emit_else em inner.else_part
      end
      else begin
        line em "} else {";
        Buffer.add_string em.out cond_stmts;
        em.indent <- em.indent + 1;
        line em ("if (" ^ cond ^ ") {");
        emit_body em inner.then_block;
        emit_else em inner.else_part;
        em.indent <- em.indent - 1;
        line em "}"
      end

(* A condition that needs statements must run them before every iteration:
     while (1) { <statements> if (!cond) break; <body> } *)
and emit_while em w =
  let saved = start_capture em in
  let cond = emit_expr em w.w_cond in
  let cond_stmts = finish_capture em saved in
  if cond_stmts = "" then begin
    line em ("while (" ^ cond.code ^ ") {");
    emit_body em w.w_body;
    line em "}"
  end
  else begin
    line em "while (1) {";
    Buffer.add_string em.out cond_stmts;
    em.indent <- em.indent + 1;
    line em ("if (!" ^ operand cond ^ ") break;");
    em.indent <- em.indent - 1;
    emit_body em w.w_body;
    line em "}"
  end

and emit_body em b =
  em.indent <- em.indent + 1;
  List.iter (emit_stmt em) b.stmts;
  em.indent <- em.indent - 1

(* ---- Functions, structs and the file ---- *)

let c_param prm =
  match prm.p_sym with
  | Some sym -> c_type sym.sym_ty ^ " " ^ c_local_name sym
  | None -> failwith "emit: unchecked parameter"

let signature f =
  let params =
    if f.params = [] then "void"
    else String.concat ", " (List.map c_param f.params)
  in
  "static " ^ c_type f.ret_ty ^ " " ^ c_func_name f.f_name ^ "(" ^ params ^ ")"

let emit_prototype em f = if f.f_foreign = None then line em (signature f ^ ";")

let emit_func em f =
  if f.f_foreign = None then begin
    em.next_tmp <- f.nsyms + 1;
    line em (signature f ^ " {");
    emit_body em f.body;
    line em "}";
    line em ""
  end

(* Foreign functions are declared under their own C names, with an
   assembler label giving the real symbol. So a binding to libc's 'abs' or
   'puts' never clashes with the declaration in <stdlib.h> or <stdio.h>.
   __USER_LABEL_PREFIX__ is '_' on macOS and empty on Linux; gcc and clang
   both support labels. *)
let foreign_prelude =
  "#define SLICKRT_STR2(x) #x\n\
   #define SLICKRT_STR(x) SLICKRT_STR2(x)\n\
   #define SLICKRT_SYM(name) __asm__(SLICKRT_STR(__USER_LABEL_PREFIX__) name)\n"

let foreign_declaration f =
  match f.f_foreign with
  | None -> None
  | Some fi ->
      let params =
        if f.param_tys = [] then "void"
        else String.concat ", " (List.map c_type f.param_tys)
      in
      Some
        (sprintf "extern %s %s(%s) SLICKRT_SYM(%s);" (c_type f.ret_ty)
           (c_foreign_name f.f_name) params
           (c_string_literal fi.symbol))

let field_line (f : field) =
  "    " ^ c_type f.fd_ty ^ " " ^ c_field f.fd_name ^ ";\n"

let struct_definition (sd : struct_decl) =
  let body =
    match sd.s_fields with
    | [] -> "    char " ^ unused_field ^ ";\n"
    | fields -> String.concat "" (List.map field_line fields)
  in
  "struct " ^ c_struct_name sd.s_name ^ " {\n" ^ body ^ "};\n"

(* Struct definitions in an order where every struct a field holds by value
   comes first. The checker has ruled out cycles. *)
let rec order_struct em (done_ : string list ref) acc (sd : struct_decl) =
  if List.mem sd.s_name !done_ then acc
  else begin
    done_ := sd.s_name :: !done_;
    let acc = order_fields em done_ acc sd.s_fields in
    sd :: acc
  end

and order_fields em done_ acc (fields : field list) =
  match fields with
  | [] -> acc
  | f :: rest ->
      let acc =
        match f.fd_ty with
        | Struct n -> order_struct em done_ acc (find_struct em n)
        | _ -> acc
      in
      order_fields em done_ acc rest

let rec order_structs em done_ acc (structs : struct_decl list) =
  match structs with
  | [] -> acc
  | sd :: rest -> order_structs em done_ (order_struct em done_ acc sd) rest

let register_struct em (sd : struct_decl) =
  Hashtbl.replace em.structs sd.s_name sd

let is_used em name = List.mem name em.helpers
let register_func em (f : func) = Hashtbl.replace em.funcs f.f_name f

let typedef (sd : struct_decl) =
  let name = c_struct_name sd.s_name in
  sprintf "typedef struct %s %s;" name name

(* Lines joined, followed by a blank line; nothing if there are none. *)
let block parts = if parts = [] then "" else String.concat "\n" parts ^ "\n\n"

(* The functions are emitted first, since that is what collects the panic
   messages and runtime helpers, which must come before them in the file. *)
let emit_file (file : file) =
  let em =
    {
      out = Buffer.create 4096;
      indent = 0;
      next_tmp = 1;
      sites = [];
      next_site = 1;
      helpers = [];
      structs = Hashtbl.create 16;
      funcs = Hashtbl.create 16;
    }
  in
  List.iter (register_struct em) file.structs;
  List.iter (register_func em) file.funcs;
  List.iter (emit_prototype em) file.funcs;
  line em "";
  List.iter (emit_func em) file.funcs;
  line em "int main(void) {";
  line em "    slick_main();";
  line em "    return 0;";
  line em "}";
  let helpers = List.filter (is_used em) helper_order in
  let helper_block =
    if helpers = [] then ""
    else String.concat "\n\n" (List.map helper_text helpers) ^ "\n\n"
  in
  let typedefs = List.map typedef file.structs in
  let ordered = List.rev (order_structs em (ref []) [] file.structs) in
  let definitions =
    if ordered = [] then ""
    else String.concat "\n" (List.map struct_definition ordered) ^ "\n"
  in
  let foreign = List.filter_map foreign_declaration file.funcs in
  let foreign_block =
    if foreign = [] then "" else foreign_prelude ^ "\n" ^ block foreign
  in
  String.concat "\n" includes
  ^ "\n\n" ^ helper_block ^ block typedefs ^ definitions ^ foreign_block
  ^ block (List.rev em.sites)
  ^ Buffer.contents em.out
