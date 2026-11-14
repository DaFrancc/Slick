Every error in a file is reported in one run, each once, without follow-on
errors caused by an earlier one.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

Three independent errors in different functions.

  $ cat > three.slick <<'EOF'
  > a :: fn() {
  >     x := 1;
  >     x = 2;
  > }
  > b :: fn() -> i32 {
  >     return true;
  > }
  > main :: fn() {
  >     print(undefined);
  > }
  > EOF
  $ slick run three.slick
  Error: Cannot assign to 'x': it was declared without 'mut'
   --> three.slick:3:5
    |
  2 |     x := 1;
    |     - Declared here without 'mut'
  3 |     x = 2;
    |     ^ Cannot assign
    |
  Help: Declare it with 'mut'
    |
  2 |     x : mut = 1;
    |       ~~~~~~~
  
  Error: 'b' returns i32, but this 'return' has a value of type bool
   --> three.slick:6:12
    |
  5 | b :: fn() -> i32 {
    |              --- Declared to return i32 here
  6 |     return true;
    |            ^^^^ This is bool
  
  Error: Undeclared name 'undefined'
   --> three.slick:9:11
    |
  9 |     print(undefined);
    |           ^^^^^^^^^ Not declared
  
  Error: Could not compile 'three.slick' due to 3 errors
  [1]

Two syntax errors in one function. A missing ';' at the end of a line does
not throw the parser off.

  $ cat > two_syntax.slick <<'EOF'
  > main :: fn() {
  >     print(1)
  >     x := (2 + ;
  >     print(3);
  > }
  > EOF
  $ slick run two_syntax.slick
  Error: Expected ';' at the end of this statement
   --> two_syntax.slick:2:13
    |
  2 |     print(1);
    |             + Expected ';'
  
  Error: Expected an expression, found ';'
   --> two_syntax.slick:3:15
    |
  3 |     x := (2 + ;
    |               ^ Expected an expression
  
  Error: Could not compile 'two_syntax.slick' due to 2 errors
  [1]

With a syntax error, the checker does not run, so the type error on line 2 is
not reported yet.

  $ cat > syntax_first.slick <<'EOF'
  > main :: fn() {
  >     x : i32 = true;
  >     print(1)
  > }
  > EOF
  $ slick run syntax_first.slick
  Error: Expected ';' at the end of this statement
   --> syntax_first.slick:3:13
    |
  3 |     print(1);
    |             + Expected ';'
  
  Error: Could not compile 'syntax_first.slick' due to 1 error
  [1]

An unknown type is reported once; uses of the name raise nothing more.

  $ cat > unknown_once.slick <<'EOF'
  > main :: fn() {
  >     x : Foo = 1;
  >     print(x + 1);
  > }
  > EOF
  $ slick run unknown_once.slick
  Error: Unknown type 'Foo'
   --> unknown_once.slick:2:9
    |
  2 |     x : Foo = 1;
    |         ^^^ Not a type
    |
  Note: The built-in types are i8, i16, i32, i64, u8, u16, u32, u64, f32, f64 and bool
  
  Error: Could not compile 'unknown_once.slick' due to 1 error
  [1]

A bad operand is reported where it happens, and the result still has its
type, so using it later is fine.

  $ cat > operand_once.slick <<'EOF'
  > main :: fn() {
  >     print(1 + true);
  >     y := 1 + true;
  >     print(y);
  > }
  > EOF
  $ slick run operand_once.slick
  Error: Operator '+' expects numbers, found i32 and bool
   --> operand_once.slick:2:13
    |
  2 |     print(1 + true);
    |           - i32
    |             ^
    |               ---- bool
  
  Error: Operator '+' expects numbers, found i32 and bool
   --> operand_once.slick:3:12
    |
  3 |     y := 1 + true;
    |          - i32
    |            ^
    |              ---- bool
  
  Error: Could not compile 'operand_once.slick' due to 2 errors
  [1]

A missing ')' is one error, and the next statement still parses: its missing
';' is found too.

  $ cat > paren_once.slick <<'EOF'
  > main :: fn() {
  >     print((1 + 2);
  >     print(3)
  > }
  > EOF
  $ slick run paren_once.slick
  Error: Unclosed '('
   --> paren_once.slick:2:18
    |
  2 |     print((1 + 2));
    |                  + Expected ')'
  
  Error: Expected ';' at the end of this statement
   --> paren_once.slick:3:13
    |
  3 |     print(3);
    |             + Expected ';'
  
  Error: Could not compile 'paren_once.slick' due to 2 errors
  [1]

A broken parameter list is one error, and the body still parses.

  $ cat > params_once.slick <<'EOF'
  > f :: fn(a i32) {
  >     print(1)
  > }
  > main :: fn() { f(1); }
  > EOF
  $ slick run params_once.slick
  Error: Expected ':', found 'i32'
   --> params_once.slick:1:11
    |
  1 | f :: fn(a i32) {
    |           ^^^ Expected ':'
  
  Error: Expected ';' at the end of this statement
   --> params_once.slick:2:13
    |
  2 |     print(1);
    |             + Expected ';'
  
  Error: Could not compile 'params_once.slick' due to 2 errors
  [1]

A function missing its '}' is one error, pointing at the '{' that is not
closed, and the next function still parses.

  $ cat > unclosed.slick <<'EOF'
  > f :: fn() {
  >     print(1);
  > main :: fn() {
  >     print(2)
  > }
  > EOF
  $ slick run unclosed.slick
  Error: Expected '}', found 'main'
   --> unclosed.slick:3:1
    |
  1 | f :: fn() {
    |           - This '{' is not closed
  2 |     print(1);
  3 | main :: fn() {
    | ^^^^ Expected '}'
    |
  Note: A function cannot be defined inside another one
  
  Error: Expected ';' at the end of this statement
   --> unclosed.slick:4:13
    |
  4 |     print(2);
    |             + Expected ';'
  
  Error: Could not compile 'unclosed.slick' due to 2 errors
  [1]

A misspelled keyword is one error with a suggestion. Skipping past it skips
the whole block that follows, so the block's '}' does not end the function
early.

  $ cat > keyword_typo.slick <<'EOF'
  > main :: fn() {
  >     i : mut = 0;
  >     whle i < 10 {
  >         print(i);
  >         i += 1;
  >     }
  > }
  > EOF
  $ slick run keyword_typo.slick
  Error: 'whle' is not a keyword
   --> keyword_typo.slick:3:5
    |
  3 |     whle i < 10 {
    |     ^^^^
    |
  Help: Did you mean 'while'?
    |
  3 |     while i < 10 {
    |     ~~~~~
  
  Error: Could not compile 'keyword_typo.slick' due to 1 error
  [1]

Other words after an expression on the same line are one error.

  $ cat > junk.slick <<'EOF'
  > main :: fn() {
  >     foo bar;
  > }
  > EOF
  $ slick run junk.slick
  Error: Expected ';', found 'bar'
   --> junk.slick:2:9
    |
  2 |     foo bar;
    |         ^^^ Expected ';'
  
  Error: Could not compile 'junk.slick' due to 1 error
  [1]

The lexer reports every bad character and literal. The parser only runs once
there are none, since a skipped character would confuse it.

  $ cat > lexer.slick <<'EOF'
  > main :: fn() {
  >     x := 1 @ 2;
  >     y := 0x1G;
  >     z := 3 $ 4;
  > }
  > EOF
  $ slick run lexer.slick
  Error: Unexpected character '@'
   --> lexer.slick:2:12
    |
  2 |     x := 1 @ 2;
    |            ^
  
  Error: Invalid integer literal '0x1G'
   --> lexer.slick:3:10
    |
  3 |     y := 0x1G;
    |          ^^^^ Only hexadecimal digits and '_' are allowed
  
  Error: Unexpected character '$'
   --> lexer.slick:4:12
    |
  4 |     z := 3 $ 4;
    |            ^
  
  Error: Could not compile 'lexer.slick' due to 3 errors
  [1]

Columns count characters: the '@' after a two-byte 'é' is in column 13.

  $ cat > utf8.slick <<'EOF'
  > main :: fn() {
  >     print(é @);
  > }
  > EOF
  $ slick run utf8.slick
  Error: Unexpected byte 0xC3
   --> utf8.slick:2:11
    |
  2 |     print(é @);
    |           ^
    |
  Note: Only comments can contain characters outside ASCII
  
  Error: Unexpected character '@'
   --> utf8.slick:2:13
    |
  2 |     print(é @);
    |             ^
  
  Error: Could not compile 'utf8.slick' due to 2 errors
  [1]

Garbage input ends with errors, not a hang (timeout's exit code 124) or an
OCaml exception (exit code 2).

  $ printf ') } ; :: fn fn ( -> { ) ;;; x := := ( fn main :: ( ) { if while return } } }\n' > garbage.slick
  $ timeout 10 slick run garbage.slick > out 2>&1; echo "exit $?"
  exit 1
  $ tail -1 out | sed 's/due to [0-9]* errors/due to N errors/'
  Error: Could not compile 'garbage.slick' due to N errors

  $ printf 'main :: fn() { x := ((((((( ; y := ))))) ; if { while } return return ; } fn ::\n' > garbage2.slick
  $ timeout 10 slick run garbage2.slick > out 2>&1; echo "exit $?"
  exit 1
