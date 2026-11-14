How diagnostics are laid out: the line-number gutter, gaps between lines,
several labels on one line, tabs, each kind of suggested edit, and color.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

A two-digit line number widens the gutter for the whole diagnostic.

  $ cat > wide.slick <<'EOF'
  > main :: fn() {
  >     print(1);
  >     print(2);
  >     print(3);
  >     print(4);
  >     print(5);
  >     print(6);
  >     print(7);
  >     total := 0;
  >     total += 1;
  > }
  > EOF
  $ slick run wide.slick
  Error: Cannot assign to 'total': it was declared without 'mut'
    --> wide.slick:10:5
     |
   9 |     total := 0;
     |     ----- Declared here without 'mut'
  10 |     total += 1;
     |     ^^^^^ Cannot assign
     |
  Help: Declare it with 'mut'
     |
   9 |     total : mut = 0;
     |           ~~~~~~~
  
  Error: Could not compile 'wide.slick' due to 1 error
  [1]

One line between two labelled lines is shown.

  $ cat > gap_one.slick <<'EOF'
  > main :: fn() {
  >     n := 1;
  >     print(n);
  >     n = 2;
  > }
  > EOF
  $ slick run gap_one.slick
  Error: Cannot assign to 'n': it was declared without 'mut'
   --> gap_one.slick:4:5
    |
  2 |     n := 1;
    |     - Declared here without 'mut'
  3 |     print(n);
  4 |     n = 2;
    |     ^ Cannot assign
    |
  Help: Declare it with 'mut'
    |
  2 |     n : mut = 1;
    |       ~~~~~~~
  
  Error: Could not compile 'gap_one.slick' due to 1 error
  [1]

A longer gap is shown as '...'.

  $ cat > gap_many.slick <<'EOF'
  > main :: fn() {
  >     n := 1;
  >     print(n);
  >     print(n);
  >     print(n);
  >     n = 2;
  > }
  > EOF
  $ slick run gap_many.slick
  Error: Cannot assign to 'n': it was declared without 'mut'
   --> gap_many.slick:6:5
    |
  2 |     n := 1;
    |     - Declared here without 'mut'
  ...
  6 |     n = 2;
    |     ^ Cannot assign
    |
  Help: Declare it with 'mut'
    |
  2 |     n : mut = 1;
    |       ~~~~~~~
  
  Error: Could not compile 'gap_many.slick' due to 1 error
  [1]

Two labels on the same line each get their own row.

  $ cat > same_line.slick <<'EOF'
  > main :: fn() { n := 1; n = 2; }
  > EOF
  $ slick run same_line.slick
  Error: Cannot assign to 'n': it was declared without 'mut'
   --> same_line.slick:1:24
    |
  1 | main :: fn() { n := 1; n = 2; }
    |                - Declared here without 'mut'
    |                        ^ Cannot assign
    |
  Help: Declare it with 'mut'
    |
  1 | main :: fn() { n : mut = 1; n = 2; }
    |                  ~~~~~~~
  
  Error: Could not compile 'same_line.slick' due to 1 error
  [1]

A tab is shown as four spaces, and the column in '-->' counts it as one
character.

  $ printf 'main :: fn() {\n\tprint(1)\n}\n' > tab.slick
  $ slick run tab.slick
  Error: Expected ';' at the end of this statement
   --> tab.slick:2:10
    |
  2 |     print(1);
    |             + Expected ';'
  
  Error: Could not compile 'tab.slick' due to 1 error
  [1]

A span across lines is underlined to the end of its first line.

  $ cat > multiline.slick <<'EOF'
  > main :: fn() {
  >     x : bool = 1 +
  >         2;
  > }
  > EOF
  $ slick run multiline.slick
  Error: Cannot initialize 'x' of type bool with a value of type i32
   --> multiline.slick:2:16
    |
  2 |     x : bool = 1 +
    |         ---- Declared as bool here
    |                ^^^ This is i32
  
  Error: Could not compile 'multiline.slick' due to 1 error
  [1]

Edits: '~' marks a replacement (above), and '+' an insertion.

  $ cat > insertion.slick <<'EOF'
  > main :: fn() {
  >     x : i32 = 1;
  >     x = 2;
  > }
  > EOF
  $ slick run insertion.slick
  Error: Cannot assign to 'x': it was declared without 'mut'
   --> insertion.slick:3:5
    |
  2 |     x : i32 = 1;
    |     - Declared here without 'mut'
  3 |     x = 2;
    |     ^ Cannot assign
    |
  Help: Declare it with 'mut'
    |
  2 |     x : mut i32 = 1;
    |         ++++
  
  Error: Could not compile 'insertion.slick' due to 1 error
  [1]

A deletion
shows the original line with '-' under what goes.

  $ cat > deletion.slick <<'EOF'
  > main :: fn() { ; }
  > EOF
  $ slick run deletion.slick
  Error: Unexpected ';'
   --> deletion.slick:1:16
    |
  1 | main :: fn() { ; }
    |                ^ Not needed here
    |
  Help: Remove it
    |
  1 | main :: fn() { ; }
    |                -
  
  Error: Could not compile 'deletion.slick' due to 1 error
  [1]

Color, shown with cat -v: ^[[1;31m is bold red, ^[[0m resets.

  $ slick run deletion.slick --color=always 2>&1 | cat -v
  ^[[1;31mError^[[0m^[[1m: Unexpected ';'^[[0m
   ^[[1;34m-->^[[0m deletion.slick:1:16
  ^[[1;34m  |^[[0m
  ^[[1;34m1 |^[[0m main :: fn() { ; }
  ^[[1;34m  |^[[0m                ^[[1;31m^ Not needed here^[[0m
  ^[[1;34m  |^[[0m
  ^[[1;36mHelp^[[0m: Remove it
  ^[[1;34m  |^[[0m
  ^[[1;34m1 |^[[0m main :: fn() { ^[[31m;^[[0m }
  ^[[1;34m  |^[[0m                ^[[31m-^[[0m
  
  ^[[1;31mError^[[0m^[[1m: Could not compile 'deletion.slick' due to 1 error^[[0m

Missing text shown in the source line is green (^[[32m), with its '+'.

  $ cat > missing_paren.slick <<'EOF'
  > main :: fn() {
  >     print(1
  > }
  > EOF
  $ slick run missing_paren.slick --color=always 2>&1 | sed -n '4,5p' | cat -v
  ^[[1;34m2 |^[[0m     print(1^[[32m)^[[0m
  ^[[1;34m  |^[[0m            ^[[32m+^[[0m^[[1;31m Expected ')'^[[0m

--color=never and --color=auto give plain text here, since stderr is not a
terminal under the test runner. --color wins over NO_COLOR.

  $ slick run deletion.slick --color=never 2>&1 | head -1 | cat -v
  Error: Unexpected ';'
  $ slick run deletion.slick --color=auto 2>&1 | head -1 | cat -v
  Error: Unexpected ';'
  $ NO_COLOR=1 slick run deletion.slick --color=always 2>&1 | head -1 | cat -v
  ^[[1;31mError^[[0m^[[1m: Unexpected ';'^[[0m

An invalid --color value is a usage error.

  $ slick run deletion.slick --color=sometimes
  Error: Invalid value 'sometimes' for '--color': use 'auto', 'always' or 'never'
  [2]
  $ slick run deletion.slick --color
  Error: Invalid value '' for '--color': use 'auto', 'always' or 'never'
  [2]
