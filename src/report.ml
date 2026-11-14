(* Collects diagnostics and prints them, followed by a summary line. *)

type state = {
  mutable diags : Diag.diagnostic list; (* in reverse order *)
  mutable errors : int;
  mutable warnings : int;
  mutable path : string;
  mutable lines : string array; (* the source, for excerpts *)
  mutable color : bool;
}

let st =
  {
    diags = [];
    errors = 0;
    warnings = 0;
    path = "";
    lines = [||];
    color = false;
  }

let strip_cr line =
  let n = String.length line in
  if n > 0 && line.[n - 1] = '\r' then String.sub line 0 (n - 1) else line

let split_lines src =
  Array.of_list (List.map strip_cr (String.split_on_char '\n' src))

(* Called once, before any phase runs. *)
let setup path src color =
  st.path <- path;
  st.lines <- split_lines src;
  st.color <- color

(* With --warnings-as-errors, a warning is reported as an error, with a note
   saying why. *)
let report (d : Diag.diagnostic) =
  let d =
    if d.severity = Diag.Warning && Options.v.warnings_as_errors then
      Diag.with_note
        { d with severity = Diag.Error }
        "Reported as an error because of --warnings-as-errors"
    else d
  in
  st.diags <- d :: st.diags;
  match d.severity with
  | Diag.Error -> st.errors <- st.errors + 1
  | Diag.Warning -> st.warnings <- st.warnings + 1
  | Diag.Panic -> ()

let error_count () = st.errors

(* The source text of a span on one line, for suggestions that quote code.
   None for a span across lines. *)
let span_text (s : Diag.span) =
  if s.start_line <> s.end_line || s.start_line > Array.length st.lines then
    None
  else Some (Render.slice st.lines.(s.start_line - 1) s.start_col s.end_col)

let render_one d = Render.render st.lines st.color d

(* Without color, for messages the compiled program prints, like panics. *)
let render_plain d = Render.render st.lines false d

(* Where a diagnostic sorts: its primary label, or after everything else if
   it has none. *)
let position (d : Diag.diagnostic) =
  match d.labels with
  | [] -> (max_int, 0)
  | _ ->
      let rec primary (labels : Diag.label list) =
        match labels with
        | l :: rest -> if l.l_primary then l.l_span else primary rest
        | [] -> (List.hd d.labels).l_span
      in
      let s = primary d.labels in
      (s.start_line, s.start_col)

let compare_position a b = compare (position a) (position b)

(* Prints every diagnostic in source order, a blank line between each, then
   the summary. *)
let print_all () =
  let sorted = List.stable_sort compare_position (List.rev st.diags) in
  let rendered = List.map render_one sorted in
  prerr_string (String.concat "\n" rendered);
  if st.diags <> [] then
    prerr_string ("\n" ^ Render.summary st.color st.path st.errors st.warnings);
  (* Warnings come before anything the compiled program prints. *)
  flush stderr;
  st.diags <- []

(* Between phases: if anything went wrong, print it all and stop. *)
let stop_if_errors () =
  if st.errors > 0 then begin
    print_all ();
    exit 1
  end

(* After the last phase that reports: print any warnings, and go on. *)
let print_warnings () = if st.diags <> [] then print_all ()
