type kind =
  | Ident of string
  | Int of int (* at most 2147483648; the checker rejects that unless negated *)
  (* keywords *)
  | Fn
  | Mut
  | If
  | Else
  | While
  | Return
  | True
  | False
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
  (* operators *)
  | Plus
  | Minus
  | Star
  | Slash
  | Percent
  | Assign
  | PlusAssign
  | MinusAssign
  | StarAssign
  | SlashAssign
  | PercentAssign
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
