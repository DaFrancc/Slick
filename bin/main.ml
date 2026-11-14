(* Command-line parsing. The work itself is in Slick.Driver. *)

type options = {
  cmd : string;
  mutable input : string option;
  mutable output : string option;
  mutable emit_c : bool;
}

let build_only opts flag =
  if opts.cmd <> "build" then
    Slick.Driver.arg_error
      (Printf.sprintf "'%s' only works with 'slick build'" flag)

let rec parse_options opts args =
  match args with
  | [] -> ()
  | "-o" :: rest -> (
      build_only opts "-o";
      match rest with
      | [] -> Slick.Driver.arg_error "'-o' needs a file name"
      | out :: rest ->
          opts.output <- Some out;
          parse_options opts rest)
  | "--emit-c" :: rest ->
      build_only opts "--emit-c";
      opts.emit_c <- true;
      parse_options opts rest
  | arg :: rest ->
      if String.length arg > 1 && arg.[0] = '-' then
        Slick.Driver.arg_error (Printf.sprintf "unknown option '%s'" arg);
      (match opts.input with
      | None -> opts.input <- Some arg
      | Some _ ->
          Slick.Driver.arg_error (Printf.sprintf "unexpected argument '%s'" arg));
      parse_options opts rest

let () =
  match List.tl (Array.to_list Sys.argv) with
  | [] -> Slick.Driver.usage_error ""
  | cmd :: rest -> (
      if cmd <> "build" && cmd <> "run" then
        Slick.Driver.usage_error (Printf.sprintf "unknown command '%s'" cmd);
      let opts = { cmd; input = None; output = None; emit_c = false } in
      parse_options opts rest;
      match opts.input with
      | None -> Slick.Driver.usage_error "missing input file"
      | Some path ->
          if cmd = "build" then Slick.Driver.build path opts.output opts.emit_c
          else Slick.Driver.run path)
