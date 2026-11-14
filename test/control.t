Stage 4: if, else if, else, while, and the boolean operators.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

if and else pick the right branch.

  $ cat > branch.slick <<'EOF'
  > main :: fn() {
  >     if true { print(1); } else { print(2); }
  >     if false { print(3); } else { print(4); }
  >     if true { print(5); }
  >     if false { print(6); }
  > }
  > EOF
  $ slick run branch.slick
  1
  4
  5

An else-if chain, with each arm taken once.

  $ cat > chain.slick <<'EOF'
  > main :: fn() {
  >     i : mut = 0;
  >     while i < 3 {
  >         if i == 0 {
  >             print(10);
  >         } else if i == 1 {
  >             print(20);
  >         } else {
  >             print(30);
  >         }
  >         i += 1;
  >     }
  > }
  > EOF
  $ slick run chain.slick
  10
  20
  30

Every comparison operator, on a value less than, equal to, and greater than 2.
Each digit of the result is one operator: < <= > >= == != from left to right.

  $ cat > compare.slick <<'EOF'
  > main :: fn() {
  >     a : mut = 1;
  >     while a <= 3 {
  >         r : mut = 0;
  >         if a < 2 { r += 100000; }
  >         if a <= 2 { r += 10000; }
  >         if a > 2 { r += 1000; }
  >         if a >= 2 { r += 100; }
  >         if a == 2 { r += 10; }
  >         if a != 2 { r += 1; }
  >         print(r);
  >         a += 1;
  >     }
  > }
  > EOF
  $ slick run compare.slick
  110001
  10110
  1101

Truth tables for &&, || and !, equality on booleans, and a zeroed bool.

  $ cat > logic.slick <<'EOF'
  > main :: fn() {
  >     t := true;
  >     f := false;
  >     if t && t { print(1); } else { print(0); }
  >     if t && f { print(1); } else { print(0); }
  >     if f && t { print(1); } else { print(0); }
  >     if f && f { print(1); } else { print(0); }
  >     if t || t { print(1); } else { print(0); }
  >     if t || f { print(1); } else { print(0); }
  >     if f || t { print(1); } else { print(0); }
  >     if f || f { print(1); } else { print(0); }
  >     if !t { print(1); } else { print(0); }
  >     if !f { print(1); } else { print(0); }
  >     if t == f { print(1); } else { print(0); }
  >     if f == f { print(1); } else { print(0); }
  >     if t != f { print(1); } else { print(0); }
  >     z : bool;
  >     if z { print(1); } else { print(0); }
  > }
  > EOF
  $ slick run logic.slick
  1
  0
  0
  0
  1
  1
  1
  0
  0
  1
  0
  1
  1
  0

&& binds tighter than ||, and comparisons bind looser than arithmetic.

  $ cat > logic_prec.slick <<'EOF'
  > main :: fn() {
  >     if true || false && false { print(1); } else { print(0); }
  >     if false && true || true { print(1); } else { print(0); }
  >     if 1 + 2 == 3 { print(1); } else { print(0); }
  >     if 2 * 3 > 5 && 1 < 2 { print(1); } else { print(0); }
  >     if !(1 < 2) { print(1); } else { print(0); }
  > }
  > EOF
  $ slick run logic_prec.slick
  1
  1
  1
  1
  0

while loops, including ones whose condition is false from the start.

  $ cat > loops.slick <<'EOF'
  > main :: fn() {
  >     i : mut = 0;
  >     while i < 5 {
  >         print(i);
  >         i += 1;
  >     }
  >     while false { print(99); }
  >     j : mut = 10;
  >     while j < 5 { print(j); }
  >     print(-1);
  > }
  > EOF
  $ slick run loops.slick
  0
  1
  2
  3
  4
  -1

Nested loops, and loops in a row whose bodies each declare the same name.

  $ cat > nested_loops.slick <<'EOF'
  > main :: fn() {
  >     i : mut = 0;
  >     while i < 3 {
  >         j : mut = 0;
  >         while j < 2 {
  >             print(i * 10 + j);
  >             j += 1;
  >         }
  >         i += 1;
  >     }
  >     k : mut = 0;
  >     while k < 2 {
  >         t := k * 2;
  >         print(t);
  >         k += 1;
  >     }
  >     while k < 4 {
  >         t := k * 3;
  >         print(t);
  >         k += 1;
  >     }
  > }
  > EOF
  $ slick run nested_loops.slick
  0
  1
  10
  11
  20
  21
  0
  2
  6
  9

The two branches of an if are separate blocks, so both can declare a name.

  $ cat > branch_names.slick <<'EOF'
  > main :: fn() {
  >     if true { x := 1; print(x); } else { x := 2; print(x); }
  >     if false { x := 3; print(x); } else { x := 4; print(x); }
  > }
  > EOF
  $ slick run branch_names.slick
  1
  4

A name declared in a loop body cannot be declared again inside it.

  $ cat > loop_shadow.slick <<'EOF'
  > main :: fn() {
  >     while false {
  >         n := 1;
  >         if true {
  >             n := 2;
  >         }
  >     }
  > }
  > EOF
  $ slick run loop_shadow.slick
  loop_shadow.slick:5:13: error: 'n' is already declared on line 3
  [1]

Conditions must be bool.

  $ cat > if_int.slick <<'EOF'
  > main :: fn() {
  >     if 1 { }
  > }
  > EOF
  $ slick run if_int.slick
  if_int.slick:2:8: error: condition of 'if' must be bool, found i32
  [1]

  $ cat > while_int.slick <<'EOF'
  > main :: fn() {
  >     while 0 { }
  > }
  > EOF
  $ slick run while_int.slick
  while_int.slick:2:11: error: condition of 'while' must be bool, found i32
  [1]

  $ cat > elseif_int.slick <<'EOF'
  > main :: fn() {
  >     if false { } else if 5 { }
  > }
  > EOF
  $ slick run elseif_int.slick
  elseif_int.slick:2:26: error: condition of 'if' must be bool, found i32
  [1]

Braces are required.

  $ cat > no_braces.slick <<'EOF'
  > main :: fn() {
  >     if true print(1);
  > }
  > EOF
  $ slick run no_braces.slick
  no_braces.slick:2:13: error: expected '{', found 'print'
  [1]

  $ cat > else_no_braces.slick <<'EOF'
  > main :: fn() {
  >     if true { } else print(1);
  > }
  > EOF
  $ slick run else_no_braces.slick
  else_no_braces.slick:2:22: error: expected '{' or 'if' after 'else', found 'print'
  [1]
