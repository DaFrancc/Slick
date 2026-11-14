(* Source locations and fatal error reporting. The compiler stops at the first
   error: [fatal] prints it and exits with code 1. *)

type loc = { file : string; line : int; col : int }

let fatal loc msg =
  Printf.eprintf "%s:%d:%d: error: %s\n" loc.file loc.line loc.col msg;
  exit 1

(* For errors that belong to the whole file rather than a position in it. *)
let fatal_file file msg =
  Printf.eprintf "%s: error: %s\n" file msg;
  exit 1
