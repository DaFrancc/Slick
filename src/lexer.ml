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

(* The point at the current position. *)
let here lx =
  {
    Diag.file = lx.file;
    start_line = lx.line;
    start_col = lx.col;
    end_line = lx.line;
    end_col = lx.col;
  }

(* From [start] to the current position. *)
let since lx (start : Diag.span) =
  { start with end_line = lx.line; end_col = lx.col }

let at_end lx = lx.pos >= String.length lx.src

let peek_at lx offset =
  if lx.pos + offset < String.length lx.src then lx.src.[lx.pos + offset]
  else '\000'

(* Columns count characters: a UTF-8 continuation byte (10xxxxxx) does not
   start a new one. *)
let advance lx =
  let c = lx.src.[lx.pos] in
  if c = '\n' then begin
    lx.line <- lx.line + 1;
    lx.col <- 1
  end
  else if Char.code c land 0xC0 <> 0x80 then lx.col <- lx.col + 1;
  lx.pos <- lx.pos + 1

let is_digit c = c >= '0' && c <= '9'
let is_continuation c = Char.code c land 0xC0 = 0x80

let is_ident_start c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'

let is_ident_char c = is_ident_start c || is_digit c

let push lx kind start_pos start =
  let text = String.sub lx.src start_pos (lx.pos - start_pos) in
  lx.toks <- { kind; text; span = since lx start } :: lx.toks

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
  let start = here lx in
  while (not (at_end lx)) && is_ident_char (peek_at lx 0) do
    advance lx
  done;
  let word = String.sub lx.src start_pos (lx.pos - start_pos) in
  (* A reserved word is reported, then treated as a name. *)
  if List.mem word reserved then
    Report.report
      (Diag.error (since lx start)
         (Printf.sprintf "'%s' is not supported yet" word)
         "Reserved for a later version of Slick");
  match keyword_kind word with
  | Some kind -> push lx kind start_pos start
  | None -> push lx (Ident word) start_pos start

let i32_range_note = "An i32 holds values from -2147483648 to 2147483647"

(* Decimal digits with optional '_' separators. The value is accumulated by
   hand, stopping once it is out of range, so no literal can overflow. *)
let lex_int lx =
  let start_pos = lx.pos in
  let start = here lx in
  while (not (at_end lx)) && is_ident_char (peek_at lx 0) do
    advance lx
  done;
  let text = String.sub lx.src start_pos (lx.pos - start_pos) in
  let value = ref 0 in
  let too_big = ref false in
  let valid = ref true in
  for i = 0 to String.length text - 1 do
    let c = text.[i] in
    if is_digit c then
      begin if not !too_big then begin
        value := (!value * 10) + (Char.code c - Char.code '0');
        if !value > 2147483648 then too_big := true
      end
      end
    else if c <> '_' then valid := false
  done;
  (* A bad literal is reported, then treated as 0. *)
  if not !valid then begin
    Report.report
      (Diag.with_note
         (Diag.error (since lx start)
            (Printf.sprintf "Invalid integer literal '%s'" text)
            "Only digits and '_' are allowed")
         "Hexadecimal, binary and float literals are not supported yet");
    push lx (Int 0) start_pos start
  end
  else if !too_big then begin
    Report.report
      (Diag.with_note
         (Diag.error (since lx start)
            (Printf.sprintf "Integer literal %s does not fit in i32" text)
            "Too large")
         i32_range_note);
    push lx (Int 0) start_pos start
  end
  else push lx (Int !value) start_pos start

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

(* A character the language does not use: reported and skipped. Its span
   covers the whole character, continuation bytes included, so one non-ASCII
   character gives one error. *)
let unexpected_char lx start c prev =
  advance lx;
  while (not (at_end lx)) && is_continuation (peek_at lx 0) do
    advance lx
  done;
  let span = since lx start in
  let code = Char.code c in
  let d =
    if code >= 33 && code <= 126 then
      Diag.error span (Printf.sprintf "Unexpected character '%c'" c) ""
    else
      Diag.with_note
        (Diag.error span (Printf.sprintf "Unexpected byte 0x%02X" code) "")
        "Only comments can contain characters outside ASCII"
  in
  let d =
    if c = '&' then Diag.with_help d "Use '&&' for logical and" []
    else if c = '|' then Diag.with_help d "Use '||' for logical or" []
    else if c = '.' && is_digit prev then
      Diag.with_note d "Float literals are not supported yet"
    else d
  in
  Report.report d

let lex_punct lx =
  let start_pos = lx.pos in
  let start = here lx in
  let c = peek_at lx 0 in
  match two_char_kind c (peek_at lx 1) with
  | Some kind ->
      advance lx;
      advance lx;
      push lx kind start_pos start
  | None -> (
      match one_char_kind c with
      | Some kind ->
          advance lx;
          push lx kind start_pos start
      | None ->
          let prev = if lx.pos > 0 then lx.src.[lx.pos - 1] else ' ' in
          unexpected_char lx start c prev)

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
