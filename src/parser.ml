(* Recursive descent, one function per grammar rule. *)

open Ast

type parser = { toks : Token.t array; mutable pos : int }

let peek p = p.toks.(p.pos)
let peek_kind p = (peek p).Token.kind

let peek2_kind p =
  if p.pos + 1 < Array.length p.toks then p.toks.(p.pos + 1).Token.kind
  else Token.Eof

let advance p =
  let tok = peek p in
  if tok.kind <> Token.Eof then p.pos <- p.pos + 1;
  tok

let fail_expected p what =
  let tok = peek p in
  Diag.fatal tok.loc
    (Printf.sprintf "expected %s, found %s" what (Token.describe tok))

let expect p kind what =
  if peek_kind p = kind then advance p else fail_expected p what

let expect_ident p what =
  match peek_kind p with
  | Token.Ident _ -> advance p
  | _ -> fail_expected p what

(* A missing ';' is reported just past the statement's last token, which is
   usually on the line before the token that revealed it. *)
let expect_semi p =
  if peek_kind p = Token.Semi then ignore (advance p)
  else
    let last = p.toks.(p.pos - 1) in
    Diag.fatal last.end_loc "expected ';' at the end of this statement"

let mk_expr kind loc = { kind; loc; ty = Void }

let parse_type p =
  let tok = expect_ident p "a type" in
  { t_name = tok.text; t_loc = tok.loc }

(* ---- Expressions, lowest precedence first ---- *)

let comparison_op kind =
  match kind with
  | Token.EqEq -> Some Eq
  | Token.NotEq -> Some Ne
  | Token.Lt -> Some Lt
  | Token.Le -> Some Le
  | Token.Gt -> Some Gt
  | Token.Ge -> Some Ge
  | _ -> None

let additive_op kind =
  match kind with Token.Plus -> Some Add | Token.Minus -> Some Sub | _ -> None

let multiplicative_op kind =
  match kind with
  | Token.Star -> Some Mul
  | Token.Slash -> Some Div
  | Token.Percent -> Some Rem
  | _ -> None

let mk_binary op op_loc lhs rhs =
  mk_expr (Binary { op; op_loc; lhs; rhs }) lhs.loc

let rec parse_expr p = parse_or p

and parse_or p =
  let lhs = parse_and p in
  parse_or_rest p lhs

and parse_or_rest p lhs =
  if peek_kind p = Token.OrOr then begin
    let op_tok = advance p in
    let rhs = parse_and p in
    parse_or_rest p (mk_binary Or op_tok.loc lhs rhs)
  end
  else lhs

and parse_and p =
  let lhs = parse_comparison p in
  parse_and_rest p lhs

and parse_and_rest p lhs =
  if peek_kind p = Token.AndAnd then begin
    let op_tok = advance p in
    let rhs = parse_comparison p in
    parse_and_rest p (mk_binary And op_tok.loc lhs rhs)
  end
  else lhs

and parse_comparison p =
  let lhs = parse_additive p in
  match comparison_op (peek_kind p) with
  | None -> lhs
  | Some op -> (
      let op_tok = advance p in
      let rhs = parse_additive p in
      match comparison_op (peek_kind p) with
      | Some _ ->
          Diag.fatal (peek p).loc
            "comparisons cannot be chained; combine them with '&&'"
      | None -> mk_binary op op_tok.loc lhs rhs)

and parse_additive p =
  let lhs = parse_multiplicative p in
  parse_additive_rest p lhs

and parse_additive_rest p lhs =
  match additive_op (peek_kind p) with
  | None -> lhs
  | Some op ->
      let op_tok = advance p in
      let rhs = parse_multiplicative p in
      parse_additive_rest p (mk_binary op op_tok.loc lhs rhs)

and parse_multiplicative p =
  let lhs = parse_unary p in
  parse_multiplicative_rest p lhs

and parse_multiplicative_rest p lhs =
  match multiplicative_op (peek_kind p) with
  | None -> lhs
  | Some op ->
      let op_tok = advance p in
      let rhs = parse_unary p in
      parse_multiplicative_rest p (mk_binary op op_tok.loc lhs rhs)

and parse_unary p =
  let tok = peek p in
  match tok.kind with
  | Token.Minus -> (
      ignore (advance p);
      (* '-' directly before a literal folds into a negative literal, which
         is how -2147483648 is written. *)
      match peek_kind p with
      | Token.Int n ->
          ignore (advance p);
          mk_expr (Int (-n)) tok.loc
      | _ -> mk_expr (Unary (Neg, parse_unary p)) tok.loc)
  | Token.Bang ->
      ignore (advance p);
      mk_expr (Unary (Not, parse_unary p)) tok.loc
  | _ -> parse_primary p

and parse_primary p =
  let tok = peek p in
  match tok.kind with
  | Token.Int n ->
      ignore (advance p);
      mk_expr (Int n) tok.loc
  | Token.True ->
      ignore (advance p);
      mk_expr (Bool_lit true) tok.loc
  | Token.False ->
      ignore (advance p);
      mk_expr (Bool_lit false) tok.loc
  | Token.Ident name ->
      ignore (advance p);
      if peek_kind p = Token.LParen then begin
        ignore (advance p);
        let args = parse_args p in
        mk_expr (Call { callee = name; args }) tok.loc
      end
      else mk_expr (Var { var_name = name; var_sym = None }) tok.loc
  | Token.LParen ->
      ignore (advance p);
      let e = parse_expr p in
      ignore (expect p Token.RParen "')'");
      e
  | _ -> fail_expected p "an expression"

(* After the '('. *)
and parse_args p =
  if peek_kind p = Token.RParen then begin
    ignore (advance p);
    []
  end
  else parse_args_rest p []

and parse_args_rest p acc =
  let e = parse_expr p in
  let acc = e :: acc in
  if peek_kind p = Token.Comma then begin
    ignore (advance p);
    parse_args_rest p acc
  end
  else begin
    ignore (expect p Token.RParen "')'");
    List.rev acc
  end

(* ---- Statements ---- *)

let assign_op kind =
  match kind with
  | Token.Assign -> Some None
  | Token.PlusAssign -> Some (Some Add)
  | Token.MinusAssign -> Some (Some Sub)
  | Token.StarAssign -> Some (Some Mul)
  | Token.SlashAssign -> Some (Some Div)
  | Token.PercentAssign -> Some (Some Rem)
  | _ -> None

let rec parse_block p =
  ignore (expect p Token.LBrace "'{'");
  parse_block_rest p []

and parse_block_rest p acc =
  match peek_kind p with
  | Token.RBrace ->
      let close = advance p in
      { stmts = List.rev acc; close_loc = close.loc }
  | Token.Eof -> fail_expected p "'}'"
  | _ ->
      let s = parse_stmt p in
      parse_block_rest p (s :: acc)

and parse_stmt p =
  let tok = peek p in
  match tok.kind with
  | Token.Semi -> Diag.fatal tok.loc "unexpected ';'"
  | Token.If ->
      ignore (advance p);
      { skind = If (parse_if p); sloc = tok.loc }
  | Token.While ->
      ignore (advance p);
      let w_cond = parse_expr p in
      let w_body = parse_block p in
      { skind = While { w_cond; w_body }; sloc = tok.loc }
  | Token.Return -> parse_return p
  | Token.LBrace -> { skind = Block (parse_block p); sloc = tok.loc }
  | Token.Ident _
    when peek2_kind p = Token.ColonEq || peek2_kind p = Token.Colon ->
      parse_decl p
  | _ -> parse_simple p

(* After the 'if'. *)
and parse_if p =
  let cond = parse_expr p in
  let then_block = parse_block p in
  if peek_kind p = Token.Else then begin
    ignore (advance p);
    match peek_kind p with
    | Token.If ->
        ignore (advance p);
        { cond; then_block; else_part = Else_if (parse_if p) }
    | Token.LBrace ->
        { cond; then_block; else_part = Else_block (parse_block p) }
    | _ -> fail_expected p "'{' or 'if' after 'else'"
  end
  else { cond; then_block; else_part = No_else }

and parse_return p =
  let tok = advance p in
  match peek_kind p with
  | Token.Semi ->
      ignore (advance p);
      { skind = Return None; sloc = tok.loc }
  | Token.RBrace ->
      expect_semi p;
      { skind = Return None; sloc = tok.loc }
  | _ ->
      let e = parse_expr p in
      expect_semi p;
      { skind = Return (Some e); sloc = tok.loc }

and parse_decl p =
  let name = advance p in
  let d_name = name.text in
  if peek_kind p = Token.ColonEq then begin
    ignore (advance p);
    let init = parse_expr p in
    expect_semi p;
    {
      skind =
        Decl
          {
            d_name;
            d_mut = false;
            d_ann = None;
            d_init = Some init;
            d_sym = None;
          };
      sloc = name.loc;
    }
  end
  else begin
    ignore (expect p Token.Colon "':'");
    let d_mut =
      if peek_kind p = Token.Mut then begin
        ignore (advance p);
        true
      end
      else false
    in
    let d_ann =
      match peek_kind p with Token.Ident _ -> Some (parse_type p) | _ -> None
    in
    let d_init =
      if peek_kind p = Token.Assign then begin
        ignore (advance p);
        Some (parse_expr p)
      end
      else None
    in
    if d_ann = None && d_init = None then
      Diag.fatal name.loc
        (Printf.sprintf "'%s' needs a type or an initial value" d_name);
    expect_semi p;
    {
      skind = Decl { d_name; d_mut; d_ann; d_init; d_sym = None };
      sloc = name.loc;
    }
  end

and parse_simple p =
  let e = parse_expr p in
  match assign_op (peek_kind p) with
  | Some a_op ->
      let op_tok = advance p in
      (match e.kind with
      | Var _ -> ()
      | _ -> Diag.fatal e.loc "cannot assign to this expression");
      let value = parse_expr p in
      expect_semi p;
      {
        skind =
          Assign { a_op; a_op_loc = op_tok.loc; a_target = e; a_value = value };
        sloc = e.loc;
      }
  | None -> (
      match e.kind with
      | Call _ ->
          expect_semi p;
          { skind = Call_stmt e; sloc = e.loc }
      | _ ->
          Diag.fatal e.loc
            "this expression does nothing; only calls can be used as statements"
      )

(* ---- Functions and the file ---- *)

let rec parse_param_names p acc =
  let tok = expect_ident p "a parameter name" in
  let acc = tok :: acc in
  if peek_kind p = Token.Comma then begin
    ignore (advance p);
    parse_param_names p acc
  end
  else List.rev acc

let make_param p_mut p_ann (tok : Token.t) =
  { p_name = tok.text; p_loc = tok.loc; p_mut; p_ann; p_sym = None }

(* One group, like 'a, b: mut i32'. *)
let parse_param_group p =
  let names = parse_param_names p [] in
  ignore (expect p Token.Colon "':'");
  let is_mut =
    if peek_kind p = Token.Mut then begin
      ignore (advance p);
      true
    end
    else false
  in
  let ann = parse_type p in
  List.map (make_param is_mut ann) names

let rec parse_param_groups p acc =
  let group = parse_param_group p in
  let acc = List.rev_append group acc in
  if peek_kind p = Token.Comma then begin
    ignore (advance p);
    parse_param_groups p acc
  end
  else List.rev acc

let parse_func p =
  let name = advance p in
  ignore (expect p Token.ColonColon "'::'");
  ignore (expect p Token.Fn "'fn'");
  ignore (expect p Token.LParen "'('");
  let params =
    if peek_kind p = Token.RParen then [] else parse_param_groups p []
  in
  ignore (expect p Token.RParen "')'");
  let ret_ann =
    if peek_kind p = Token.Arrow then begin
      ignore (advance p);
      Some (parse_type p)
    end
    else None
  in
  let body = parse_block p in
  {
    f_name = name.text;
    f_loc = name.loc;
    params;
    ret_ann;
    body;
    param_tys = [];
    ret_ty = Void;
    nsyms = 0;
  }

let rec parse_funcs p acc =
  let tok = peek p in
  match tok.kind with
  | Token.Eof -> List.rev acc
  | Token.Semi -> Diag.fatal tok.loc "unexpected ';'"
  | Token.Ident _ ->
      let f = parse_func p in
      parse_funcs p (f :: acc)
  | _ -> fail_expected p "a function definition"

let parse_file path toks =
  let p = { toks; pos = 0 } in
  { path; funcs = parse_funcs p [] }
