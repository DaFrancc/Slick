(* The syntax tree. The parser builds it; the checker fills in the mutable
   fields (types, resolved symbols) in place. *)

(* [Err] is the type of something whose error has already been reported. It
   is accepted everywhere, so one mistake never causes a second error. *)
type ty = I32 | Bool | Void | Err

let ty_name t =
  match t with
  | I32 -> "i32"
  | Bool -> "bool"
  | Void -> "void"
  | Err -> "<error>"

(* One per parameter or local, made by the checker. *)
type symbol = {
  sym_name : string;
  sym_ty : ty;
  sym_mut : bool;
  sym_param : bool;
  sym_span : Diag.span; (* the name where it was declared *)
  sym_type_span : Diag.span; (* its written type, or its name if none *)
  sym_mut_edit : Diag.edit; (* the edit that would declare it 'mut' *)
  sym_id : int; (* unique within its function, used for C names *)
}

type unop = Neg | Not

type binop =
  | Add
  | Sub
  | Mul
  | Div
  | Rem
  | Eq
  | Ne
  | Lt
  | Le
  | Gt
  | Ge
  | And
  | Or

let binop_text op =
  match op with
  | Add -> "+"
  | Sub -> "-"
  | Mul -> "*"
  | Div -> "/"
  | Rem -> "%"
  | Eq -> "=="
  | Ne -> "!="
  | Lt -> "<"
  | Le -> "<="
  | Gt -> ">"
  | Ge -> ">="
  | And -> "&&"
  | Or -> "||"

type expr = {
  kind : expr_kind;
  span : Diag.span; (* the whole expression, parentheses included *)
  mutable ty : ty;
}

and expr_kind =
  | Int of int
  | Bool_lit of bool
  | Var of var_ref
  | Call of call
  | Unary of unop * expr
  | Binary of binary

and var_ref = { var_name : string; mutable var_sym : symbol option }

and call = {
  callee : string;
  callee_span : Diag.span;
  args : expr list;
  args_span : Diag.span; (* from '(' to ')' *)
}

and binary = { op : binop; op_span : Diag.span; lhs : expr; rhs : expr }

type type_ann = { t_name : string; t_span : Diag.span }

type stmt = { skind : stmt_kind; sspan : Diag.span (* ';' included *) }

and stmt_kind =
  | Decl of decl
  | Assign of assign
  | Call_stmt of expr (* always a Call *)
  | If of if_stmt
  | While of while_stmt
  | Return of return_stmt
  | Block of block

and decl = {
  d_name : string;
  d_name_span : Diag.span;
  d_sep_span : Diag.span; (* the ':=' or ':' after the name *)
  d_colon_eq : bool; (* whether the separator is ':=' *)
  d_mut : bool;
  d_ann : type_ann option;
  d_init : expr option;
  mutable d_sym : symbol option;
}

and assign = {
  a_op : binop option; (* None for '=', Some Add for '+=' and so on *)
  a_op_span : Diag.span;
  a_target : expr; (* always a Var *)
  a_value : expr;
}

and if_stmt = { cond : expr; then_block : block; else_part : else_part }
and else_part = No_else | Else_block of block | Else_if of if_stmt
and while_stmt = { w_cond : expr; w_body : block }
and return_stmt = { ret_value : expr option; ret_kw_span : Diag.span }
and block = { stmts : stmt list; close_span : Diag.span (* the '}' *) }

type param = {
  p_name : string;
  p_span : Diag.span;
  p_mut : bool;
  p_ann : type_ann;
  mutable p_sym : symbol option;
}

type func = {
  f_name : string;
  f_name_span : Diag.span;
  params : param list;
  params_span : Diag.span; (* from '(' to ')' *)
  ret_ann : type_ann option;
  body : block;
  mutable param_tys : ty list;
  mutable ret_ty : ty;
  mutable nsyms : int; (* symbols made for this function; temporaries follow *)
}

type file = { path : string; funcs : func list }
