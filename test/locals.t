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
  compound_zero.slick:3: panic: division by zero
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
  immutable.slick:3:5: error: cannot assign to 'count': it was declared without 'mut' on line 2
  [1]

  $ cat > immutable_compound.slick <<'EOF'
  > main :: fn() {
  >     x : i32 = 1;
  >     x += 1;
  > }
  > EOF
  $ slick run immutable_compound.slick
  immutable_compound.slick:3:5: error: cannot assign to 'x': it was declared without 'mut' on line 2
  [1]

Names must be declared before use.

  $ cat > before.slick <<'EOF'
  > main :: fn() {
  >     print(x);
  >     x := 1;
  > }
  > EOF
  $ slick run before.slick
  before.slick:2:11: error: undeclared name 'x'
  [1]

  $ cat > never.slick <<'EOF'
  > main :: fn() {
  >     y = 1;
  > }
  > EOF
  $ slick run never.slick
  never.slick:2:5: error: undeclared name 'y'
  [1]

  $ cat > own_init.slick <<'EOF'
  > main :: fn() {
  >     x := x + 1;
  > }
  > EOF
  $ slick run own_init.slick
  own_init.slick:2:10: error: undeclared name 'x'
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
  same_block.slick:3:5: error: 'x' is already declared on line 2
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
  nested.slick:4:9: error: 'x' is already declared on line 2
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
  deep.slick:5:13: error: 'x' is already declared on line 2
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
  out_of_scope.slick:5:11: error: undeclared name 'x'
  [1]

A local cannot take the name of a function, whether it is defined before or
after, or the name of print.

  $ cat > local_print.slick <<'EOF'
  > main :: fn() {
  >     print := 1;
  > }
  > EOF
  $ slick run local_print.slick
  local_print.slick:2:5: error: 'print' is a built-in function and cannot be redeclared
  [1]

  $ cat > local_fn_before.slick <<'EOF'
  > helper :: fn() { }
  > main :: fn() {
  >     helper := 1;
  > }
  > EOF
  $ slick run local_fn_before.slick
  local_fn_before.slick:3:5: error: 'helper' is already declared as a function on line 1
  [1]

  $ cat > local_fn_after.slick <<'EOF'
  > main :: fn() {
  >     later := 1;
  > }
  > later :: fn() { }
  > EOF
  $ slick run local_fn_after.slick
  local_fn_after.slick:2:5: error: 'later' is already declared as a function on line 4
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
  init_bool.slick:2:16: error: cannot initialize 'x' of type bool with a value of type i32
  [1]

  $ cat > init_int.slick <<'EOF'
  > main :: fn() {
  >     x : mut i32 = true;
  > }
  > EOF
  $ slick run init_int.slick
  init_int.slick:2:19: error: cannot initialize 'x' of type i32 with a value of type bool
  [1]

  $ cat > assign_type.slick <<'EOF'
  > main :: fn() {
  >     x : mut = 1;
  >     x = true;
  > }
  > EOF
  $ slick run assign_type.slick
  assign_type.slick:3:9: error: cannot assign a value of type bool to 'x' of type i32
  [1]

  $ cat > compound_bool.slick <<'EOF'
  > main :: fn() {
  >     b : mut = true;
  >     b += 1;
  > }
  > EOF
  $ slick run compound_bool.slick
  compound_bool.slick:3:7: error: operator '+=' expects i32 operands, found bool and i32
  [1]

Declaration errors.

  $ cat > no_type.slick <<'EOF'
  > main :: fn() {
  >     x : mut;
  > }
  > EOF
  $ slick run no_type.slick
  no_type.slick:2:5: error: 'x' needs a type or an initial value
  [1]

  $ cat > unknown_type.slick <<'EOF'
  > main :: fn() {
  >     x : Foo;
  > }
  > EOF
  $ slick run unknown_type.slick
  unknown_type.slick:2:9: error: unknown type 'Foo'
  [1]

Only names can be assigned to.

  $ cat > assign_literal.slick <<'EOF'
  > main :: fn() {
  >     1 = 2;
  > }
  > EOF
  $ slick run assign_literal.slick
  assign_literal.slick:2:5: error: cannot assign to this expression
  [1]

  $ cat > assign_fn.slick <<'EOF'
  > helper :: fn() { }
  > main :: fn() {
  >     helper = 1;
  > }
  > EOF
  $ slick run assign_fn.slick
  assign_fn.slick:3:5: error: cannot assign to function 'helper'
  [1]
