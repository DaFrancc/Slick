(* Runs the phases and the C compiler. Command-line parsing is in bin/main.ml. *)

let usage =
  "usage: slick build FILE [-o OUT] [--emit-c]\n       slick run FILE\n"

(* A usage error that also prints the usage text. *)
let usage_error msg =
  if msg <> "" then Printf.eprintf "slick: %s\n" msg;
  prerr_string usage;
  exit 2

(* A usage error that is clear without the usage text. *)
let arg_error msg =
  Printf.eprintf "slick: %s\n" msg;
  exit 2

let check_input path =
  if not (Filename.check_suffix path ".slick") then
    arg_error (Printf.sprintf "'%s' is not a .slick file" path);
  if (not (Sys.file_exists path)) || Sys.is_directory path then
    arg_error (Printf.sprintf "cannot find '%s'" path)

let compile_to_c path =
  let src = In_channel.with_open_bin path In_channel.input_all in
  let toks = Lexer.tokenize path src in
  let file = Parser.parse_file path toks in
  Check.check_file file;
  Emit_c.emit_file file

let env_or name default =
  match Sys.getenv_opt name with Some v when v <> "" -> v | _ -> default

(* Compiles C source to an executable at [out]. A C compiler failure is a bug
   in slick, so the C file is kept for inspection. *)
(* Integer overflow wraps in Slick, so -fwrapv makes C agree, and the
   compile-time overflow warnings are turned off: -Wno-overflow for gcc,
   -Wno-integer-overflow for clang. Each compiler ignores the other's flag. *)
let base_cflags = "-std=c11 -fwrapv -Wno-overflow -Wno-integer-overflow"

let write_file path contents =
  let oc = open_out_bin path in
  output_string oc contents;
  close_out oc

let compile_c c_src out =
  let c_path = Filename.temp_file "slick" ".c" in
  write_file c_path c_src;
  let cc = env_or "CC" "cc" in
  let flags = env_or "SLICK_CFLAGS" "" in
  let cmd =
    Printf.sprintf "%s %s %s -o %s %s" cc base_cflags flags (Filename.quote out)
      (Filename.quote c_path)
  in
  if Sys.command cmd <> 0 then begin
    Printf.eprintf
      "slick: internal error: the C compiler rejected the generated code; it \
       was kept at %s\n"
      c_path;
    exit 3
  end;
  Sys.remove c_path

let build path output emit_c =
  check_input path;
  let c_src = compile_to_c path in
  if emit_c then print_string c_src
  else
    let out =
      match output with
      | Some out -> out
      | None -> Filename.remove_extension (Filename.basename path)
    in
    compile_c c_src out

let run path =
  check_input path;
  let c_src = compile_to_c path in
  let exe = Filename.temp_file "slick" ".exe" in
  compile_c c_src exe;
  flush stdout;
  let code = Sys.command (Filename.quote exe) in
  Sys.remove exe;
  exit code
