(* Turns the checked AST into C source text.

   Slick evaluates strictly left to right; C leaves the order of call
   arguments and operands unspecified. So [emit_expr] returns a C expression
   and may first write statements (declarations of temporaries) to the output,
   which fix the order:
   - every call that returns a value is stored in a temporary;
   - an operand is stored in a temporary before a later operand that has a
     side effect (a call, or a division that can panic) is evaluated;
   - the right side of && and ||, and the conditions of 'while' and 'else
     if', are emitted into a separate buffer first, so that any statements
     they need can be placed where they only run when they should. *)

open Ast

type emitter = {
  mutable out : Buffer.t;
  mutable indent : int;
  mutable next_tmp : int; (* temporaries continue the function's symbol ids *)
  (* The panic messages, one per division, as C definitions, in reverse. *)
  mutable sites : string list;
  mutable next_site : int;
}

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
      Buffer.add_string b (Printf.sprintf "\\%03o" (Char.code ch))
    else Buffer.add_char b ch
  done;
  Buffer.add_char b '"';
  Buffer.contents b

(* The runtime. A panic prints a message the compiler rendered in advance,
   with the source line, and exits. *)
let prelude =
  String.concat "\n"
    [
      "#include <inttypes.h>";
      "#include <stdbool.h>";
      "#include <stdint.h>";
      "#include <stdio.h>";
      "#include <stdlib.h>";
      "";
      "static void slickrt_print_i32(int32_t v) { printf(\"%\" PRId32 \"\\n\", \
       v); }";
      "";
      "static _Noreturn void slickrt_panic(const char *msg) {";
      "    fflush(stdout);";
      "    fputs(msg, stderr);";
      "    exit(1);";
      "}";
      "";
      "/* INT32_MIN / -1 overflows, which traps on x86; Slick wraps it. */";
      "static int32_t slickrt_div_i32(int32_t a, int32_t b, const char *site) {";
      "    if (b == 0) slickrt_panic(site);";
      "    if (b == -1) return (int32_t)(0u - (uint32_t)a);";
      "    return a / b;";
      "}";
      "";
      "static int32_t slickrt_rem_i32(int32_t a, int32_t b, const char *site) {";
      "    if (b == 0) slickrt_panic(site);";
      "    if (b == -1) return 0;";
      "    return a % b;";
      "}";
      "";
    ]

(* Renders the panic for a division by zero at [divisor] and returns the
   name of the C string that holds it. *)
let panic_site em op (divisor : expr) =
  let message = if op = Div then "Division by zero" else "Remainder by zero" in
  let d =
    {
      (Diag.error divisor.span message "This is zero") with
      severity = Diag.Panic;
    }
  in
  let name = "slickrt_site_" ^ string_of_int em.next_site in
  em.next_site <- em.next_site + 1;
  em.sites <-
    Printf.sprintf "static const char %s[] = %s;" name
      (c_string_literal (Report.render_plain d))
    :: em.sites;
  name

(* C is only emitted for programs with no errors, so [Err] never gets here. *)
let c_type t =
  match t with
  | I32 -> "int32_t"
  | Bool -> "bool"
  | Void -> "void"
  | Err -> failwith "emit: error type"

let c_zero t =
  match t with
  | I32 -> "0"
  | Bool -> "false"
  | Void -> ""
  | Err -> failwith "emit: error type"

let c_func_name name = "slick_" ^ name

let starts_with s prefix =
  String.length s >= String.length prefix
  && String.sub s 0 (String.length prefix) = prefix

(* Locals are '<name>_<id>', which keeps them clear of C keywords and of the
   compiler's 'tmp_<id>' temporaries. A local starting with 'slick' gets a
   'u_' prefix so it can never equal a function's 'slick_<name>'. *)
let c_local_name sym =
  let base = sym.sym_name ^ "_" ^ string_of_int sym.sym_id in
  if starts_with sym.sym_name "slick" then "u_" ^ base else base

let sym_of vr =
  match vr.var_sym with
  | Some sym -> sym
  | None -> failwith "emit: unresolved name"

(* A C expression. [atomic]: usable as an operand without parentheses.
   [stable]: a literal or a temporary, whose value nothing can change, so it
   never needs to be saved before a later side effect. *)
type cexpr = { code : string; atomic : bool; stable : bool }

let atom code = { code; atomic = true; stable = false }
let compound code = { code; atomic = false; stable = false }
let literal code = { code; atomic = true; stable = true }

(* Every non-atomic operand is parenthesized, so C precedence never matters.
   The whole expression is not, since 'if ((a == b))' makes clang warn. *)
let operand ce = if ce.atomic then ce.code else "(" ^ ce.code ^ ")"

let c_binop op =
  match op with
  | Add -> "+"
  | Sub -> "-"
  | Mul -> "*"
  | Eq -> "=="
  | Ne -> "!="
  | Lt -> "<"
  | Le -> "<="
  | Gt -> ">"
  | Ge -> ">="
  | And -> "&&"
  | Or -> "||"
  | Div | Rem -> failwith "c_binop: division goes through a helper"

(* Whether evaluating [e] can do something observable: call a function, or
   divide (which can panic). *)
let rec has_effect e =
  match e.kind with
  | Call _ -> true
  | Binary b -> b.op = Div || b.op = Rem || has_effect b.lhs || has_effect b.rhs
  | Unary (_, x) -> has_effect x
  | Int _ | Bool_lit _ | Var _ -> false

let new_tmp em =
  let n = em.next_tmp in
  em.next_tmp <- n + 1;
  "tmp_" ^ string_of_int n

(* Writes 'T tmp = code;' now and returns the temporary. *)
let store em ty code =
  let t = new_tmp em in
  line em (c_type ty ^ " " ^ t ^ " = " ^ code ^ ";");
  { code = t; atomic = true; stable = true }

let rec emit_expr em e =
  match e.kind with
  (* In C, 2147483648 is a long, so the minimum is written by name. *)
  | Int n when n = -2147483648 -> literal "INT32_MIN"
  | Int n when n < 0 ->
      { code = string_of_int n; atomic = false; stable = true }
  | Int n -> literal (string_of_int n)
  | Bool_lit b -> literal (if b then "true" else "false")
  | Var vr -> atom (c_local_name (sym_of vr))
  | Call call -> store em e.ty (emit_call em call)
  | Unary (Neg, x) -> compound ("-" ^ operand (emit_expr em x))
  | Unary (Not, x) -> compound ("!" ^ operand (emit_expr em x))
  | Binary b -> (
      match b.op with
      | And | Or -> emit_short_circuit em b
      | _ -> emit_binary em b)

and emit_binary em b =
  let l = emit_expr em b.lhs in
  let l =
    if has_effect b.rhs && not l.stable then store em b.lhs.ty l.code else l
  in
  let r = emit_expr em b.rhs in
  match b.op with
  | Div | Rem ->
      let helper =
        if b.op = Div then "slickrt_div_i32" else "slickrt_rem_i32"
      in
      atom
        (Printf.sprintf "%s(%s, %s, %s)" helper l.code r.code
           (panic_site em b.op b.rhs))
  | op -> compound (operand l ^ " " ^ c_binop op ^ " " ^ operand r)

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

(* Each argument is saved before a later argument with a side effect runs. *)
and emit_args em args acc =
  match args with
  | [] -> List.rev acc
  | arg :: rest ->
      let ce = emit_expr em arg in
      let ce =
        if List.exists has_effect rest && not ce.stable then
          store em arg.ty ce.code
        else ce
      in
      emit_args em rest (ce.code :: acc)

(* The call itself, as C text, after its arguments' statements. *)
and emit_call em call =
  let args = emit_args em call.args [] in
  let name =
    if call.callee = "print" then "slickrt_print_i32"
    else c_func_name call.callee
  in
  name ^ "(" ^ String.concat ", " args ^ ")"

(* 'x op= v' is emitted as 'x = x op v', so '/=' and '%=' go through the
   division helpers and 'x' is read before 'v' runs. *)
let assigned_value a =
  match a.a_op with
  | None -> a.a_value
  | Some op ->
      {
        kind =
          Binary
            { op; op_span = a.a_op_span; lhs = a.a_target; rhs = a.a_value };
        span = Diag.join a.a_target.span a.a_value.span;
        ty = a.a_target.ty;
      }

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
        | None -> c_zero sym.sym_ty
      in
      line em (c_type sym.sym_ty ^ " " ^ c_local_name sym ^ " = " ^ value ^ ";")
  | Assign a ->
      let value = (emit_expr em (assigned_value a)).code in
      let target = (emit_expr em a.a_target).code in
      line em (target ^ " = " ^ value ^ ";")
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

let emit_prototype em f = line em (signature f ^ ";")

let emit_func em f =
  em.next_tmp <- f.nsyms + 1;
  line em (signature f ^ " {");
  emit_body em f.body;
  line em "}";
  line em ""

(* The functions are emitted first, since that is what collects the panic
   messages, which must come before them in the file. *)
let emit_file (file : file) =
  let em =
    {
      out = Buffer.create 4096;
      indent = 0;
      next_tmp = 1;
      sites = [];
      next_site = 1;
    }
  in
  List.iter (emit_prototype em) file.funcs;
  line em "";
  List.iter (emit_func em) file.funcs;
  line em "int main(void) {";
  line em "    slick_main();";
  line em "    return 0;";
  line em "}";
  let sites = List.rev em.sites in
  let site_block =
    if sites = [] then "" else String.concat "\n" sites ^ "\n\n"
  in
  prelude ^ "\n" ^ site_block ^ Buffer.contents em.out
