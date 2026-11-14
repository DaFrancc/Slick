Stage 1: the walking skeleton. Every program's C is also compiled with strict
warnings.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

print(42) prints 42.

  $ cat > print.slick <<'EOF'
  > main :: fn() { print(42); }
  > EOF
  $ slick run print.slick
  42

Statements run in order, whether they are on separate lines or one line.

  $ cat > lines.slick <<'EOF'
  > main :: fn() {
  >     print(1);
  >     print(2);
  >     print(3);
  > }
  > EOF
  $ slick run lines.slick
  1
  2
  3

  $ cat > oneline.slick <<'EOF'
  > main :: fn() { print(1); print(2); print(3); }
  > EOF
  $ slick run oneline.slick
  1
  2
  3

A newline is only whitespace, even inside a call.

  $ cat > split.slick <<'EOF'
  > main :: fn() {
  >     print(
  >         7
  >     );
  > }
  > EOF
  $ slick run split.slick
  7

Comments: whole lines, trailing, commented-out code, and a comment on the last
line with no newline after it.

  $ printf 'main :: fn() {\n    // a comment line\n    print(1); // trailing\n    // print(2);\n}\n// last line' > comments.slick
  $ slick run comments.slick
  1

User functions with no parameters can be called, before or after their
definition.

  $ cat > calls.slick <<'EOF'
  > first :: fn() { print(1); }
  > main :: fn() {
  >     first();
  >     second();
  > }
  > second :: fn() { print(2); }
  > EOF
  $ slick run calls.slick
  1
  2

A missing ';' is reported where the statement ended, not on the next line.

  $ cat > semi.slick <<'EOF'
  > main :: fn() {
  >     print(1)
  >     print(2);
  > }
  > EOF
  $ slick run semi.slick
  semi.slick:2:13: error: expected ';' at the end of this statement
  [1]

The last statement before '}' needs its ';' too.

  $ cat > semi_brace.slick <<'EOF'
  > main :: fn() { print(1) }
  > EOF
  $ slick run semi_brace.slick
  semi_brace.slick:1:24: error: expected ';' at the end of this statement
  [1]

A ';' with no statement is an error, in a block and after a function body.

  $ cat > lone.slick <<'EOF'
  > main :: fn() {
  >     print(1);
  >     ;
  > }
  > EOF
  $ slick run lone.slick
  lone.slick:3:5: error: unexpected ';'
  [1]

  $ cat > after_fn.slick <<'EOF'
  > main :: fn() {
  >     print(1);
  > };
  > EOF
  $ slick run after_fn.slick
  after_fn.slick:3:2: error: unexpected ';'
  [1]

There must be a main, and it takes nothing and returns nothing.

  $ cat > nomain.slick <<'EOF'
  > helper :: fn() { print(1); }
  > EOF
  $ slick run nomain.slick
  nomain.slick: error: no 'main' function found
  [1]

  $ cat > main_param.slick <<'EOF'
  > main :: fn(n: i32) { print(n); }
  > EOF
  $ slick run main_param.slick
  main_param.slick:1:1: error: 'main' must take no parameters and return nothing
  [1]

  $ cat > main_ret.slick <<'EOF'
  > main :: fn() -> i32 { return 0; }
  > EOF
  $ slick run main_ret.slick
  main_ret.slick:1:1: error: 'main' must take no parameters and return nothing
  [1]

Functions cannot be defined twice, and print cannot be redefined.

  $ cat > dup.slick <<'EOF'
  > f :: fn() { print(1); }
  > f :: fn() { print(2); }
  > main :: fn() { f(); }
  > EOF
  $ slick run dup.slick
  dup.slick:2:1: error: function 'f' is already defined on line 1
  [1]

  $ cat > redef_print.slick <<'EOF'
  > print :: fn() { }
  > main :: fn() { }
  > EOF
  $ slick run redef_print.slick
  redef_print.slick:1:1: error: 'print' is a built-in function and cannot be redeclared
  [1]

Unknown functions.

  $ cat > unknown_fn.slick <<'EOF'
  > main :: fn() {
  >     prnt(1);
  > }
  > EOF
  $ slick run unknown_fn.slick
  unknown_fn.slick:2:5: error: unknown function 'prnt'
  [1]

A character the language does not use, with its line and column.

  $ cat > at.slick <<'EOF'
  > main :: fn() {
  >     print(1) @ 2;
  > }
  > EOF
  $ slick run at.slick
  at.slick:2:14: error: unexpected character '@'
  [1]

Keywords from later milestones are reserved now.

  $ cat > reserved.slick <<'EOF'
  > main :: fn() {
  >     for(1);
  > }
  > EOF
  $ slick run reserved.slick
  reserved.slick:2:5: error: 'for' is not supported yet
  [1]

Only function definitions are allowed at the top level for now.

  $ cat > toplevel.slick <<'EOF'
  > x := 5;
  > main :: fn() { }
  > EOF
  $ slick run toplevel.slick
  toplevel.slick:1:3: error: expected '::', found ':='
  [1]

  $ cat > toplevel_const.slick <<'EOF'
  > MAX :: 1024;
  > main :: fn() { }
  > EOF
  $ slick run toplevel_const.slick
  toplevel_const.slick:1:8: error: expected 'fn', found '1024'
  [1]

A byte outside printable ASCII is reported by its value.

  $ printf 'main :: fn() {\n    print(1);\n}\n\303\251\n' > byte.slick
  $ slick run byte.slick
  byte.slick:4:1: error: unexpected byte 0xC3
  [1]

Other parser errors use the form 'expected X, found Y'.

  $ cat > top_number.slick <<'EOF'
  > 5
  > EOF
  $ slick run top_number.slick
  top_number.slick:1:1: error: expected a function definition, found '5'
  [1]

  $ cat > no_paren.slick <<'EOF'
  > f :: fn { }
  > EOF
  $ slick run no_paren.slick
  no_paren.slick:1:9: error: expected '(', found '{'
  [1]

  $ cat > param_name.slick <<'EOF'
  > f :: fn(1) { }
  > EOF
  $ slick run param_name.slick
  param_name.slick:1:9: error: expected a parameter name, found '1'
  [1]

  $ cat > param_colon.slick <<'EOF'
  > f :: fn(a i32) { }
  > EOF
  $ slick run param_colon.slick
  param_colon.slick:1:11: error: expected ':', found 'i32'
  [1]

  $ cat > no_ret_type.slick <<'EOF'
  > f :: fn() -> { }
  > EOF
  $ slick run no_ret_type.slick
  no_ret_type.slick:1:14: error: expected a type, found '{'
  [1]

An unterminated function body.

  $ cat > eof.slick <<'EOF'
  > main :: fn() {
  >     print(1);
  > EOF
  $ slick run eof.slick
  eof.slick:3:1: error: expected '}', found end of file
  [1]
