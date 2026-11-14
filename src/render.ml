(* Turns a diagnostic into text: a header, the location, the source lines it
   points at with labels underlined, then notes and helps.

     Error: Cannot assign to 'count': it was declared without 'mut'
      --> game.slick:3:5
       |
     2 |     count := 0;
       |     ----- Declared here without 'mut'
     3 |     count += 1;
       |     ^^^^^ Cannot assign
       |
     Help: Declare it with 'mut'
       |
     2 |     count : mut = 0;
       |           ~~~~~~~ *)

open Diag

(* ---- Color ---- *)

let reset = "\027[0m"
let bold = "\027[1m"
let bold_red = "\027[1;31m"
let bold_yellow = "\027[1;33m"
let bold_blue = "\027[1;34m"
let bold_green = "\027[1;32m"
let bold_cyan = "\027[1;36m"
let green = "\027[32m"
let red = "\027[31m"

let paint color style text =
  if color && text <> "" then style ^ text ^ reset else text

let severity_word sev =
  match sev with Error -> "Error" | Warning -> "Warning" | Panic -> "Panic"

let severity_style sev =
  match sev with Error | Panic -> bold_red | Warning -> bold_yellow

(* ---- Columns ----

   Spans count characters; the display expands each tab to four spaces. *)

let is_continuation c = Char.code c land 0xC0 = 0x80

(* The display width of the first [col - 1] characters of [line]. *)
let display_col line col =
  let width = ref 0 in
  let chars = ref 0 in
  let i = ref 0 in
  while !i < String.length line && !chars < col - 1 do
    let c = line.[!i] in
    if c = '\t' then begin
      width := !width + 4;
      incr chars
    end
    else if not (is_continuation c) then begin
      incr width;
      incr chars
    end;
    incr i
  done;
  !width

let display_width line = display_col line max_int

let expand_tabs line =
  let b = Buffer.create (String.length line) in
  for i = 0 to String.length line - 1 do
    if line.[i] = '\t' then Buffer.add_string b "    "
    else Buffer.add_char b line.[i]
  done;
  Buffer.contents b

(* The byte offset where character [col] (1-based) starts. Each step skips
   one character: its first byte and any continuation bytes. *)
let byte_of_col line col =
  let len = String.length line in
  let chars = ref 0 in
  let i = ref 0 in
  while !i < len && !chars < col - 1 do
    incr i;
    while !i < len && is_continuation line.[!i] do
      incr i
    done;
    incr chars
  done;
  !i

(* Characters [from_col] up to, but not including, [to_col]. *)
let slice line from_col to_col =
  let a = byte_of_col line from_col in
  let b = byte_of_col line to_col in
  if b > a then String.sub line a (b - a) else ""

(* ---- Layout ---- *)

type layout = {
  lines : string array; (* the source, one entry per line *)
  color : bool;
  width : int; (* of the line-number column *)
  out : Buffer.t;
}

let source_line lay n =
  if n >= 1 && n <= Array.length lay.lines then lay.lines.(n - 1) else ""

let emit lay s =
  Buffer.add_string lay.out s;
  Buffer.add_char lay.out '\n'

let pad lay = String.make lay.width ' '

(* '  |' *)
let gutter_blank lay = paint lay.color bold_blue (pad lay ^ " |")

(* ' 12 | text' *)
let gutter_line lay n text =
  let num = string_of_int n in
  let num = String.make (lay.width - String.length num) ' ' ^ num in
  let gutter = paint lay.color bold_blue (num ^ " |") in
  if text = "" then gutter else gutter ^ " " ^ text

let rec digits n = if n < 10 then 1 else 1 + digits (n / 10)

(* ---- Edited lines ----

   Used for helps, which show a line as it would be after their edits, and
   for labels that show missing text inside the source line. *)

let edit_line (e : edit) = e.e_span.start_line

let compare_edits (a : edit) (b : edit) =
  compare
    (a.e_span.start_line, a.e_span.start_col)
    (b.e_span.start_line, b.e_span.start_col)

let is_deletion (e : edit) = e.e_text = ""

(* One piece of an edited line: its text, and the marker that goes under it
   (' ' for unchanged text). *)
type piece = { text : string; mark : char }

let rec pieces_of_edits line pos (edits : edit list) acc =
  match edits with
  | [] -> List.rev ({ text = slice line pos max_int; mark = ' ' } :: acc)
  | e :: rest ->
      let before = { text = slice line pos e.e_span.start_col; mark = ' ' } in
      let is_insert =
        e.e_span.start_col = e.e_span.end_col
        && e.e_span.start_line = e.e_span.end_line
      in
      let inserted =
        { text = e.e_text; mark = (if is_insert then '+' else '~') }
      in
      pieces_of_edits line e.e_span.end_col rest (inserted :: before :: acc)

(* A deletion shows the original line with '-' under what goes. *)
let rec pieces_of_deletions line pos (edits : edit list) acc =
  match edits with
  | [] -> List.rev ({ text = slice line pos max_int; mark = ' ' } :: acc)
  | e :: rest ->
      let before = { text = slice line pos e.e_span.start_col; mark = ' ' } in
      let removed =
        { text = slice line e.e_span.start_col e.e_span.end_col; mark = '-' }
      in
      pieces_of_deletions line e.e_span.end_col rest (removed :: before :: acc)

let piece_style mark = if mark = '-' then red else green

(* The edited line as it is built: [raw] for measuring, [shown] with tabs
   expanded and color, and the marker row. *)
type edited = { raw : Buffer.t; shown : Buffer.t; marks : Buffer.t }

let add_piece lay ed pc =
  let start = display_width (Buffer.contents ed.raw) in
  Buffer.add_string ed.raw pc.text;
  let stop = display_width (Buffer.contents ed.raw) in
  let text = expand_tabs pc.text in
  if pc.mark = ' ' then begin
    Buffer.add_string ed.shown text;
    Buffer.add_string ed.marks (String.make (stop - start) ' ')
  end
  else begin
    Buffer.add_string ed.shown (paint lay.color (piece_style pc.mark) text);
    Buffer.add_string ed.marks
      (paint lay.color (piece_style pc.mark)
         (String.make (max 1 (stop - start)) pc.mark))
  end

(* Writes the edited line and the marker row under it. *)
let emit_pieces lay n pieces =
  let ed =
    {
      raw = Buffer.create 80;
      shown = Buffer.create 80;
      marks = Buffer.create 80;
    }
  in
  List.iter (add_piece lay ed) pieces;
  emit lay (gutter_line lay n (Buffer.contents ed.shown));
  let row = Buffer.contents ed.marks in
  (* Trailing spaces come from unchanged text after the last marker. *)
  let len = ref (String.length row) in
  while !len > 0 && row.[!len - 1] = ' ' do
    decr len
  done;
  emit lay (gutter_blank lay ^ " " ^ String.sub row 0 !len)

(* ---- Labels ---- *)

let label_line (l : label) = l.l_span.start_line

let compare_labels (a : label) (b : label) =
  compare
    (a.l_span.start_line, a.l_span.start_col)
    (b.l_span.start_line, b.l_span.start_col)

let is_insert (l : label) = l.l_insert <> ""
let insert_edit (l : label) = { e_span = l.l_span; e_text = l.l_insert }

let char_length s =
  let n = ref 0 in
  for i = 0 to String.length s - 1 do
    if not (is_continuation s.[i]) then incr n
  done;
  !n

(* How many characters the insertions add before column [col]. *)
let rec shift (inserts : edit list) col =
  match inserts with
  | [] -> 0
  | e :: rest ->
      (if e.e_span.start_col < col then char_length e.e_text else 0)
      + shift rest col

(* The row under a source line for one label. [line] is the line as shown,
   with any insertions in it; [inserts] are those insertions, which move the
   columns of everything after them. *)
let label_row lay sev line inserts (l : label) =
  let s = l.l_span in
  let start_col = s.start_col + shift inserts s.start_col in
  let start = display_col line start_col in
  let stop =
    if is_insert l then display_col line (start_col + char_length l.l_insert)
    else if s.end_line = s.start_line then
      display_col line (s.end_col + shift inserts s.end_col)
    else display_width line
  in
  let style = if l.l_primary then severity_style sev else bold_blue in
  let indent = gutter_blank lay ^ " " ^ String.make start ' ' in
  if is_insert l then
    let text = if l.l_text = "" then "" else " " ^ l.l_text in
    indent
    ^ paint lay.color green (String.make (max 1 (stop - start)) '+')
    ^ paint lay.color style text
  else
    let marks =
      String.make (max 1 (stop - start)) (if l.l_primary then '^' else '-')
    in
    let text = if l.l_text = "" then marks else marks ^ " " ^ l.l_text in
    indent ^ paint lay.color style text

let emit_source lay n =
  emit lay (gutter_line lay n (expand_tabs (source_line lay n)))

(* Shows line [n] with [inserts] in green, and returns it as shown, without
   color, for measuring. *)
let emit_with_inserts lay n inserts =
  let ed =
    {
      raw = Buffer.create 80;
      shown = Buffer.create 80;
      marks = Buffer.create 80;
    }
  in
  List.iter (add_piece lay ed)
    (pieces_of_edits (source_line lay n) 1 inserts []);
  emit lay (gutter_line lay n (Buffer.contents ed.shown));
  Buffer.contents ed.raw

(* The labels on line [n], which come first in the sorted list, and the
   rest. *)
let rec split_labels n (labels : label list) acc =
  match labels with
  | l :: rest when label_line l = n -> split_labels n rest (l :: acc)
  | _ -> (List.rev acc, labels)

let emit_label_row lay sev line inserts l =
  emit lay (label_row lay sev line inserts l)

(* Shows each labelled line once, in order, with a row per label under it.
   One unlabelled line between two shown lines is shown too; a longer gap is
   shown as '...'. *)
let rec emit_labelled_lines lay sev labels prev =
  match labels with
  | [] -> ()
  | (l : label) :: _ ->
      let n = label_line l in
      (match prev with
      | Some p when n - p = 2 -> emit_source lay (p + 1)
      | Some p when n - p > 2 -> emit lay (paint lay.color bold_blue "...")
      | _ -> ());
      let on_line, rest = split_labels n labels [] in
      let inserts = List.map insert_edit (List.filter is_insert on_line) in
      let shown =
        if inserts = [] then begin
          emit_source lay n;
          source_line lay n
        end
        else emit_with_inserts lay n inserts
      in
      List.iter (emit_label_row lay sev shown inserts) on_line;
      emit_labelled_lines lay sev rest (Some n)

(* ---- Helps ---- *)

(* The edits on line [n], which come first in the sorted list, and the rest. *)
let rec split_edits n (edits : edit list) acc =
  match edits with
  | e :: rest when edit_line e = n -> split_edits n rest (e :: acc)
  | _ -> (List.rev acc, edits)

let rec emit_edited_lines lay (edits : edit list) =
  match edits with
  | [] -> ()
  | e :: _ ->
      let n = edit_line e in
      let on_line, rest = split_edits n edits [] in
      let line = source_line lay n in
      let pieces =
        if List.for_all is_deletion on_line then
          pieces_of_deletions line 1 on_line []
        else pieces_of_edits line 1 on_line []
      in
      emit_pieces lay n pieces;
      emit_edited_lines lay rest

let emit_help lay (h : help) =
  emit lay (paint lay.color bold_cyan "Help" ^ ": " ^ h.h_text);
  if h.h_edits <> [] then begin
    emit lay (gutter_blank lay);
    emit_edited_lines lay (List.sort compare_edits h.h_edits)
  end

let emit_note lay text =
  emit lay (paint lay.color bold_green "Note" ^ ": " ^ text)

(* ---- Diagnostics ---- *)

let max_line acc n = if n > acc then n else acc
let help_edit_lines (h : help) = List.map edit_line h.h_edits
let is_primary (l : label) = l.l_primary

let render lines color (d : diagnostic) =
  let label_lines = List.map label_line d.labels in
  let edit_lines = List.concat_map help_edit_lines d.helps in
  let biggest = List.fold_left max_line 1 (label_lines @ edit_lines) in
  let lay = { lines; color; width = digits biggest; out = Buffer.create 512 } in
  emit lay
    (paint color (severity_style d.severity) (severity_word d.severity)
    ^ paint color bold (": " ^ d.message));
  let labels = List.sort compare_labels d.labels in
  (match List.filter is_primary labels with
  | primary :: _ ->
      let s = primary.l_span in
      emit lay
        (pad lay
        ^ paint color bold_blue "-->"
        ^ Printf.sprintf " %s:%d:%d" s.file s.start_line s.start_col);
      emit lay (gutter_blank lay);
      emit_labelled_lines lay d.severity labels None
  | [] -> emit lay (pad lay ^ paint color bold_blue "-->" ^ " " ^ d.file));
  if labels <> [] && (d.notes <> [] || d.helps <> []) then
    emit lay (gutter_blank lay);
  List.iter (emit_note lay) d.notes;
  List.iter (emit_help lay) d.helps;
  Buffer.contents lay.out

let summary color path errors =
  let count =
    if errors = 1 then "1 error" else string_of_int errors ^ " errors"
  in
  paint color bold_red "Error"
  ^ paint color bold
      (Printf.sprintf ": Could not compile '%s' due to %s" path count)
  ^ "\n"
