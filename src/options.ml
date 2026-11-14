(* Command-line settings that the phases read. bin/main.ml sets them before
   anything runs. *)

type t = {
  mutable warn_implicit : bool; (* --warn-implicit-conversions *)
  mutable warnings_as_errors : bool; (* --warnings-as-errors *)
}

let v = { warn_implicit = false; warnings_as_errors = false }
