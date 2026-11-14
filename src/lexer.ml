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
    "enum";
    "defer";
    "errdefer";
    "try";
    "import";
    "as";
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
  | "struct" -> Some Struct
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

let digit_value c =
  if c >= '0' && c <= '9' then Char.code c - Char.code '0'
  else if c >= 'a' && c <= 'f' then Char.code c - Char.code 'a' + 10
  else if c >= 'A' && c <= 'F' then Char.code c - Char.code 'A' + 10
  else 99

let skip_while lx pred =
  while (not (at_end lx)) && pred (peek_at lx 0) do
    advance lx
  done

let is_digit_or_sep c = is_digit c || c = '_'
let without_underscores text = String.concat "" (String.split_on_char '_' text)

let base_name base =
  match base with
  | 16 -> "Only hexadecimal digits and '_' are allowed"
  | 2 -> "Only 0, 1 and '_' are allowed"
  | _ -> "Only digits and '_' are allowed"

let invalid_literal lx start text what label =
  Report.report
    (Diag.error (since lx start)
       (Printf.sprintf "Invalid %s literal '%s'" what text)
       label)

(* The digits of [text] from [from] on, in [base], as an unsigned 64-bit
   value. The value is checked before each step, so it never overflows;
   [None] means the literal is larger than any integer type. *)
let int_value text from base =
  let value = ref 0L in
  let too_big = ref false in
  let b = Int64.of_int base in
  for i = from to String.length text - 1 do
    let c = text.[i] in
    if c <> '_' && not !too_big then begin
      let d = Int64.of_int (digit_value c) in
      let limit = Int64.unsigned_div (Int64.sub (-1L) d) b in
      if Int64.unsigned_compare !value limit > 0 then too_big := true
      else value := Int64.add (Int64.mul !value b) d
    end
  done;
  if !too_big then None else Some !value

(* An integer literal [text] whose digits start at [from]. A bad literal is
   reported, then treated as 0. *)
let finish_int lx start_pos start text from base =
  let valid = ref (String.length text > from) in
  let has_digit = ref false in
  for i = from to String.length text - 1 do
    let c = text.[i] in
    if c = '_' then ()
    else if digit_value c < base then has_digit := true
    else valid := false
  done;
  if not (!valid && !has_digit) then begin
    invalid_literal lx start text "integer"
      (if !valid then "Expected digits after the prefix" else base_name base);
    push lx (Int 0L) start_pos start
  end
  else
    match int_value text from base with
    | Some v -> push lx (Int v) start_pos start
    | None ->
        Report.report
          (Diag.with_note
             (Diag.error (since lx start)
                (Printf.sprintf "Integer literal %s is too large" text)
                "Larger than any integer type")
             "The largest is u64, which holds up to 18446744073709551615");
        push lx (Int 0L) start_pos start

(* Decimal, '0x' hexadecimal or '0b' binary integers, and floats: digits, a
   '.' and digits, then an optional exponent, or digits and an exponent.
   Letters or digits glued to the end, as in '5x' or '1.5f', make the whole
   literal invalid. *)
let lex_number lx =
  let start_pos = lx.pos in
  let start = here lx in
  let c1 = peek_at lx 1 in
  if peek_at lx 0 = '0' && (c1 = 'x' || c1 = 'X' || c1 = 'b' || c1 = 'B') then begin
    advance lx;
    advance lx;
    skip_while lx is_ident_char;
    let text = String.sub lx.src start_pos (lx.pos - start_pos) in
    finish_int lx start_pos start text 2
      (if c1 = 'x' || c1 = 'X' then 16 else 2)
  end
  else begin
    skip_while lx is_digit_or_sep;
    let is_float = ref false in
    if peek_at lx 0 = '.' && is_digit (peek_at lx 1) then begin
      is_float := true;
      advance lx;
      skip_while lx is_digit_or_sep
    end;
    let e = peek_at lx 0 in
    let sign = peek_at lx 1 in
    if
      (e = 'e' || e = 'E')
      && (is_digit sign
         || ((sign = '+' || sign = '-') && is_digit (peek_at lx 2)))
    then begin
      is_float := true;
      advance lx;
      if sign = '+' || sign = '-' then advance lx;
      skip_while lx is_digit_or_sep
    end;
    let tail = lx.pos in
    skip_while lx is_ident_char;
    let text = String.sub lx.src start_pos (lx.pos - start_pos) in
    if !is_float then
      if lx.pos > tail then begin
        invalid_literal lx start text "float"
          "Only digits, '.', '_' and an exponent are allowed";
        push lx (Int 0L) start_pos start
      end
      else push lx (Float (without_underscores text)) start_pos start
    else finish_int lx start_pos start text 0 10
  end

(* Longer operators are matched before shorter ones. *)
let three_char_kind a b c =
  match (a, b, c) with
  | '<', '<', '=' -> Some ShlAssign
  | '>', '>', '=' -> Some ShrAssign
  | _ -> None

let two_char_kind a b =
  match (a, b) with
  | '<', '<' -> Some Shl
  | '>', '>' -> Some Shr
  | '&', '=' -> Some AmpAssign
  | '|', '=' -> Some PipeAssign
  | '^', '=' -> Some CaretAssign
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
  | '.' -> Some Dot
  | '&' -> Some Amp
  | '|' -> Some Pipe
  | '^' -> Some Caret
  | '~' -> Some Tilde
  | _ -> None

(* A character the language does not use: reported and skipped. Its span
   covers the whole character, continuation bytes included, so one non-ASCII
   character gives one error. *)
let unexpected_char lx start c =
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
  Report.report d

(* Consumes an [n]-character operator and pushes its token. *)
let take lx n kind =
  let start_pos = lx.pos in
  let start = here lx in
  for _ = 1 to n do
    advance lx
  done;
  push lx kind start_pos start

let lex_punct lx =
  let c = peek_at lx 0 in
  match three_char_kind c (peek_at lx 1) (peek_at lx 2) with
  | Some kind -> take lx 3 kind
  | None -> (
      match two_char_kind c (peek_at lx 1) with
      | Some kind -> take lx 2 kind
      | None -> (
          match one_char_kind c with
          | Some kind -> take lx 1 kind
          | None -> unexpected_char lx (here lx) c))

let rec lex_all lx =
  skip_trivia lx;
  if at_end lx then push lx Eof lx.pos (here lx)
  else begin
    let c = peek_at lx 0 in
    if is_ident_start c then lex_word lx
    else if is_digit c then lex_number lx
    else lex_punct lx;
    lex_all lx
  end

let tokenize file src =
  let lx = { src; file; pos = 0; line = 1; col = 1; toks = [] } in
  lex_all lx;
  Array.of_list (List.rev lx.toks)
