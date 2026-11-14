Stage 3: local declarations, assignment, mutability, and the no-shadowing
rule.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

All six declaration forms. A declaration without a value is zero.

  $ cat > forms.slick <<'EOF'
  > main :: fn() {
  >     a := 1;
  >     b : i32 = 2;
  >     c : mut = 3;
  >     d : mut i32 = 4;
  >     e : i32;
  >     f : mut i32;
  >     print(a);
  >     print(b);
  >     print(c);
  >     print(d);
  >     print(e);
  >     print(f);
  > }
  > EOF
  $ slick run forms.slick
  1
  2
  3
  4
  0
  0

Assignment and every compound operator.

  $ cat > compound.slick <<'EOF'
  > main :: fn() {
  >     x : mut = 10;
  >     x = 20;
  >     print(x);
  >     x += 5;
  >     print(x);
  >     x -= 3;
  >     print(x);
  >     x *= 2;
  >     print(x);
  >     x /= 5;
  >     print(x);
  >     x %= 3;
  >     print(x);
  >     x = x * x + 1;
  >     print(x);
  > }
  > EOF
  $ slick run compound.slick
  20
  25
  22
  44
  8
  2
  5

Compound division checks for zero like plain division.

  $ cat > compound_zero.slick <<'EOF'
  > main :: fn() {
  >     x : mut = 5;
  >     x /= 0;
  > }
  > EOF
  $ slick run compound_zero.slick
  Panic: Division by zero
   --> compound_zero.slick:3:10
    |
  3 |     x /= 0;
    |          ^ This is zero
  [1]

Assigning to something declared without 'mut' is an error, with '=' and with
a compound operator.

  $ cat > immutable.slick <<'EOF'
  > main :: fn() {
  >     count := 0;
  >     count = 1;
  > }
  > EOF
  $ slick run immutable.slick
  Error: Cannot assign to 'count': it was declared without 'mut'
   --> immutable.slick:3:5
    |
  2 |     count := 0;
    |     ----- Declared here without 'mut'
  3 |     count = 1;
    |     ^^^^^ Cannot assign
    |
  Help: Declare it with 'mut'
    |
  2 |     count : mut = 0;
    |           ~~~~~~~
  
  Error: Could not compile 'immutable.slick' due to 1 error
  [1]

  $ cat > immutable_compound.slick <<'EOF'
  > main :: fn() {
  >     x : i32 = 1;
  >     x += 1;
  > }
  > EOF
  $ slick run immutable_compound.slick
  Error: Cannot assign to 'x': it was declared without 'mut'
   --> immutable_compound.slick:3:5
    |
  2 |     x : i32 = 1;
    |     - Declared here without 'mut'
  3 |     x += 1;
    |     ^ Cannot assign
    |
  Help: Declare it with 'mut'
    |
  2 |     x : mut i32 = 1;
    |         ++++
  
  Error: Could not compile 'immutable_compound.slick' due to 1 error
  [1]

Names must be declared before use.

  $ cat > before.slick <<'EOF'
  > main :: fn() {
  >     print(x);
  >     x := 1;
  > }
  > EOF
  $ slick run before.slick
  Error: Undeclared name 'x'
   --> before.slick:2:11
    |
  2 |     print(x);
    |           ^ Not declared
  
  Error: Could not compile 'before.slick' due to 1 error
  [1]

  $ cat > never.slick <<'EOF'
  > main :: fn() {
  >     y = 1;
  > }
  > EOF
  $ slick run never.slick
  Error: Undeclared name 'y'
   --> never.slick:2:5
    |
  2 |     y = 1;
    |     ^ Not declared
  
  Error: Could not compile 'never.slick' due to 1 error
  [1]

  $ cat > own_init.slick <<'EOF'
  > main :: fn() {
  >     x := x + 1;
  > }
  > EOF
  $ slick run own_init.slick
  Error: Undeclared name 'x'
   --> own_init.slick:2:10
    |
  2 |     x := x + 1;
    |          ^ Not declared
  
  Error: Could not compile 'own_init.slick' due to 1 error
  [1]

No shadowing: a name cannot be declared again while it is visible, in the
same block or any block inside it.

  $ cat > same_block.slick <<'EOF'
  > main :: fn() {
  >     x := 1;
  >     x := 2;
  > }
  > EOF
  $ slick run same_block.slick
  Error: 'x' is already declared
   --> same_block.slick:3:5
    |
  2 |     x := 1;
    |     - First declared here
  3 |     x := 2;
    |     ^ Declared again here
    |
  Note: Slick does not allow shadowing
  Help: Choose a different name
  
  Error: Could not compile 'same_block.slick' due to 1 error
  [1]

When the first declaration is 'mut', the help suggests assigning instead.

  $ cat > reassign.slick <<'EOF'
  > main :: fn() {
  >     score : mut = 0;
  >     score := 10;
  > }
  > EOF
  $ slick run reassign.slick
  Error: 'score' is already declared
   --> reassign.slick:3:5
    |
  2 |     score : mut = 0;
    |     ----- First declared here
  3 |     score := 10;
    |     ^^^^^ Declared again here
    |
  Note: Slick does not allow shadowing
  Help: To change its value, assign to it: 'score = 10;'
  
  Error: Could not compile 'reassign.slick' due to 1 error
  [1]

  $ cat > nested.slick <<'EOF'
  > main :: fn() {
  >     x := 1;
  >     {
  >         x := 2;
  >     }
  > }
  > EOF
  $ slick run nested.slick
  Error: 'x' is already declared
   --> nested.slick:4:9
    |
  2 |     x := 1;
    |     - First declared here
  3 |     {
  4 |         x := 2;
    |         ^ Declared again here
    |
  Note: Slick does not allow shadowing
  Help: Choose a different name
  
  Error: Could not compile 'nested.slick' due to 1 error
  [1]

  $ cat > deep.slick <<'EOF'
  > main :: fn() {
  >     x := 1;
  >     {
  >         {
  >             x := 2;
  >         }
  >     }
  > }
  > EOF
  $ slick run deep.slick
  Error: 'x' is already declared
   --> deep.slick:5:13
    |
  2 |     x := 1;
    |     - First declared here
  ...
  5 |             x := 2;
    |             ^ Declared again here
    |
  Note: Slick does not allow shadowing
  Help: Choose a different name
  
  Error: Could not compile 'deep.slick' due to 1 error
  [1]

Blocks that do not nest can reuse a name, and a name is free again once its
block ends.

  $ cat > siblings.slick <<'EOF'
  > main :: fn() {
  >     {
  >         x := 1;
  >         print(x);
  >     }
  >     {
  >         x := 2;
  >         print(x);
  >     }
  >     x := 3;
  >     print(x);
  > }
  > EOF
  $ slick run siblings.slick
  1
  2
  3

A name is not visible after its block ends.

  $ cat > out_of_scope.slick <<'EOF'
  > main :: fn() {
  >     {
  >         x := 1;
  >     }
  >     print(x);
  > }
  > EOF
  $ slick run out_of_scope.slick
  Error: Undeclared name 'x'
   --> out_of_scope.slick:5:11
    |
  3 |         x := 1;
    |         - Declared here, in a block that has ended
  4 |     }
  5 |     print(x);
    |           ^ Not declared
  
  Error: Could not compile 'out_of_scope.slick' due to 1 error
  [1]

A local cannot take the name of a function, whether it is defined before or
after, or the name of print.

  $ cat > local_print.slick <<'EOF'
  > main :: fn() {
  >     print := 1;
  > }
  > EOF
  $ slick run local_print.slick
  Error: 'print' is a built-in function and cannot be redeclared
   --> local_print.slick:2:5
    |
  2 |     print := 1;
    |     ^^^^^
    |
  Help: Choose a different name
  
  Error: Could not compile 'local_print.slick' due to 1 error
  [1]

  $ cat > local_fn_before.slick <<'EOF'
  > helper :: fn() { }
  > main :: fn() {
  >     helper := 1;
  > }
  > EOF
  $ slick run local_fn_before.slick
  Error: 'helper' is already declared as a function
   --> local_fn_before.slick:3:5
    |
  1 | helper :: fn() { }
    | ------ Function defined here
  2 | main :: fn() {
  3 |     helper := 1;
    |     ^^^^^^ Declared again here
    |
  Note: Slick does not allow shadowing
  Help: Choose a different name
  
  Error: Could not compile 'local_fn_before.slick' due to 1 error
  [1]

  $ cat > local_fn_after.slick <<'EOF'
  > main :: fn() {
  >     later := 1;
  > }
  > later :: fn() { }
  > EOF
  $ slick run local_fn_after.slick
  Error: 'later' is already declared as a function
   --> local_fn_after.slick:2:5
    |
  2 |     later := 1;
    |     ^^^^^ Declared again here
  3 | }
  4 | later :: fn() { }
    | ----- Function defined here
    |
  Note: Slick does not allow shadowing
  Help: Choose a different name
  
  Error: Could not compile 'local_fn_after.slick' due to 1 error
  [1]

Names that mean something in C are fine as Slick names.

  $ cat > c_names.slick <<'EOF'
  > main :: fn() {
  >     int := 1;
  >     double := 2;
  >     register := 3;
  >     tmp := 4;
  >     INT32_MIN := 5;
  >     print(int + double + register + tmp + INT32_MIN);
  > }
  > EOF
  $ slick run c_names.slick
  15

A local whose C name could match a function's C name.

  $ cat > c_collide.slick <<'EOF'
  > f_1 :: fn() { print(7); }
  > main :: fn() {
  >     slick_f := 1;
  >     f_1();
  >     print(slick_f);
  > }
  > EOF
  $ slick run c_collide.slick
  7
  1

Types must match.

  $ cat > init_bool.slick <<'EOF'
  > main :: fn() {
  >     x : bool = 1;
  > }
  > EOF
  $ slick run init_bool.slick
  Error: Cannot initialize 'x' of type bool with a value of type i32
   --> init_bool.slick:2:16
    |
  2 |     x : bool = 1;
    |         ---- Declared as bool here
    |                ^ This is i32
  
  Error: Could not compile 'init_bool.slick' due to 1 error
  [1]

  $ cat > init_int.slick <<'EOF'
  > main :: fn() {
  >     x : mut i32 = true;
  > }
  > EOF
  $ slick run init_int.slick
  Error: Cannot initialize 'x' of type i32 with a value of type bool
   --> init_int.slick:2:19
    |
  2 |     x : mut i32 = true;
    |             --- Declared as i32 here
    |                   ^^^^ This is bool
  
  Error: Could not compile 'init_int.slick' due to 1 error
  [1]

  $ cat > assign_type.slick <<'EOF'
  > main :: fn() {
  >     x : mut = 1;
  >     x = true;
  > }
  > EOF
  $ slick run assign_type.slick
  Error: Cannot assign a value of type bool to 'x' of type i32
   --> assign_type.slick:3:9
    |
  2 |     x : mut = 1;
    |     - 'x' is declared as i32 here
  3 |     x = true;
    |         ^^^^ This is bool
  
  Error: Could not compile 'assign_type.slick' due to 1 error
  [1]

  $ cat > compound_bool.slick <<'EOF'
  > main :: fn() {
  >     b : mut = true;
  >     b += 1;
  > }
  > EOF
  $ slick run compound_bool.slick
  Error: Operator '+=' expects i32 operands, found bool and i32
   --> compound_bool.slick:3:7
    |
  3 |     b += 1;
    |     - bool
    |       ^^
    |          - i32
  
  Error: Could not compile 'compound_bool.slick' due to 1 error
  [1]

Declaration errors.

  $ cat > no_type.slick <<'EOF'
  > main :: fn() {
  >     x : mut;
  > }
  > EOF
  $ slick run no_type.slick
  Error: 'x' needs a type or an initial value
   --> no_type.slick:2:5
    |
  2 |     x : mut;
    |     ^
    |
  Help: Give it a type, like 'x : mut i32;', or a value, like 'x : mut = 0;'
  
  Error: Could not compile 'no_type.slick' due to 1 error
  [1]

  $ cat > unknown_type.slick <<'EOF'
  > main :: fn() {
  >     x : Foo;
  > }
  > EOF
  $ slick run unknown_type.slick
  Error: Unknown type 'Foo'
   --> unknown_type.slick:2:9
    |
  2 |     x : Foo;
    |         ^^^ Not a type
    |
  Note: The types available now are i32 and bool
  
  Error: Could not compile 'unknown_type.slick' due to 1 error
  [1]

Only names can be assigned to.

  $ cat > assign_literal.slick <<'EOF'
  > main :: fn() {
  >     1 = 2;
  > }
  > EOF
  $ slick run assign_literal.slick
  Error: Cannot assign to this expression
   --> assign_literal.slick:2:5
    |
  2 |     1 = 2;
    |     ^ Not a name
    |
  Note: Only local names can be assigned to
  
  Error: Could not compile 'assign_literal.slick' due to 1 error
  [1]

  $ cat > assign_fn.slick <<'EOF'
  > helper :: fn() { }
  > main :: fn() {
  >     helper = 1;
  > }
  > EOF
  $ slick run assign_fn.slick
  Error: Cannot assign to function 'helper'
   --> assign_fn.slick:3:5
    |
  1 | helper :: fn() { }
    | ------ Function defined here
  2 | main :: fn() {
  3 |     helper = 1;
    |     ^^^^^^
  
  Error: Could not compile 'assign_fn.slick' due to 1 error
  [1]

