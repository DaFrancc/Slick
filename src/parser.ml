(* Recursive descent, one function per grammar rule.

   Error recovery uses a flag, as in Wirth's compilers. After an error that
   leaves the parser unsure where it is, it sets [panicking]: later errors are
   not reported, and [expect] does not consume tokens. After each statement,
   and each top-level item, a panicking parser skips ahead to a boundary and
   clears the flag. Placeholders (a literal 0, an empty block) stand in for
   what could not be parsed; the checker never sees them, because it only runs
   when there were no syntax errors.

   Every loop consumes at least one token per pass, even when panicking, so
   no input can make the parser loop forever. *)

open Ast

type parser = {
  toks : Token.t array;
  mutable pos : int;
  mutable panicking : bool;
}

let peek p = p.toks.(p.pos)
let peek_kind p = (peek p).Token.kind

let peek2_kind p =
  if p.pos + 1 < Array.length p.toks then p.toks.(p.pos + 1).Token.kind
  else Token.Eof

let advance p =
  let tok = peek p in
  if tok.kind <> Token.Eof then p.pos <- p.pos + 1;
  tok

(* The span of the last token consumed. *)
let prev_span p = p.toks.(max 0 (p.pos - 1)).Token.span
let prev_kind p = if p.pos > 0 then p.toks.(p.pos - 1).Token.kind else Token.Eof

(* ---- Reporting ---- *)

(* An error after which the parser cannot trust where it is. *)
let syntax_error p d =
  if not p.panicking then Report.report d;
  p.panicking <- true

(* An error after which parsing can go on as normal. *)
let soft_error p d = if not p.panicking then Report.report d

let expected_error p what =
  let tok = peek p in
  Diag.error tok.span
    (Printf.sprintf "Expected %s, found %s" what (Token.describe tok))
    ("Expected " ^ what)

let fail_expected p what = syntax_error p (expected_error p what)

(* At the top level, where only function definitions are allowed so far. *)
let fail_top_level p what =
  syntax_error p
    (Diag.with_note (expected_error p what)
       "Only functions can be defined at the top level for now")

(* On a mismatch, reports and returns the current token without consuming
   it. *)
let expect p kind what =
  if peek_kind p = kind then advance p
  else begin
    fail_expected p what;
    peek p
  end

let expect_ident p what =
  match peek_kind p with
  | Token.Ident _ -> advance p
  | _ ->
      fail_expected p what;
      peek p

(* A missing ';' is reported just past the statement's last token, which is
   usually on the line before the token that revealed it. When the next token
   is on a later line, or is '}', the ';' was most likely just forgotten, so
   parsing goes on as if it were there. *)
let expect_semi p =
  if peek_kind p = Token.Semi then ignore (advance p)
  else begin
    let last = prev_span p in
    let at = Diag.point_after last in
    let d =
      Diag.with_insert
        (Diag.error at "Expected ';' at the end of this statement"
           "Expected ';'")
        ";"
    in
    let next = peek p in
    if next.span.start_line > last.end_line || next.kind = Token.RBrace then
      soft_error p d
    else syntax_error p d
  end

(* The ')' that closes a '('. When it is missing and what follows is on a
   later line, or ends the statement or block, the ')' was most likely just
   forgotten: the error shows it, in green, right after the last token, where
   it belongs. When something else follows on the same line, as in
   'print(1 2)', a ')' is probably not the fix, so the error is the plain
   "expected". *)
let expect_close_paren p =
  if peek_kind p = Token.RParen then advance p
  else begin
    let next = peek p in
    let last = prev_span p in
    let forgotten =
      next.span.start_line > last.end_line
      ||
      match next.kind with
      | Token.Semi | Token.LBrace | Token.RBrace | Token.Eof -> true
      | _ -> false
    in
    syntax_error p
      (if forgotten then
         Diag.with_insert
           (Diag.error (Diag.point_after last) "Unclosed '('" "Expected ')'")
           ")"
       else expected_error p "')'");
    next
  end

(* A ';' where no statement or definition can start. It is consumed. *)
let stray_semi p top_level =
  let tok = advance p in
  let d =
    Diag.with_help
      (Diag.error tok.span "Unexpected ';'" "Not needed here")
      "Remove it"
      [ Diag.edit tok.span "" ]
  in
  let after_function =
    top_level && p.pos > 1 && p.toks.(p.pos - 2).Token.kind = Token.RBrace
  in
  soft_error p
    (if after_function then
       Diag.with_note d "A function definition ends at its '}'"
     else d)

(* ---- Synchronizing ---- *)

let at_statement_boundary p =
  match peek_kind p with
  | Token.RBrace | Token.If | Token.While | Token.Return | Token.Eof -> true
  | _ -> false

(* After a statement that started at token [start] and left the parser
   panicking: skip to just after a ';', or to a token that ends a block or
   starts a statement. At least one token is consumed unless the parser is
   already at such a token. *)
let synchronize p start =
  if p.pos = start && not (at_statement_boundary p) then ignore (advance p);
  if prev_kind p <> Token.Semi then begin
    (* Blocks are skipped whole, so the '}' of a block inside the broken
       statement does not end the enclosing block. *)
    let depth = ref 0 in
    let stop = ref false in
    while not !stop do
      match peek_kind p with
      | Token.Eof -> stop := true
      | Token.LBrace ->
          incr depth;
          ignore (advance p)
      | Token.RBrace ->
          if !depth = 0 then stop := true
          else begin
            decr depth;
            ignore (advance p)
          end
      | Token.Semi ->
          ignore (advance p);
          if !depth = 0 then stop := true
      | (Token.If | Token.While | Token.Return) when !depth = 0 -> stop := true
      | _ -> ignore (advance p)
    done
  end;
  p.panicking <- false

let at_function_start p =
  match peek_kind p with
  | Token.Ident _ -> peek2_kind p = Token.ColonColon
  | _ -> false

(* The same at the top level: skip to the next 'name ::' or the end. *)
let synchronize_top p start =
  if p.pos = start && peek_kind p <> Token.Eof then ignore (advance p);
  while peek_kind p <> Token.Eof && not (at_function_start p) do
    ignore (advance p)
  done;
  p.panicking <- false

let mk_expr kind span = { kind; span; ty = Void }

(* What stands in for an expression that could not be parsed. *)
let placeholder p = mk_expr (Int 0) (peek p).span

let parse_type p =
  let tok = expect_ident p "a type" in
  { t_name = tok.text; t_span = tok.span }

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

(* 'a < b < c': suggest 'a < b && b < c', repeating the middle operand. *)
let chained_comparison p (first : Token.t) (second : Token.t) middle =
  let d = Diag.error second.span "Comparisons cannot be chained" "" in
  let d = Diag.with_label d first.span "" in
  let edits =
    match Report.span_text middle.span with
    | Some text ->
        [ Diag.edit (Diag.point_before second.span) ("&& " ^ text ^ " ") ]
    | None -> []
  in
  soft_error p (Diag.with_help d "Combine them with '&&'" edits)

let mk_binary op op_span lhs rhs =
  mk_expr (Binary { op; op_span; lhs; rhs }) (Diag.join lhs.span rhs.span)

let rec parse_expr p = parse_or p

and parse_or p =
  let lhs = parse_and p in
  parse_or_rest p lhs

and parse_or_rest p lhs =
  if peek_kind p = Token.OrOr then begin
    let op_tok = advance p in
    let rhs = parse_and p in
    parse_or_rest p (mk_binary Or op_tok.span lhs rhs)
  end
  else lhs

and parse_and p =
  let lhs = parse_comparison p in
  parse_and_rest p lhs

and parse_and_rest p lhs =
  if peek_kind p = Token.AndAnd then begin
    let op_tok = advance p in
    let rhs = parse_comparison p in
    parse_and_rest p (mk_binary And op_tok.span lhs rhs)
  end
  else lhs

and parse_comparison p =
  let lhs = parse_additive p in
  match comparison_op (peek_kind p) with
  | None -> lhs
  | Some op -> (
      let op_tok = advance p in
      let rhs = parse_additive p in
      let e = mk_binary op op_tok.span lhs rhs in
      match comparison_op (peek_kind p) with
      | Some _ ->
          chained_comparison p op_tok (peek p) rhs;
          parse_chain_rest p e
      | None -> e)

(* After a chained comparison has been reported, the rest of the chain is
   parsed without further errors. *)
and parse_chain_rest p lhs =
  match comparison_op (peek_kind p) with
  | None -> lhs
  | Some op ->
      let op_tok = advance p in
      let rhs = parse_additive p in
      parse_chain_rest p (mk_binary op op_tok.span lhs rhs)

and parse_additive p =
  let lhs = parse_multiplicative p in
  parse_additive_rest p lhs

and parse_additive_rest p lhs =
  match additive_op (peek_kind p) with
  | None -> lhs
  | Some op ->
      let op_tok = advance p in
      let rhs = parse_multiplicative p in
      parse_additive_rest p (mk_binary op op_tok.span lhs rhs)

and parse_multiplicative p =
  let lhs = parse_unary p in
  parse_multiplicative_rest p lhs

and parse_multiplicative_rest p lhs =
  match multiplicative_op (peek_kind p) with
  | None -> lhs
  | Some op ->
      let op_tok = advance p in
      let rhs = parse_unary p in
      parse_multiplicative_rest p (mk_binary op op_tok.span lhs rhs)

and parse_unary p =
  let tok = peek p in
  match tok.kind with
  | Token.Minus -> (
      ignore (advance p);
      (* '-' directly before a literal folds into a negative literal, which
         is how -2147483648 is written. *)
      match peek_kind p with
      | Token.Int n ->
          let lit = advance p in
          mk_expr (Int (-n)) (Diag.join tok.span lit.span)
      | _ ->
          let x = parse_unary p in
          mk_expr (Unary (Neg, x)) (Diag.join tok.span x.span))
  | Token.Bang ->
      ignore (advance p);
      let x = parse_unary p in
      mk_expr (Unary (Not, x)) (Diag.join tok.span x.span)
  | _ -> parse_primary p

and parse_primary p =
  let tok = peek p in
  match tok.kind with
  | Token.Int n ->
      ignore (advance p);
      mk_expr (Int n) tok.span
  | Token.True ->
      ignore (advance p);
      mk_expr (Bool_lit true) tok.span
  | Token.False ->
      ignore (advance p);
      mk_expr (Bool_lit false) tok.span
  | Token.Ident name ->
      ignore (advance p);
      if peek_kind p = Token.LParen then begin
        let open_tok = advance p in
        let args = parse_args p in
        let args_span = Diag.join open_tok.span (prev_span p) in
        mk_expr
          (Call { callee = name; callee_span = tok.span; args; args_span })
          (Diag.join tok.span args_span)
      end
      else mk_expr (Var { var_name = name; var_sym = None }) tok.span
  | Token.LParen ->
      ignore (advance p);
      let e = parse_expr p in
      let close = expect_close_paren p in
      { e with span = Diag.join tok.span close.span }
  | _ ->
      fail_expected p "an expression";
      placeholder p

(* After the '('. Consumes the ')'. *)
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
    ignore (expect_close_paren p);
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

(* A statement from [start] to the last token consumed. *)
let mk_stmt p skind (start : Diag.span) =
  { skind; sspan = Diag.join start (prev_span p) }

(* What stands in for a statement that could not be parsed. *)
let empty_stmt p (start : Diag.span) =
  mk_stmt p (Block { stmts = []; close_span = start }) start

(* Reaching the end of the file, or the next function, inside a block. The
   '{' that was never closed gets a label. *)
let unclosed_block p open_span =
  let d =
    Diag.with_label (expected_error p "'}'") open_span "This '{' is not closed"
  in
  syntax_error p
    (if peek_kind p = Token.Eof then d
     else Diag.with_note d "A function cannot be defined inside another one")

let rec parse_block p =
  if peek_kind p = Token.LBrace then begin
    let open_tok = advance p in
    parse_block_rest p open_tok.span []
  end
  else begin
    (* Without its '{', what follows is not parsed as a block at all: the
       enclosing statement skips it. *)
    fail_expected p "'{'";
    { stmts = []; close_span = (peek p).span }
  end

and parse_block_rest p open_span acc =
  match peek_kind p with
  | Token.RBrace ->
      let close = advance p in
      { stmts = List.rev acc; close_span = close.span }
  | Token.Eof ->
      unclosed_block p open_span;
      { stmts = List.rev acc; close_span = (peek p).span }
  | Token.Ident _ when peek2_kind p = Token.ColonColon ->
      unclosed_block p open_span;
      { stmts = List.rev acc; close_span = (peek p).span }
  | _ ->
      let start = p.pos in
      let s = parse_stmt p in
      if p.panicking then synchronize p start;
      parse_block_rest p open_span (s :: acc)

and parse_stmt p =
  let tok = peek p in
  match tok.kind with
  | Token.Semi ->
      stray_semi p false;
      empty_stmt p tok.span
  | Token.If ->
      ignore (advance p);
      let ifs = parse_if p in
      mk_stmt p (If ifs) tok.span
  | Token.While ->
      ignore (advance p);
      let w_cond = parse_expr p in
      let w_body = parse_block p in
      mk_stmt p (While { w_cond; w_body }) tok.span
  | Token.Return -> parse_return p
  | Token.LBrace ->
      let b = parse_block p in
      mk_stmt p (Block b) tok.span
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
    | _ ->
        fail_expected p "'{' or 'if' after 'else'";
        { cond; then_block; else_part = No_else }
  end
  else { cond; then_block; else_part = No_else }

and parse_return p =
  let tok = advance p in
  let ret_value =
    match peek_kind p with
    | Token.Semi | Token.RBrace -> None
    | _ -> Some (parse_expr p)
  in
  expect_semi p;
  mk_stmt p (Return { ret_value; ret_kw_span = tok.span }) tok.span

and parse_decl p =
  let name = advance p in
  let sep = advance p in
  let d_colon_eq = sep.kind = Token.ColonEq in
  let d_mut =
    if (not d_colon_eq) && peek_kind p = Token.Mut then begin
      ignore (advance p);
      true
    end
    else false
  in
  let d_ann =
    match peek_kind p with
    | Token.Ident _ when not d_colon_eq -> Some (parse_type p)
    | _ -> None
  in
  let d_init =
    if d_colon_eq then Some (parse_expr p)
    else if peek_kind p = Token.Assign then begin
      ignore (advance p);
      Some (parse_expr p)
    end
    else None
  in
  if d_ann = None && d_init = None then begin
    let m = if d_mut then "mut " else "" in
    soft_error p
      (Diag.with_help
         (Diag.error name.span
            (Printf.sprintf "'%s' needs a type or an initial value" name.text)
            "")
         (Printf.sprintf
            "Give it a type, like '%s : %si32;', or a value, like '%s : %s= 0;'"
            name.text m name.text m)
         [])
  end;
  expect_semi p;
  mk_stmt p
    (Decl
       {
         d_name = name.text;
         d_name_span = name.span;
         d_sep_span = sep.span;
         d_colon_eq;
         d_mut;
         d_ann;
         d_init;
         d_sym = None;
       })
    name.span

and parse_simple p =
  let e = parse_expr p in
  match assign_op (peek_kind p) with
  | Some a_op ->
      let op_tok = advance p in
      (match e.kind with
      | Var _ -> ()
      | _ ->
          soft_error p
            (Diag.with_note
               (Diag.error e.span "Cannot assign to this expression"
                  "Not a name")
               "Only local names can be assigned to"));
      let value = parse_expr p in
      expect_semi p;
      mk_stmt p
        (Assign { a_op; a_op_span = op_tok.span; a_target = e; a_value = value })
        e.span
  | None -> (
      match e.kind with
      | Call _ ->
          expect_semi p;
          mk_stmt p (Call_stmt e) e.span
      | _ ->
          let next = peek p in
          let ends =
            next.span.start_line > e.span.end_line
            ||
            match next.kind with
            | Token.Semi | Token.RBrace | Token.Eof -> true
            | _ -> false
          in
          (if ends then begin
             does_nothing p e;
             expect_semi p
           end
           else
             (* More follows on the same line: a misspelled keyword, like
                'whle i < 10 {', or words that do not belong. *)
             match e.kind with
             | Var { var_name; _ } when keyword_like var_name <> None ->
                 misspelled_keyword p e var_name
             | _ -> fail_expected p "';'");
          empty_stmt p e.span)

and keyword_like name =
  Suggest.closest name
    [
      ("while", 0);
      ("if", 1);
      ("else", 2);
      ("return", 3);
      ("mut", 4);
      ("fn", 5);
      ("true", 6);
      ("false", 7);
    ]

and misspelled_keyword p e name =
  let d = Diag.error e.span (Printf.sprintf "'%s' is not a keyword" name) "" in
  syntax_error p
    (match keyword_like name with
    | Some kw ->
        Diag.with_help d
          (Printf.sprintf "Did you mean '%s'?" kw)
          [ Diag.edit e.span kw ]
    | None -> d)

(* An expression statement that is not a call. 'x == 1;' was probably meant
   to be an assignment. *)
and does_nothing p e =
  let d =
    Diag.error e.span "This expression does nothing" "Its value is not used"
  in
  let d =
    match e.kind with
    | Binary { op = Eq; op_span; lhs = { kind = Var _; _ }; _ } ->
        Diag.with_help d "To assign, use '='" [ Diag.edit op_span "=" ]
    | _ -> (
        match Report.span_text e.span with
        | Some text ->
            Diag.with_help d
              (Printf.sprintf
                 "Only calls can be statements. To keep the value, give it a \
                  name: 'value := %s;'."
                 text)
              []
        | None -> Diag.with_help d "Only calls can be statements" [])
  in
  soft_error p d

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
  { p_name = tok.text; p_span = tok.span; p_mut; p_ann; p_sym = None }

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

(* After an error in a signature: skip to the token [kind] or to the body's
   '{', and carry on. A ')' is consumed; the '{' is left for the body. *)
let recover_in_signature p kind =
  while
    peek_kind p <> kind
    && peek_kind p <> Token.LBrace
    && peek_kind p <> Token.Eof
  do
    ignore (advance p)
  done;
  if kind <> Token.LBrace && peek_kind p = kind then ignore (advance p);
  p.panicking <- false

(* Returns None if the definition is broken before its parameter list; the
   caller then skips to the next definition. *)
let parse_func p =
  let name = advance p in
  if peek_kind p <> Token.ColonColon then begin
    fail_top_level p "'::'";
    None
  end
  else begin
    ignore (advance p);
    if peek_kind p <> Token.Fn then begin
      fail_top_level p "'fn'";
      None
    end
    else begin
      ignore (advance p);
      let open_span = (peek p).span in
      let has_open = peek_kind p = Token.LParen in
      if has_open then ignore (advance p) else fail_expected p "'('";
      let params =
        if has_open && peek_kind p <> Token.RParen then parse_param_groups p []
        else []
      in
      if not p.panicking then ignore (expect p Token.RParen "')'");
      if p.panicking then recover_in_signature p Token.RParen;
      let params_span = Diag.join open_span (prev_span p) in
      let ret_ann =
        if peek_kind p = Token.Arrow then begin
          ignore (advance p);
          Some (parse_type p)
        end
        else None
      in
      if p.panicking then recover_in_signature p Token.LBrace;
      let body = parse_block p in
      Some
        {
          f_name = name.text;
          f_name_span = name.span;
          params;
          params_span;
          ret_ann;
          body;
          param_tys = [];
          ret_ty = Void;
          nsyms = 0;
        }
    end
  end

let rec parse_funcs p acc =
  match peek_kind p with
  | Token.Eof -> List.rev acc
  | Token.Semi ->
      stray_semi p true;
      parse_funcs p acc
  | Token.Ident _ ->
      let start = p.pos in
      let acc = match parse_func p with Some f -> f :: acc | None -> acc in
      if p.panicking then synchronize_top p start;
      parse_funcs p acc
  | _ ->
      let start = p.pos in
      fail_top_level p "a function definition";
      synchronize_top p start;
      parse_funcs p acc

let parse_file path toks =
  let p = { toks; pos = 0; panicking = false } in
  { path; funcs = parse_funcs p [] }
