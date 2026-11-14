type kind =
  | Ident of string
  (* The magnitude, read as unsigned: up to 18446744073709551615. A '-' in
     front is a separate token; the parser folds it in. *)
  | Int of Int64.t
  | Float of string (* the source text without '_' *)
  (* keywords *)
  | Fn
  | Mut
  | If
  | Else
  | While
  | Return
  | True
  | False
  | Struct
  (* punctuation *)
  | LParen
  | RParen
  | LBrace
  | RBrace
  | Comma
  | Semi
  | Colon
  | ColonColon
  | ColonEq
  | Arrow
  | Dot
  (* operators *)
  | Plus
  | Minus
  | Star
  | Slash
  | Percent
  | Amp
  | Pipe
  | Caret
  | Tilde
  | Shl
  | Shr
  | Assign
  | PlusAssign
  | MinusAssign
  | StarAssign
  | SlashAssign
  | PercentAssign
  | AmpAssign
  | PipeAssign
  | CaretAssign
  | ShlAssign
  | ShrAssign
  | EqEq
  | NotEq
  | Lt
  | Le
  | Gt
  | Ge
  | AndAnd
  | OrOr
  | Bang
  | Eof

type t = {
  kind : kind;
  text : string; (* the source text, for messages *)
  span : Diag.span;
}

(* How a token is named in "expected X, found Y" messages. *)
let describe tok =
  match tok.kind with Eof -> "end of file" | _ -> "'" ^ tok.text ^ "'"
