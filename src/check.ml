(* Name resolution and type checking. Annotates the AST in place. *)

open Ast

type checker = {
  file : string;
  funcs : (string, func) Hashtbl.t;
  (* Every parameter and local visible at this point. With no shadowing, one
     table is enough: a name is in it at most once. *)
  locals : (string, symbol) Hashtbl.t;
  (* The names declared in each open block, innermost first, so they can be
     removed when the block ends. *)
  mutable scopes : string list list;
  mutable next_id : int;
  mutable cur_func : func option; (* the function whose body is being checked *)
}

let resolve_type ann =
  match ann.t_name with
  | "i32" -> I32
  | "bool" -> Bool
  | name -> Diag.fatal ann.t_loc (Printf.sprintf "unknown type '%s'" name)

let resolve_param_type prm = resolve_type prm.p_ann

(* ---- Pass 1: function signatures ---- *)

let declare_func c f =
  if f.f_name = "print" then
    Diag.fatal f.f_loc "'print' is a built-in function and cannot be redeclared";
  (match Hashtbl.find_opt c.funcs f.f_name with
  | Some prev ->
      Diag.fatal f.f_loc
        (Printf.sprintf "function '%s' is already defined on line %d" f.f_name
           prev.f_loc.line)
  | None -> ());
  if f.f_name = "main" && (f.params <> [] || f.ret_ann <> None) then
    Diag.fatal f.f_loc "'main' must take no parameters and return nothing";
  f.param_tys <- List.map resolve_param_type f.params;
  f.ret_ty <-
    (match f.ret_ann with None -> Void | Some ann -> resolve_type ann);
  Hashtbl.replace c.funcs f.f_name f

(* ---- Scopes ---- *)

let open_scope c = c.scopes <- [] :: c.scopes

let close_scope c =
  match c.scopes with
  | names :: rest ->
      List.iter (Hashtbl.remove c.locals) names;
      c.scopes <- rest
  | [] -> failwith "close_scope: no open scope"

let is_function c name = name = "print" || Hashtbl.mem c.funcs name

(* No shadowing: a name cannot be declared while anything with that name is
   visible, including functions and print. *)
let check_name_free c name loc =
  if name = "print" then
    Diag.fatal loc "'print' is a built-in function and cannot be redeclared";
  (match Hashtbl.find_opt c.funcs name with
  | Some f ->
      Diag.fatal loc
        (Printf.sprintf "'%s' is already declared as a function on line %d" name
           f.f_loc.line)
  | None -> ());
  match Hashtbl.find_opt c.locals name with
  | Some sym ->
      Diag.fatal loc
        (Printf.sprintf "'%s' is already declared on line %d" name
           sym.sym_loc.line)
  | None -> ()

let add_local c name loc ty is_mut is_param =
  let sym =
    {
      sym_name = name;
      sym_ty = ty;
      sym_mut = is_mut;
      sym_param = is_param;
      sym_loc = loc;
      sym_id = c.next_id;
    }
  in
  c.next_id <- c.next_id + 1;
  Hashtbl.replace c.locals name sym;
  (match c.scopes with
  | names :: rest -> c.scopes <- (name :: names) :: rest
  | [] -> failwith "add_local: no open scope");
  sym

(* ---- Pass 2: bodies ---- *)

let plural n word =
  if n = 1 then "1 " ^ word else string_of_int n ^ " " ^ word ^ "s"

let check_var c e vr =
  match Hashtbl.find_opt c.locals vr.var_name with
  | Some sym ->
      vr.var_sym <- Some sym;
      sym.sym_ty
  | None ->
      if is_function c vr.var_name then
        Diag.fatal e.loc
          (Printf.sprintf "'%s' cannot be used as a value yet" vr.var_name)
      else Diag.fatal e.loc (Printf.sprintf "undeclared name '%s'" vr.var_name)

let operand_error op_loc op what lt rt =
  Diag.fatal op_loc
    (Printf.sprintf "operator '%s' expects %s operands, found %s and %s"
       (binop_text op) what (ty_name lt) (ty_name rt))

(* The type of [e], for any position except a call statement. *)
let rec check_expr c e =
  let t =
    match e.kind with
    | Int n ->
        if n > 2147483647 then
          Diag.fatal e.loc
            (Printf.sprintf "integer literal %d does not fit in i32" n);
        I32
    | Bool_lit _ -> Bool
    | Call call -> check_call c e call
    | Var vr -> check_var c e vr
    | Unary (op, operand) -> check_unary c e op operand
    | Binary b -> check_binary c b
  in
  e.ty <- t;
  t

(* Like [check_expr], for positions that need a value. Only a call can be
   void. *)
and check_value c e =
  let t = check_expr c e in
  (if t = Void then
     match e.kind with
     | Call call ->
         Diag.fatal e.loc
           (Printf.sprintf "'%s' returns nothing and cannot be used as a value"
              call.callee)
     | _ -> ());
  t

and check_unary c e op operand =
  let t = check_value c operand in
  match op with
  | Neg ->
      if t <> I32 then
        Diag.fatal e.loc
          (Printf.sprintf "operator '-' expects i32, found %s" (ty_name t));
      I32
  | Not ->
      if t <> Bool then
        Diag.fatal e.loc
          (Printf.sprintf "operator '!' expects bool, found %s" (ty_name t));
      Bool

and check_binary c b =
  let lt = check_value c b.lhs in
  let rt = check_value c b.rhs in
  match b.op with
  | Add | Sub | Mul | Div | Rem ->
      if lt <> I32 || rt <> I32 then operand_error b.op_loc b.op "i32" lt rt;
      I32
  | Lt | Le | Gt | Ge ->
      if lt <> I32 || rt <> I32 then operand_error b.op_loc b.op "i32" lt rt;
      Bool
  | Eq | Ne ->
      if lt <> rt then
        Diag.fatal b.op_loc
          (Printf.sprintf
             "operator '%s' needs both sides to have the same type, found %s \
              and %s"
             (binop_text b.op) (ty_name lt) (ty_name rt));
      Bool
  | And | Or ->
      if lt <> Bool || rt <> Bool then operand_error b.op_loc b.op "bool" lt rt;
      Bool

and check_args c callee_name args expected index =
  match (args, expected) with
  | [], _ | _, [] -> ()
  | arg :: rest, ty :: rest_tys ->
      let t = check_value c arg in
      if t <> ty then
        Diag.fatal arg.loc
          (Printf.sprintf "argument %d of '%s' expects %s, found %s" index
             callee_name (ty_name ty) (ty_name t));
      check_args c callee_name rest rest_tys (index + 1)

and check_call c e call =
  if Hashtbl.mem c.locals call.callee then
    Diag.fatal e.loc (Printf.sprintf "'%s' is not a function" call.callee);
  let param_tys, ret =
    if call.callee = "print" then ([ I32 ], Void)
    else
      match Hashtbl.find_opt c.funcs call.callee with
      | Some f -> (f.param_tys, f.ret_ty)
      | None ->
          Diag.fatal e.loc (Printf.sprintf "unknown function '%s'" call.callee)
  in
  let expected = List.length param_tys in
  let found = List.length call.args in
  if expected <> found then
    Diag.fatal e.loc
      (Printf.sprintf "'%s' expects %s, found %d" call.callee
         (plural expected "argument")
         found);
  check_args c call.callee call.args param_tys 1;
  ret

let check_decl c loc d =
  (* The name is checked first, but declared only after the initializer, so
     'x := x + 1;' cannot read the 'x' it declares. *)
  check_name_free c d.d_name loc;
  let ann_ty =
    match d.d_ann with Some ann -> Some (resolve_type ann) | None -> None
  in
  let ty =
    match (ann_ty, d.d_init) with
    | Some t, Some init ->
        let it = check_value c init in
        if it <> t then
          Diag.fatal init.loc
            (Printf.sprintf
               "cannot initialize '%s' of type %s with a value of type %s"
               d.d_name (ty_name t) (ty_name it));
        t
    | Some t, None -> t
    | None, Some init -> check_value c init
    | None, None -> failwith "check_decl: the parser requires a type or a value"
  in
  d.d_sym <- Some (add_local c d.d_name loc ty d.d_mut false)

let check_assign c a =
  let target = a.a_target in
  let vr =
    match target.kind with
    | Var vr -> vr
    | _ -> failwith "check_assign: the parser only allows names"
  in
  let sym =
    match Hashtbl.find_opt c.locals vr.var_name with
    | Some sym -> sym
    | None ->
        if is_function c vr.var_name then
          Diag.fatal target.loc
            (Printf.sprintf "cannot assign to function '%s'" vr.var_name)
        else
          Diag.fatal target.loc
            (Printf.sprintf "undeclared name '%s'" vr.var_name)
  in
  vr.var_sym <- Some sym;
  target.ty <- sym.sym_ty;
  if not sym.sym_mut then
    Diag.fatal target.loc
      (Printf.sprintf
         "cannot assign to %s'%s': it was declared without 'mut' on line %d"
         (if sym.sym_param then "parameter " else "")
         sym.sym_name sym.sym_loc.line);
  let vt = check_value c a.a_value in
  match a.a_op with
  | None ->
      if vt <> sym.sym_ty then
        Diag.fatal a.a_value.loc
          (Printf.sprintf "cannot assign a value of type %s to '%s' of type %s"
             (ty_name vt) sym.sym_name (ty_name sym.sym_ty))
  | Some op ->
      if sym.sym_ty <> I32 || vt <> I32 then
        Diag.fatal a.a_op_loc
          (Printf.sprintf "operator '%s=' expects i32 operands, found %s and %s"
             (binop_text op) (ty_name sym.sym_ty) (ty_name vt))

let rec check_stmt c s =
  match s.skind with
  | Call_stmt e -> ignore (check_expr c e)
  | Decl d -> check_decl c s.sloc d
  | Assign a -> check_assign c a
  | Block b -> check_block c b
  | If ifs -> check_if c ifs
  | While w ->
      check_cond c "while" w.w_cond;
      check_block c w.w_body
  | Return value -> check_return c s.sloc value

and check_return c loc value =
  let f =
    match c.cur_func with
    | Some f -> f
    | None -> failwith "check_return: outside a function"
  in
  match value with
  | None ->
      if f.ret_ty <> Void then
        Diag.fatal loc
          (Printf.sprintf "'%s' returns %s, but this 'return' has no value"
             f.f_name (ty_name f.ret_ty))
  | Some e ->
      if f.ret_ty = Void then
        Diag.fatal e.loc
          (Printf.sprintf "'%s' returns nothing, but this 'return' has a value"
             f.f_name);
      let t = check_value c e in
      if t <> f.ret_ty then
        Diag.fatal e.loc
          (Printf.sprintf
             "'%s' returns %s, but this 'return' has a value of type %s"
             f.f_name (ty_name f.ret_ty) (ty_name t))

and check_cond c keyword e =
  let t = check_value c e in
  if t <> Bool then
    Diag.fatal e.loc
      (Printf.sprintf "condition of '%s' must be bool, found %s" keyword
         (ty_name t))

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

let add_param c prm ty =
  check_name_free c prm.p_name prm.p_loc;
  prm.p_sym <- Some (add_local c prm.p_name prm.p_loc ty prm.p_mut true)

let rec add_params c params tys =
  match (params, tys) with
  | prm :: rest, ty :: rest_tys ->
      add_param c prm ty;
      add_params c rest rest_tys
  | _ -> ()

let check_func c f =
  c.cur_func <- Some f;
  c.next_id <- 1;
  open_scope c;
  add_params c f.params f.param_tys;
  check_block c f.body;
  close_scope c;
  if f.ret_ty <> Void && not (block_returns f.body) then
    Diag.fatal f.body.close_loc
      (Printf.sprintf "'%s' is missing a return: not every path returns a value"
         f.f_name);
  f.nsyms <- c.next_id - 1;
  c.cur_func <- None

let check_file (file : file) =
  let c =
    {
      file = file.path;
      funcs = Hashtbl.create 16;
      locals = Hashtbl.create 16;
      scopes = [];
      next_id = 1;
      cur_func = None;
    }
  in
  List.iter (declare_func c) file.funcs;
  if not (Hashtbl.mem c.funcs "main") then
    Diag.fatal_file c.file "no 'main' function found";
  List.iter (check_func c) file.funcs
