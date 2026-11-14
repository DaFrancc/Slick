Stage 6: evaluation is strictly left to right, for call arguments and for
operands, whatever order the C compiler would pick. noisy prints its argument
and returns it, so the output shows the order.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

  $ cat > helpers.slick <<'EOF'
  > noisy :: fn(n: i32) -> i32 {
  >     print(n);
  >     return n;
  > }
  > yes :: fn(n: i32) -> bool {
  >     print(n);
  >     return true;
  > }
  > no :: fn(n: i32) -> bool {
  >     print(n);
  >     return false;
  > }
  > zero :: fn() -> i32 {
  >     print(0);
  >     return 0;
  > }
  > add :: fn(a, b: i32) -> i32 { return a + b; }
  > EOF

Arguments are evaluated left to right.

  $ cat helpers.slick - > args.slick <<'EOF'
  > main :: fn() { print(add(noisy(1), noisy(2))); }
  > EOF
  $ slick run args.slick
  1
  2
  3

Operands are evaluated left to right, whatever the precedence.

  $ cat helpers.slick - > operands.slick <<'EOF'
  > main :: fn() {
  >     print(noisy(1) + noisy(2) * noisy(3));
  >     print(noisy(4) - noisy(5));
  > }
  > EOF
  $ slick run operands.slick
  1
  2
  3
  7
  4
  5
  -1

Nested calls.

  $ cat helpers.slick - > nested.slick <<'EOF'
  > f :: fn(a, b, c: i32) -> i32 { return a * 100 + b * 10 + c; }
  > main :: fn() {
  >     print(f(noisy(1), add(noisy(2), noisy(3)), noisy(4)));
  > }
  > EOF
  $ slick run nested.slick
  1
  2
  3
  4
  154

Declarations, assignments and returns.

  $ cat helpers.slick - > statements.slick <<'EOF'
  > pair :: fn() -> i32 { return noisy(5) * 10 + noisy(6); }
  > main :: fn() {
  >     a := noisy(1) * 10 + noisy(2);
  >     b : mut = 0;
  >     b = noisy(3) - noisy(4);
  >     b += noisy(7);
  >     print(a);
  >     print(b);
  >     print(pair());
  > }
  > EOF
  $ slick run statements.slick
  1
  2
  3
  4
  7
  12
  6
  5
  6
  56

A division that panics stops the program before later operands run.

  $ cat helpers.slick - > div_order.slick <<'EOF'
  > main :: fn() {
  >     print(10 / zero() + noisy(5));
  > }
  > EOF
  $ slick run div_order.slick
  0
  div_order.slick:19: panic: division by zero
  [1]

&& and || skip their right side when the left decides the result, including
when the right side has calls.

  $ cat helpers.slick - > short.slick <<'EOF'
  > main :: fn() {
  >     if false && yes(1) { print(10); } else { print(11); }
  >     if true && yes(2) { print(20); }
  >     if true || yes(3) { print(30); }
  >     if false || yes(4) { print(40); }
  >     if yes(5) && no(6) && yes(7) { print(50); } else { print(51); }
  >     if no(8) || no(9) || yes(10) { print(60); }
  >     ok := no(12) && yes(13);
  >     if !ok { print(70); }
  > }
  > EOF
  $ slick run short.slick
  11
  2
  20
  30
  4
  40
  5
  6
  51
  8
  9
  10
  60
  12
  70

A guard with && protects a division on its right.

  $ cat > guard.slick <<'EOF'
  > main :: fn() {
  >     x := 0;
  >     if x != 0 && 10 / x > 1 { print(1); } else { print(0); }
  > }
  > EOF
  $ slick run guard.slick
  0

A while condition with a call runs before every iteration, not just once.

  $ cat > while_call.slick <<'EOF'
  > keep_going :: fn(i: i32) -> bool {
  >     print(i);
  >     return i < 3;
  > }
  > main :: fn() {
  >     i : mut = 0;
  >     while keep_going(i) {
  >         i += 1;
  >         if i > 10 { return; }
  >     }
  >     print(100);
  > }
  > EOF
  $ slick run while_call.slick
  0
  1
  2
  3
  100

An else-if condition only runs when the branches before it were not taken.

  $ cat helpers.slick - > else_if.slick <<'EOF'
  > main :: fn() {
  >     if yes(1) { print(10); } else if yes(2) { print(20); }
  >     if no(3) { print(30); } else if yes(4) { print(40); } else { print(50); }
  >     if no(5) { print(60); } else if no(6) { print(70); } else if yes(7) { print(80); }
  > }
  > EOF
  $ slick run else_if.slick
  1
  10
  3
  4
  40
  5
  6
  7
  80
