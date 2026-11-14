(* The syntax tree. The parser builds it; the checker fills in the mutable
   fields (types, resolved symbols, conversions) in place. *)

type int_kind = I8 | I16 | I32 | I64 | U8 | U16 | U32 | U64
type float_kind = F32 | F64

(* [Err] is the type of something whose error has already been reported. It
   is accepted everywhere, so one mistake never causes a second error.

   A struct is referred to by name, never by its record: [ty] holds no
   records or functions, so the polymorphic [=] and [<>] are safe on it even
   for a struct that points to itself. Keep it that way. *)
type ty =
  | Int_ty of int_kind
  | Float_ty of float_kind
  | Bool
  | Void
  | Ptr of bool * ty (* whether the pointee is mutable, and its type *)
  | Struct of string
  | Err

let all_int_kinds = [ I8; I16; I32; I64; U8; U16; U32; U64 ]

let int_kind_name k =
  match k with
  | I8 -> "i8"
  | I16 -> "i16"
  | I32 -> "i32"
  | I64 -> "i64"
  | U8 -> "u8"
  | U16 -> "u16"
  | U32 -> "u32"
  | U64 -> "u64"

let float_kind_name k = match k with F32 -> "f32" | F64 -> "f64"

let int_bits k =
  match k with
  | I8 | U8 -> 8
  | I16 | U16 -> 16
  | I32 | U32 -> 32
  | I64 | U64 -> 64

let is_signed k = match k with I8 | I16 | I32 | I64 -> true | _ -> false
let float_bits k = match k with F32 -> 32 | F64 -> 64

let rec ty_name t =
  match t with
  | Int_ty k -> int_kind_name k
  | Float_ty k -> float_kind_name k
  | Bool -> "bool"
  | Void -> "void"
  | Ptr (true, t) -> "*mut " ^ ty_name t
  | Ptr (false, t) -> "*" ^ ty_name t
  | Struct name -> name
  | Err -> "<error>"

let i32 = Int_ty I32
let is_int t = match t with Int_ty _ -> true | _ -> false
let is_float t = match t with Float_ty _ -> true | _ -> false
let is_number t = is_int t || is_float t

(* One per parameter or local, made by the checker. *)
type symbol = {
  sym_name : string;
  sym_ty : ty;
  sym_mut : bool;
  sym_param : bool;
  sym_span : Diag.span; (* the name where it was declared *)
  sym_type_span : Diag.span; (* its written type, or its name if none *)
  sym_mut_edit : Diag.edit; (* the edit that would declare it 'mut' *)
  (* For a read-only pointer, the edit that would make it a '*mut': in its
     written type, or in the '&' it was initialized with. *)
  sym_ptr_edit : Diag.edit option;
  sym_id : int; (* unique within its function, used for C names *)
}

type unop = Neg | Not | Bnot

type binop =
  | Add
  | Sub
  | Mul
  | Div
  | Rem
  | Band
  | Bor
  | Bxor
  | Shl
  | Shr
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
  | Band -> "&"
  | Bor -> "|"
  | Bxor -> "^"
  | Shl -> "<<"
  | Shr -> ">>"
  | Eq -> "=="
  | Ne -> "!="
  | Lt -> "<"
  | Le -> "<="
  | Gt -> ">"
  | Ge -> ">="
  | And -> "&&"
  | Or -> "||"

(* A written type. [t_span] covers all of it, like '*mut Vec3'. *)
type type_ann = { t_kind : type_kind; t_span : Diag.span }
and type_kind = Named of string | Pointer of bool * type_ann

(* An integer literal: its magnitude, read as unsigned, and whether a '-'
   was folded into it. *)
type int_lit = { value : Int64.t; neg : bool }

(* A float literal: its source text without '_' or sign. *)
type float_lit = { text : string; fneg : bool }
type cast_kind = Convert | Bits

type expr = {
  kind : expr_kind;
  span : Diag.span; (* the whole expression, parentheses included *)
  mutable ty : ty;
  (* The type the checker converted this expression to, where an implicit
     conversion happened. The emitter writes it as a C cast. *)
  mutable conv : ty option;
}

and expr_kind =
  | Int of int_lit
  | Float of float_lit
  | Bool_lit of bool
  | Var of var_ref
  | Call of call
  | Unary of unop * expr
  | Binary of binary
  | Field of field_access
  | Deref of expr
  | Addr_of of bool * expr (* whether it is '&mut' *)
  | Cast of cast_kind * type_ann * expr
  | Struct_lit of struct_lit

and var_ref = { var_name : string; mutable var_sym : symbol option }

and call = {
  callee : string;
  callee_span : Diag.span;
  args : expr list;
  args_span : Diag.span; (* from '(' to ')' *)
}

and binary = { op : binop; op_span : Diag.span; lhs : expr; rhs : expr }

and field_access = {
  obj : expr;
  field : string;
  field_span : Diag.span;
  mutable through_ptr : bool; (* whether [obj] is a pointer to the struct *)
}

and struct_lit = {
  sl_name : (string * Diag.span) option; (* None for '.{ }' *)
  sl_open : Diag.span; (* the name and '{', or '.{' *)
  items : lit_item list;
}

(* [i_name] is None for a positional value. *)
and lit_item = { i_name : (string * Diag.span) option; i_value : expr }

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
  a_target : expr;
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

type field = {
  fd_name : string;
  fd_span : Diag.span;
  fd_ann : type_ann;
  mutable fd_ty : ty;
}

type struct_decl = {
  s_name : string;
  s_name_span : Diag.span;
  s_fields : field list;
}

(* Each list is in source order. *)
type file = { path : string; structs : struct_decl list; funcs : func list }
