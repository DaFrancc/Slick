(* Name resolution and type checking. Annotates the AST in place.

   Every error is reported and checking goes on. Something whose error has
   been reported gets the type [Err], which every check accepts silently, and
   operators still produce their usual result type. So one mistake is
   reported once, and nothing that depends on it is reported again. *)

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
  (* Symbols of this function whose block has ended, most recent first, so an
     undeclared name can point at one. *)
  mutable ended : symbol list;
  mutable next_id : int;
  mutable cur_func : func option; (* the function whose body is being checked *)
}

let sprintf = Printf.sprintf

(* ---- Building diagnostics ---- *)

let i32_range_note = "An i32 holds values from -2147483648 to 2147483647"
let no_shadowing_note = "Slick does not allow shadowing"

let plural n word =
  if n = 1 then "1 " ^ word else string_of_int n ^ " " ^ word ^ "s"

(* A secondary label at a function's name, unless it is the built-in print,
   which has no source. *)
let with_function_label d name f_opt text =
  match f_opt with
  | Some f when name <> "print" -> Diag.with_label d f.f_name_span text
  | _ -> d

(* The span of the first character of [s], for a unary operator. *)
let first_char (s : Diag.span) =
  { s with end_line = s.start_line; end_col = s.start_col + 1 }

let quoted_source (s : Diag.span) =
  match Report.span_text s with Some text -> text | None -> "..."

(* Whether two types disagree, counting [Err] as agreeing with anything. *)
let mismatch a b = a <> b && a <> Err && b <> Err

(* Whether [t] is known and is not [want]. *)
let is_not t want = t <> want && t <> Err

(* ---- Types ---- *)

let resolve_type ann =
  match ann.t_name with
  | "i32" -> I32
  | "bool" -> Bool
  | name ->
      let d =
        Diag.error ann.t_span (sprintf "Unknown type '%s'" name) "Not a type"
      in
      let suggestion =
        match name with
        | "int" | "integer" -> Some "i32"
        | "boolean" -> Some "bool"
        | _ -> Suggest.closest name [ ("i32", 0); ("bool", 1) ]
      in
      Report.report
        (match suggestion with
        | Some s ->
            Diag.with_help d
              (sprintf "Did you mean '%s'?" s)
              [ Diag.edit ann.t_span s ]
        | None -> Diag.with_note d "The types available now are i32 and bool");
      Err

let resolve_param_type prm = resolve_type prm.p_ann

(* ---- Pass 1: function signatures ---- *)

(* A function named print, or a second function with a name already taken,
   is reported and left out of the table; its body is still checked. *)
let declare_func c f =
  f.param_tys <- List.map resolve_param_type f.params;
  f.ret_ty <-
    (match f.ret_ann with None -> Void | Some ann -> resolve_type ann);
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
  if f.f_name = "print" then
    Report.report
      (Diag.with_help
         (Diag.error f.f_name_span
            "'print' is a built-in function and cannot be redeclared" "")
         "Choose a different name" [])
  else
    match Hashtbl.find_opt c.funcs f.f_name with
    | Some prev ->
        Report.report
          (Diag.with_label
             (Diag.error f.f_name_span
                (sprintf "Function '%s' is already defined" f.f_name)
                "Defined again here")
             prev.f_name_span "First defined here")
    | None -> Hashtbl.replace c.funcs f.f_name f

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

let is_function c name = name = "print" || Hashtbl.mem c.funcs name

(* No shadowing: a name cannot be declared while anything with that name is
   visible, including functions and print. [init] is the new declaration's
   initial value, if it has one, for the "assign instead" suggestion.

   Returns whether to declare the name anyway. A name taken by a function is
   still declared as a local, so later uses do not report again. A name taken
   by another local is not: the first declaration stays. *)
let check_name_free c name span init =
  if name = "print" then begin
    Report.report
      (Diag.with_help
         (Diag.error span
            "'print' is a built-in function and cannot be redeclared" "")
         "Choose a different name" []);
    true
  end
  else
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
    | None -> (
        match Hashtbl.find_opt c.funcs name with
        | Some f ->
            let d =
              Diag.error span
                (sprintf "'%s' is already declared as a function" name)
                "Declared again here"
            in
            let d = Diag.with_label d f.f_name_span "Function defined here" in
            let d = Diag.with_note d no_shadowing_note in
            Report.report (Diag.with_help d "Choose a different name" []);
            true
        | None -> true)

let add_local c name span type_span ty is_mut is_param mut_edit =
  let sym =
    {
      sym_name = name;
      sym_ty = ty;
      sym_mut = is_mut;
      sym_param = is_param;
      sym_span = span;
      sym_type_span = type_span;
      sym_mut_edit = mut_edit;
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

let rec find_ended name (syms : symbol list) =
  match syms with
  | [] -> None
  | sym :: rest ->
      if sym.sym_name = name then Some sym else find_ended name rest

(* "Did you mean 'x'?", replacing the name at [span]. *)
let with_suggestion d span suggestion =
  match suggestion with
  | Some s ->
      Diag.with_help d (sprintf "Did you mean '%s'?" s) [ Diag.edit span s ]
  | None -> d

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

let check_var c e vr =
  match Hashtbl.find_opt c.locals vr.var_name with
  | Some sym ->
      vr.var_sym <- Some sym;
      sym.sym_ty
  | None ->
      if is_function c vr.var_name then begin
        let f = Hashtbl.find_opt c.funcs vr.var_name in
        let d =
          Diag.error e.span
            (sprintf "'%s' is a function and cannot be used as a value yet"
               vr.var_name)
            ""
        in
        let d = with_function_label d vr.var_name f "Function defined here" in
        let edits =
          match f with
          | Some f when f.params = [] ->
              [ Diag.edit (Diag.point_after e.span) "()" ]
          | _ -> []
        in
        Report.report (Diag.with_help d "To call it, add parentheses" edits);
        Err
      end
      else undeclared c e.span vr.var_name

(* An operator applied to operands of the wrong types: the operator is the
   primary label, and each operand is labelled with its type. *)
let operand_error op_span msg (lhs : expr) lt (rhs : expr) rt =
  let d = Diag.error op_span msg "" in
  let d = Diag.with_label d lhs.span (ty_name lt) in
  Report.report (Diag.with_label d rhs.span (ty_name rt))

(* Reports unless an operand already has an error. *)
let expect_operands op_span op want lhs lt rhs rt =
  if lt <> Err && rt <> Err && (lt <> want || rt <> want) then
    operand_error op_span
      (sprintf "Operator '%s' expects %s operands, found %s and %s"
         (binop_text op) (ty_name want) (ty_name lt) (ty_name rt))
      lhs lt rhs rt

(* The type of [e], for any position except a call statement. *)
let rec check_expr c e =
  let t =
    match e.kind with
    | Int n ->
        if n > 2147483647 then
          Report.report
            (Diag.with_note
               (Diag.error e.span
                  (sprintf "Integer literal %d does not fit in i32" n)
                  "Too large")
               i32_range_note);
        I32
    | Bool_lit _ -> Bool
    | Call call -> check_call c call
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
          (with_function_label d call.callee
             (Hashtbl.find_opt c.funcs call.callee)
             "Declared here with no return type")
    | _ -> ());
    Err
  end
  else t

and check_unary c e op operand =
  let t = check_value c operand in
  let op_span = first_char e.span in
  match op with
  | Neg ->
      if is_not t I32 then
        Report.report
          (Diag.with_label
             (Diag.error op_span
                (sprintf "Operator '-' expects i32, found %s" (ty_name t))
                "")
             operand.span (ty_name t));
      I32
  | Not ->
      if is_not t Bool then begin
        let d =
          Diag.with_label
            (Diag.error op_span
               (sprintf "Operator '!' expects bool, found %s" (ty_name t))
               "")
            operand.span (ty_name t)
        in
        Report.report
          (if t = I32 then
             Diag.with_help d
               (sprintf "To test for zero, compare it: '%s == 0'"
                  (quoted_source operand.span))
               []
           else d)
      end;
      Bool

and check_binary c b =
  let lt = check_value c b.lhs in
  let rt = check_value c b.rhs in
  match b.op with
  | Add | Sub | Mul | Div | Rem ->
      expect_operands b.op_span b.op I32 b.lhs lt b.rhs rt;
      I32
  | Lt | Le | Gt | Ge ->
      expect_operands b.op_span b.op I32 b.lhs lt b.rhs rt;
      Bool
  | Eq | Ne ->
      if mismatch lt rt then
        operand_error b.op_span
          (sprintf
             "Operator '%s' needs both sides to have the same type, found %s \
              and %s"
             (binop_text b.op) (ty_name lt) (ty_name rt))
          b.lhs lt b.rhs rt;
      Bool
  | And | Or ->
      expect_operands b.op_span b.op Bool b.lhs lt b.rhs rt;
      Bool

(* [params] is the function's parameter list, empty for print. *)
and check_args c callee_name args expected params index =
  match (args, expected) with
  | [], _ | _, [] -> ()
  | arg :: rest, ty :: rest_tys ->
      let t = check_value c arg in
      if mismatch t ty then begin
        let d =
          Diag.error arg.span
            (sprintf "Argument %d of '%s' expects %s, found %s" index
               callee_name (ty_name ty) (ty_name t))
            ("This is " ^ ty_name t)
        in
        Report.report
          (match params with
          | prm :: _ ->
              Diag.with_label d prm.p_span
                (sprintf "Parameter '%s' is declared here" prm.p_name)
          | [] -> d)
      end;
      let rest_params = match params with _ :: ps -> ps | [] -> [] in
      check_args c callee_name rest rest_tys rest_params (index + 1)

(* Arguments of a call that is already wrong are still checked, for errors
   of their own. *)
and check_args_only c args = List.iter (check_arg_only c) args
and check_arg_only c arg = ignore (check_value c arg)

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
      let f = Hashtbl.find_opt c.funcs call.callee in
      let signature =
        if call.callee = "print" then Some ([ I32 ], Void, [])
        else
          match f with
          | Some f -> Some (f.param_tys, f.ret_ty, f.params)
          | None -> None
      in
      match signature with
      | None ->
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
          Err
      | Some (param_tys, ret, params) ->
          let expected = List.length param_tys in
          let found = List.length call.args in
          if expected <> found then begin
            let d =
              Diag.error call.args_span
                (sprintf "'%s' expects %s, found %d" call.callee
                   (plural expected "argument")
                   found)
                ("Found " ^ plural found "argument")
            in
            Report.report
              (match f with
              | Some f when call.callee <> "print" ->
                  Diag.with_label d f.params_span
                    (sprintf "'%s' is defined here" call.callee)
              | _ -> d);
            check_args_only c call.args
          end
          else check_args c call.callee call.args param_tys params 1;
          ret)

(* How to make a declaration 'mut': 'x := v' becomes 'x : mut = v', and
   'x : T' becomes 'x : mut T'. *)
let decl_mut_edit d =
  if d.d_colon_eq then Diag.edit d.d_sep_span ": mut ="
  else
    match d.d_ann with
    | Some ann -> Diag.edit (Diag.point_before ann.t_span) "mut "
    | None -> Diag.edit (Diag.point_after d.d_sep_span) " mut"

let check_decl c d =
  (* The name is checked first, but declared only after the initializer, so
     'x := x + 1;' cannot read the 'x' it declares. *)
  let declare = check_name_free c d.d_name d.d_name_span d.d_init in
  let ann_ty =
    match d.d_ann with Some ann -> Some (resolve_type ann) | None -> None
  in
  let init_ty =
    match d.d_init with Some init -> Some (check_value c init) | None -> None
  in
  (match (ann_ty, d.d_ann, init_ty, d.d_init) with
  | Some t, Some ann, Some it, Some init when mismatch it t ->
      Report.report
        (Diag.with_label
           (Diag.error init.span
              (sprintf
                 "Cannot initialize '%s' of type %s with a value of type %s"
                 d.d_name (ty_name t) (ty_name it))
              ("This is " ^ ty_name it))
           ann.t_span
           (sprintf "Declared as %s here" (ty_name t)))
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
           (decl_mut_edit d))

let check_assign c a =
  let target = a.a_target in
  let vr =
    match target.kind with
    | Var vr -> vr
    | _ -> failwith "check_assign: the parser only allows names"
  in
  match Hashtbl.find_opt c.locals vr.var_name with
  | None ->
      if is_function c vr.var_name then
        Report.report
          (with_function_label
             (Diag.error target.span
                (sprintf "Cannot assign to function '%s'" vr.var_name)
                "")
             vr.var_name
             (Hashtbl.find_opt c.funcs vr.var_name)
             "Function defined here")
      else ignore (undeclared c target.span vr.var_name);
      ignore (check_value c a.a_value)
  | Some sym -> (
      vr.var_sym <- Some sym;
      target.ty <- sym.sym_ty;
      if not sym.sym_mut then begin
        let msg =
          sprintf "Cannot assign to %s'%s': it was declared without 'mut'"
            (if sym.sym_param then "parameter " else "")
            sym.sym_name
        in
        let d = Diag.error target.span msg "Cannot assign" in
        let d = Diag.with_label d sym.sym_span "Declared here without 'mut'" in
        Report.report
          (Diag.with_help d "Declare it with 'mut'" [ sym.sym_mut_edit ])
      end;
      let vt = check_value c a.a_value in
      match a.a_op with
      | None ->
          if mismatch vt sym.sym_ty then
            Report.report
              (Diag.with_label
                 (Diag.error a.a_value.span
                    (sprintf
                       "Cannot assign a value of type %s to '%s' of type %s"
                       (ty_name vt) sym.sym_name (ty_name sym.sym_ty))
                    ("This is " ^ ty_name vt))
                 sym.sym_type_span
                 (sprintf "'%s' is declared as %s here" sym.sym_name
                    (ty_name sym.sym_ty)))
      | Some op ->
          if sym.sym_ty <> Err && vt <> Err && (sym.sym_ty <> I32 || vt <> I32)
          then
            operand_error a.a_op_span
              (sprintf "Operator '%s=' expects i32 operands, found %s and %s"
                 (binop_text op) (ty_name sym.sym_ty) (ty_name vt))
              target sym.sym_ty a.a_value vt)

(* A secondary label at the function's return type, if it has one. *)
let with_return_label d f =
  match f.ret_ann with
  | Some ann ->
      Diag.with_label d ann.t_span
        (sprintf "Declared to return %s here" (ty_name f.ret_ty))
  | None -> d

let rec check_stmt c s =
  match s.skind with
  | Call_stmt e -> ignore (check_expr c e)
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
        ignore (check_expr c e)
      end
      else
        let t = check_value c e in
        if mismatch t f.ret_ty then
          Report.report
            (with_return_label
               (Diag.error e.span
                  (sprintf
                     "'%s' returns %s, but this 'return' has a value of type %s"
                     f.f_name (ty_name f.ret_ty) (ty_name t))
                  ("This is " ^ ty_name t))
               f)

and check_cond c keyword e =
  let t = check_value c e in
  if is_not t Bool then begin
    let d =
      Diag.error e.span
        (sprintf "Condition of '%s' must be bool, found %s" keyword (ty_name t))
        "Expected bool"
    in
    Report.report
      (if t = I32 then
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
           mut_edit)
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

let check_func c f =
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

let check_file (file : file) =
  let c =
    {
      file = file.path;
      funcs = Hashtbl.create 16;
      locals = Hashtbl.create 16;
      scopes = [];
      ended = [];
      next_id = 1;
      cur_func = None;
    }
  in
  List.iter (declare_func c) file.funcs;
  if not (Hashtbl.mem c.funcs "main") then
    Report.report
      (Diag.with_help
         (Diag.file_error c.file "No 'main' function found")
         "Add one, like 'main :: fn() { }'" []);
  List.iter (check_func c) file.funcs
