(* Source spans and error reporting. *)

(* A range of source text. Lines and columns are 1-based and count
   characters, not bytes. The end is exclusive; a span whose end equals its
   start is a point between two characters. *)
type span = {
  file : string;
  start_line : int;
  start_col : int;
  end_line : int;
  end_col : int;
}

(* From the start of [first] to the end of [last]. *)
let join first last =
  { first with end_line = last.end_line; end_col = last.end_col }

(* The point just after [s]. *)
let point_after s = { s with start_line = s.end_line; start_col = s.end_col }

(* The point just before [s]. *)
let point_before s = { s with end_line = s.start_line; end_col = s.start_col }

(* ---- Diagnostics ---- *)

type severity = Error | Warning | Panic

(* An underlined span with a short text. Each diagnostic with a span has
   exactly one primary label; the others point at related code. A label with
   [l_insert] marks a point where that text is missing: it is shown in the
   source line, in green, with '+' under it. *)
type label = {
  l_span : span;
  l_text : string;
  l_primary : bool;
  l_insert : string;
}

(* Replaces the text in [e_span] with [e_text]. A point span inserts; empty
   text deletes. *)
type edit = { e_span : span; e_text : string }

(* A suggestion, optionally with the edits that carry it out. *)
type help = { h_text : string; h_edits : edit list }

type diagnostic = {
  severity : severity;
  message : string;
  file : string; (* for diagnostics with no span *)
  labels : label list;
  notes : string list;
  helps : help list;
}

(* An error at [span], whose primary label says [text] (which may be ""). *)
let error (span : span) message text =
  {
    severity = Error;
    message;
    file = span.file;
    labels =
      [ { l_span = span; l_text = text; l_primary = true; l_insert = "" } ];
    notes = [];
    helps = [];
  }

(* An error about a whole file. *)
let file_error file message =
  { severity = Error; message; file; labels = []; notes = []; helps = [] }

let with_label d span text =
  {
    d with
    labels =
      d.labels
      @ [ { l_span = span; l_text = text; l_primary = false; l_insert = "" } ];
  }

let set_insert text (l : label) =
  if l.l_primary then { l with l_insert = text } else l

(* Shows [text] as missing at the primary label, which should be a point. *)
let with_insert d text = { d with labels = List.map (set_insert text) d.labels }
let with_note d text = { d with notes = d.notes @ [ text ] }

let with_help d text edits =
  { d with helps = d.helps @ [ { h_text = text; h_edits = edits } ] }

let edit span text = { e_span = span; e_text = text }
