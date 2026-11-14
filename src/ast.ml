(* The syntax tree. The parser builds it; the checker fills in the mutable
   fields (types, resolved symbols) in place. *)

type ty = I32 | Bool | Void

let ty_name t = match t with I32 -> "i32" | Bool -> "bool" | Void -> "void"

(* One per parameter or local, made by the checker. *)
type symbol = {
  sym_name : string;
  sym_ty : ty;
  sym_mut : bool;
  sym_param : bool;
  sym_loc : Diag.loc;
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
  loc : Diag.loc; (* where the expression starts *)
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
and call = { callee : string; args : expr list }
and binary = { op : binop; op_loc : Diag.loc; lhs : expr; rhs : expr }

type type_ann = { t_name : string; t_loc : Diag.loc }

type stmt = { skind : stmt_kind; sloc : Diag.loc }

and stmt_kind =
  | Decl of decl
  | Assign of assign
  | Call_stmt of expr (* always a Call *)
  | If of if_stmt
  | While of while_stmt
  | Return of expr option
  | Block of block

and decl = {
  d_name : string;
  d_mut : bool;
  d_ann : type_ann option;
  d_init : expr option;
  mutable d_sym : symbol option;
}

and assign = {
  a_op : binop option; (* None for '=', Some Add for '+=' and so on *)
  a_op_loc : Diag.loc;
  a_target : expr; (* always a Var *)
  a_value : expr;
}

and if_stmt = { cond : expr; then_block : block; else_part : else_part }
and else_part = No_else | Else_block of block | Else_if of if_stmt
and while_stmt = { w_cond : expr; w_body : block }
and block = { stmts : stmt list; close_loc : Diag.loc }

type param = {
  p_name : string;
  p_loc : Diag.loc;
  p_mut : bool;
  p_ann : type_ann;
  mutable p_sym : symbol option;
}

type func = {
  f_name : string;
  f_loc : Diag.loc;
  params : param list;
  ret_ann : type_ann option;
  body : block;
  mutable param_tys : ty list;
  mutable ret_ty : ty;
  mutable nsyms : int; (* symbols made for this function; temporaries follow *)
}

type file = { path : string; funcs : func list }
