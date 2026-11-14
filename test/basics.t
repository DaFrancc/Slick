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
  Error: Expected ';' at the end of this statement
   --> semi.slick:2:13
    |
  2 |     print(1);
    |             + Expected ';'
  
  Error: Could not compile 'semi.slick' due to 1 error
  [1]

The last statement before '}' needs its ';' too.

  $ cat > semi_brace.slick <<'EOF'
  > main :: fn() { print(1) }
  > EOF
  $ slick run semi_brace.slick
  Error: Expected ';' at the end of this statement
   --> semi_brace.slick:1:24
    |
  1 | main :: fn() { print(1); }
    |                        + Expected ';'
  
  Error: Could not compile 'semi_brace.slick' due to 1 error
  [1]

A ';' with no statement is an error, in a block and after a function body.

  $ cat > lone.slick <<'EOF'
  > main :: fn() {
  >     print(1);
  >     ;
  > }
  > EOF
  $ slick run lone.slick
  Error: Unexpected ';'
   --> lone.slick:3:5
    |
  3 |     ;
    |     ^ Not needed here
    |
  Help: Remove it
    |
  3 |     ;
    |     -
  
  Error: Could not compile 'lone.slick' due to 1 error
  [1]

  $ cat > after_fn.slick <<'EOF'
  > main :: fn() {
  >     print(1);
  > };
  > EOF
  $ slick run after_fn.slick
  Error: Unexpected ';'
   --> after_fn.slick:3:2
    |
  3 | };
    |  ^ Not needed here
    |
  Note: A function definition ends at its '}'
  Help: Remove it
    |
  3 | };
    |  -
  
  Error: Could not compile 'after_fn.slick' due to 1 error
  [1]

There must be a main, and it takes nothing and returns nothing.

  $ cat > nomain.slick <<'EOF'
  > helper :: fn() { print(1); }
  > EOF
  $ slick run nomain.slick
  Error: No 'main' function found
   --> nomain.slick
  Help: Add one, like 'main :: fn() { }'
  
  Error: Could not compile 'nomain.slick' due to 1 error
  [1]

  $ cat > main_param.slick <<'EOF'
  > main :: fn(n: i32) { print(n); }
  > EOF
  $ slick run main_param.slick
  Error: 'main' must take no parameters and return nothing
   --> main_param.slick:1:11
    |
  1 | main :: fn(n: i32) { print(n); }
    |           ^^^^^^^^
    |
  Help: Write it as 'main :: fn() { ... }'
  
  Error: Could not compile 'main_param.slick' due to 1 error
  [1]

  $ cat > main_ret.slick <<'EOF'
  > main :: fn() -> i32 { return 0; }
  > EOF
  $ slick run main_ret.slick
  Error: 'main' must take no parameters and return nothing
   --> main_ret.slick:1:17
    |
  1 | main :: fn() -> i32 { return 0; }
    |                 ^^^
    |
  Help: Write it as 'main :: fn() { ... }'
  
  Error: Could not compile 'main_ret.slick' due to 1 error
  [1]

Functions cannot be defined twice, and print cannot be redefined.

  $ cat > dup.slick <<'EOF'
  > f :: fn() { print(1); }
  > f :: fn() { print(2); }
  > main :: fn() { f(); }
  > EOF
  $ slick run dup.slick
  Error: Function 'f' is already defined
   --> dup.slick:2:1
    |
  1 | f :: fn() { print(1); }
    | - First defined here
  2 | f :: fn() { print(2); }
    | ^ Defined again here
  
  Error: Could not compile 'dup.slick' due to 1 error
  [1]

  $ cat > redef_print.slick <<'EOF'
  > print :: fn() { }
  > main :: fn() { }
  > EOF
  $ slick run redef_print.slick
  Error: 'print' is a built-in function and cannot be redeclared
   --> redef_print.slick:1:1
    |
  1 | print :: fn() { }
    | ^^^^^
    |
  Help: Choose a different name
  
  Error: Could not compile 'redef_print.slick' due to 1 error
  [1]

Unknown functions.

  $ cat > unknown_fn.slick <<'EOF'
  > main :: fn() {
  >     prnt(1);
  > }
  > EOF
  $ slick run unknown_fn.slick
  Error: Unknown function 'prnt'
   --> unknown_fn.slick:2:5
    |
  2 |     prnt(1);
    |     ^^^^ Not defined
    |
  Help: Did you mean 'print'?
    |
  2 |     print(1);
    |     ~~~~~
  
  Error: Could not compile 'unknown_fn.slick' due to 1 error
  [1]

A character the language does not use, with its line and column.

  $ cat > at.slick <<'EOF'
  > main :: fn() {
  >     print(1) @ 2;
  > }
  > EOF
  $ slick run at.slick
  Error: Unexpected character '@'
   --> at.slick:2:14
    |
  2 |     print(1) @ 2;
    |              ^
  
  Error: Could not compile 'at.slick' due to 1 error
  [1]

Keywords from later milestones are reserved now.

  $ cat > reserved.slick <<'EOF'
  > main :: fn() {
  >     for(1);
  > }
  > EOF
  $ slick run reserved.slick
  Error: 'for' is not supported yet
   --> reserved.slick:2:5
    |
  2 |     for(1);
    |     ^^^ Reserved for a later version of Slick
  
  Error: Could not compile 'reserved.slick' due to 1 error
  [1]

Only function and struct definitions are allowed at the top level for now.

  $ cat > toplevel.slick <<'EOF'
  > x := 5;
  > main :: fn() { }
  > EOF
  $ slick run toplevel.slick
  Error: Expected '::', found ':='
   --> toplevel.slick:1:3
    |
  1 | x := 5;
    |   ^^ Expected '::'
    |
  Note: Only functions and structs can be defined at the top level for now
  
  Error: Could not compile 'toplevel.slick' due to 1 error
  [1]

  $ cat > toplevel_const.slick <<'EOF'
  > MAX :: 1024;
  > main :: fn() { }
  > EOF
  $ slick run toplevel_const.slick
  Error: Expected 'fn' or 'struct', found '1024'
   --> toplevel_const.slick:1:8
    |
  1 | MAX :: 1024;
    |        ^^^^ Expected 'fn' or 'struct'
    |
  Note: Only functions and structs can be defined at the top level for now
  
  Error: Could not compile 'toplevel_const.slick' due to 1 error
  [1]

A byte outside printable ASCII is reported by its value.

  $ printf 'main :: fn() {\n    print(1);\n}\n\303\251\n' > byte.slick
  $ slick run byte.slick
  Error: Unexpected byte 0xC3
   --> byte.slick:4:1
    |
  4 | é
    | ^
    |
  Note: Only comments can contain characters outside ASCII
  
  Error: Could not compile 'byte.slick' due to 1 error
  [1]

Other parser errors use the form 'expected X, found Y'.

  $ cat > top_number.slick <<'EOF'
  > 5
  > EOF
  $ slick run top_number.slick
  Error: Expected a function or struct definition, found '5'
   --> top_number.slick:1:1
    |
  1 | 5
    | ^ Expected a function or struct definition
    |
  Note: Only functions and structs can be defined at the top level for now
  
  Error: Could not compile 'top_number.slick' due to 1 error
  [1]

  $ cat > no_paren.slick <<'EOF'
  > f :: fn { }
  > EOF
  $ slick run no_paren.slick
  Error: Expected '(', found '{'
   --> no_paren.slick:1:9
    |
  1 | f :: fn { }
    |         ^ Expected '('
  
  Error: Could not compile 'no_paren.slick' due to 1 error
  [1]

  $ cat > param_name.slick <<'EOF'
  > f :: fn(1) { }
  > EOF
  $ slick run param_name.slick
  Error: Expected a parameter name, found '1'
   --> param_name.slick:1:9
    |
  1 | f :: fn(1) { }
    |         ^ Expected a parameter name
  
  Error: Could not compile 'param_name.slick' due to 1 error
  [1]

  $ cat > param_colon.slick <<'EOF'
  > f :: fn(a i32) { }
  > EOF
  $ slick run param_colon.slick
  Error: Expected ':', found 'i32'
   --> param_colon.slick:1:11
    |
  1 | f :: fn(a i32) { }
    |           ^^^ Expected ':'
  
  Error: Could not compile 'param_colon.slick' due to 1 error
  [1]

  $ cat > no_ret_type.slick <<'EOF'
  > f :: fn() -> { }
  > EOF
  $ slick run no_ret_type.slick
  Error: Expected a type, found '{'
   --> no_ret_type.slick:1:14
    |
  1 | f :: fn() -> { }
    |              ^ Expected a type
  
  Error: Could not compile 'no_ret_type.slick' due to 1 error
  [1]

An unterminated function body.

  $ cat > eof.slick <<'EOF'
  > main :: fn() {
  >     print(1);
  > EOF
  $ slick run eof.slick
  Error: Expected '}', found end of file
   --> eof.slick:3:1
    |
  1 | main :: fn() {
    |              - This '{' is not closed
  2 |     print(1);
  3 |
    | ^ Expected '}'
  
  Error: Could not compile 'eof.slick' due to 1 error
  [1]

