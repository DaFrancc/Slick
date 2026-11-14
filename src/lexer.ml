(* Turns source text into an array of tokens. Newlines are whitespace. *)

open Token

type lexer = {
  src : string;
  file : string;
  mutable pos : int;
  mutable line : int;
  mutable col : int;
  mutable toks : Token.t list; (* in reverse order *)
}

(* Keywords that later milestones use. Using one is an error now, so that no
   program written today breaks when they arrive. *)
let reserved =
  [
    "for";
    "in";
    "loop";
    "break";
    "continue";
    "match";
    "struct";
    "enum";
    "defer";
    "errdefer";
    "try";
    "import";
    "as";
    "cast";
    "bitcast";
  ]

let here lx = { Diag.file = lx.file; line = lx.line; col = lx.col }
let at_end lx = lx.pos >= String.length lx.src

let peek_at lx offset =
  if lx.pos + offset < String.length lx.src then lx.src.[lx.pos + offset]
  else '\000'

let advance lx =
  if lx.src.[lx.pos] = '\n' then begin
    lx.line <- lx.line + 1;
    lx.col <- 1
  end
  else lx.col <- lx.col + 1;
  lx.pos <- lx.pos + 1

let is_digit c = c >= '0' && c <= '9'

let is_ident_start c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'

let is_ident_char c = is_ident_start c || is_digit c

let push lx kind start_pos start_loc =
  let text = String.sub lx.src start_pos (lx.pos - start_pos) in
  lx.toks <- { kind; text; loc = start_loc; end_loc = here lx } :: lx.toks

let rec skip_trivia lx =
  if not (at_end lx) then begin
    let c = peek_at lx 0 in
    if c = ' ' || c = '\t' || c = '\n' || c = '\r' then begin
      advance lx;
      skip_trivia lx
    end
    else if c = '/' && peek_at lx 1 = '/' then begin
      while (not (at_end lx)) && peek_at lx 0 <> '\n' do
        advance lx
      done;
      skip_trivia lx
    end
  end

let keyword_kind word =
  match word with
  | "fn" -> Some Fn
  | "mut" -> Some Mut
  | "if" -> Some If
  | "else" -> Some Else
  | "while" -> Some While
  | "return" -> Some Return
  | "true" -> Some True
  | "false" -> Some False
  | _ -> None

let lex_word lx =
  let start_pos = lx.pos in
  let start_loc = here lx in
  while (not (at_end lx)) && is_ident_char (peek_at lx 0) do
    advance lx
  done;
  let word = String.sub lx.src start_pos (lx.pos - start_pos) in
  if List.mem word reserved then
    Diag.fatal start_loc (Printf.sprintf "'%s' is not supported yet" word);
  match keyword_kind word with
  | Some kind -> push lx kind start_pos start_loc
  | None -> push lx (Ident word) start_pos start_loc

(* Decimal digits with optional '_' separators. The value is accumulated by
   hand, stopping once it is out of range, so no literal can overflow. *)
let lex_int lx =
  let start_pos = lx.pos in
  let start_loc = here lx in
  while (not (at_end lx)) && is_ident_char (peek_at lx 0) do
    advance lx
  done;
  let text = String.sub lx.src start_pos (lx.pos - start_pos) in
  let value = ref 0 in
  let too_big = ref false in
  for i = 0 to String.length text - 1 do
    let c = text.[i] in
    if is_digit c then
      begin if not !too_big then begin
        value := (!value * 10) + (Char.code c - Char.code '0');
        if !value > 2147483648 then too_big := true
      end
      end
    else if c <> '_' then
      Diag.fatal start_loc
        (Printf.sprintf "'%s' is not a valid integer literal" text)
  done;
  if !too_big then
    Diag.fatal start_loc
      (Printf.sprintf "integer literal %s does not fit in i32" text);
  push lx (Int !value) start_pos start_loc

(* Two-character operators are matched before one-character ones. *)
let two_char_kind a b =
  match (a, b) with
  | ':', ':' -> Some ColonColon
  | ':', '=' -> Some ColonEq
  | '-', '>' -> Some Arrow
  | '=', '=' -> Some EqEq
  | '!', '=' -> Some NotEq
  | '<', '=' -> Some Le
  | '>', '=' -> Some Ge
  | '&', '&' -> Some AndAnd
  | '|', '|' -> Some OrOr
  | '+', '=' -> Some PlusAssign
  | '-', '=' -> Some MinusAssign
  | '*', '=' -> Some StarAssign
  | '/', '=' -> Some SlashAssign
  | '%', '=' -> Some PercentAssign
  | _ -> None

let one_char_kind c =
  match c with
  | '(' -> Some LParen
  | ')' -> Some RParen
  | '{' -> Some LBrace
  | '}' -> Some RBrace
  | ',' -> Some Comma
  | ';' -> Some Semi
  | ':' -> Some Colon
  | '+' -> Some Plus
  | '-' -> Some Minus
  | '*' -> Some Star
  | '/' -> Some Slash
  | '%' -> Some Percent
  | '=' -> Some Assign
  | '<' -> Some Lt
  | '>' -> Some Gt
  | '!' -> Some Bang
  | _ -> None

let describe_char c =
  let code = Char.code c in
  if code >= 33 && code <= 126 then Printf.sprintf "unexpected character '%c'" c
  else Printf.sprintf "unexpected byte 0x%02X" code

let lex_punct lx =
  let start_pos = lx.pos in
  let start_loc = here lx in
  let c = peek_at lx 0 in
  match two_char_kind c (peek_at lx 1) with
  | Some kind ->
      advance lx;
      advance lx;
      push lx kind start_pos start_loc
  | None -> (
      match one_char_kind c with
      | Some kind ->
          advance lx;
          push lx kind start_pos start_loc
      | None -> Diag.fatal start_loc (describe_char c))

let rec lex_all lx =
  skip_trivia lx;
  if at_end lx then push lx Eof lx.pos (here lx)
  else begin
    let c = peek_at lx 0 in
    if is_ident_start c then lex_word lx
    else if is_digit c then lex_int lx
    else lex_punct lx;
    lex_all lx
  end

let tokenize file src =
  let lx = { src; file; pos = 0; line = 1; col = 1; toks = [] } in
  lex_all lx;
  Array.of_list (List.rev lx.toks)
