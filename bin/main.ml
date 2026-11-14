(* Command-line parsing. The work itself is in Slick.Driver. *)

open Slick

type options = {
  cmd : string;
  mutable input : string option;
  mutable output : string option;
  mutable emit_c : bool;
}

let starts_with s prefix =
  String.length s >= String.length prefix
  && String.sub s 0 (String.length prefix) = prefix

let color_value arg =
  if starts_with arg "--color=" then String.sub arg 8 (String.length arg - 8)
  else ""

let color_of_value value =
  match value with
  | "auto" -> Some Driver.Auto
  | "always" -> Some Driver.Always
  | "never" -> Some Driver.Never
  | _ -> None

(* A valid --color is applied before anything else, so that errors about
   earlier arguments follow it. An invalid one is reported in order. *)
let rec prescan_color args =
  match args with
  | [] -> ()
  | arg :: rest -> (
      match color_of_value (color_value arg) with
      | Some c when starts_with arg "--color=" ->
          Driver.settings.color <- c;
          prescan_color rest
      | _ -> prescan_color rest)

let check_color arg =
  let value = color_value arg in
  if color_of_value value = None then
    Driver.arg_error
      (Printf.sprintf
         "Invalid value '%s' for '--color': use 'auto', 'always' or 'never'"
         value)

let build_only opts flag =
  if opts.cmd <> "build" then
    Driver.arg_error (Printf.sprintf "'%s' only works with 'slick build'" flag)

let rec parse_options opts args =
  match args with
  | [] -> ()
  | "-o" :: rest -> (
      build_only opts "-o";
      match rest with
      | [] -> Driver.arg_error "'-o' needs a file name"
      | out :: rest ->
          opts.output <- Some out;
          parse_options opts rest)
  | "--emit-c" :: rest ->
      build_only opts "--emit-c";
      opts.emit_c <- true;
      parse_options opts rest
  | arg :: rest when arg = "--color" || starts_with arg "--color=" ->
      check_color arg;
      parse_options opts rest
  | arg :: rest ->
      if String.length arg > 1 && arg.[0] = '-' then
        Driver.arg_error (Printf.sprintf "Unknown option '%s'" arg);
      (match opts.input with
      | None -> opts.input <- Some arg
      | Some _ ->
          Driver.arg_error (Printf.sprintf "Unexpected argument '%s'" arg));
      parse_options opts rest

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  prescan_color args;
  match args with
  | [] -> Driver.usage_error ""
  | cmd :: rest -> (
      if cmd <> "build" && cmd <> "run" then
        Driver.usage_error (Printf.sprintf "Unknown command '%s'" cmd);
      let opts = { cmd; input = None; output = None; emit_c = false } in
      parse_options opts rest;
      match opts.input with
      | None -> Driver.usage_error "Missing input file"
      | Some path ->
          if cmd = "build" then Driver.build path opts.output opts.emit_c
          else Driver.run path)
