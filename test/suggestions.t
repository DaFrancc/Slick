"Did you mean": an unknown name gets a suggestion when a known one is close.
Close means within one edit (an insertion, deletion, change, or swap of two
neighbouring characters) per three characters, and at least one.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

A visible local.

  $ cat > close_local.slick <<'EOF'
  > main :: fn() {
  >     count := 1;
  >     print(cuont);
  > }
  > EOF
  $ slick run close_local.slick
  Error: Undeclared name 'cuont'
   --> close_local.slick:3:11
    |
  3 |     print(cuont);
    |           ^^^^^ Not declared
    |
  Help: Did you mean 'count'?
    |
  3 |     print(count);
    |           ~~~~~
  
  Error: Could not compile 'close_local.slick' due to 1 error
  [1]

A function.

  $ cat > close_fn.slick <<'EOF'
  > helper :: fn() { }
  > main :: fn() {
  >     halper();
  > }
  > EOF
  $ slick run close_fn.slick
  Error: Unknown function 'halper'
   --> close_fn.slick:3:5
    |
  3 |     halper();
    |     ^^^^^^ Not defined
    |
  Help: Did you mean 'helper'?
    |
  3 |     helper();
    |     ~~~~~~
  
  Error: Could not compile 'close_fn.slick' due to 1 error
  [1]

A type, with two characters swapped, and with the wrong case.

  $ cat > swapped_type.slick <<'EOF'
  > main :: fn() {
  >     x : i23 = 1;
  >     y : Bool = true;
  > }
  > EOF
  $ slick run swapped_type.slick
  Error: Unknown type 'i23'
   --> swapped_type.slick:2:9
    |
  2 |     x : i23 = 1;
    |         ^^^ Not a type
    |
  Help: Did you mean 'i32'?
    |
  2 |     x : i32 = 1;
    |         ~~~
  
  Error: Unknown type 'Bool'
   --> swapped_type.slick:3:9
    |
  3 |     y : Bool = true;
    |         ^^^^ Not a type
    |
  Help: Did you mean 'bool'?
    |
  3 |     y : bool = true;
    |         ~~~~
  
  Error: Could not compile 'swapped_type.slick' due to 2 errors
  [1]

A name too far from anything gets no suggestion.

  $ cat > far.slick <<'EOF'
  > main :: fn() {
  >     total := 1;
  >     print(xyz);
  > }
  > EOF
  $ slick run far.slick
  Error: Undeclared name 'xyz'
   --> far.slick:3:11
    |
  3 |     print(xyz);
    |           ^^^ Not declared
  
  Error: Could not compile 'far.slick' due to 1 error
  [1]

