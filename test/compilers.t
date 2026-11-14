The same programs give the same output under gcc and clang, so nothing
depends on an order the C compiler is free to choose. This test only runs
when both compilers are installed.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

  $ cat > order.slick <<'EOF'
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
  > add :: fn(a, b: i32) -> i32 { return a + b; }
  > f :: fn(a, b, c: i32) -> i32 { return a * 100 + b * 10 + c; }
  > keep_going :: fn(i: i32) -> bool {
  >     print(i);
  >     return i < 2;
  > }
  > main :: fn() {
  >     print(add(noisy(1), noisy(2)));
  >     print(noisy(3) + noisy(4) * noisy(5));
  >     print(f(noisy(6), add(noisy(7), noisy(8)), noisy(9)));
  >     if false && yes(10) { print(0); }
  >     if yes(11) && no(12) && yes(13) { print(0); }
  >     if no(14) || yes(15) { print(16); }
  >     i : mut = 0;
  >     while keep_going(i) {
  >         i += 1;
  >         if i > 10 { return; }
  >     }
  >     if no(17) { print(0); } else if yes(18) { print(19); }
  > }
  > EOF

  $ CC=gcc slick run order.slick > gcc.out
  $ CC=clang slick run order.slick > clang.out
  $ diff gcc.out clang.out
  $ cat gcc.out
  1
  2
  3
  3
  4
  5
  23
  6
  7
  8
  9
  759
  11
  12
  14
  15
  16
  0
  1
  2
  17
  18
  19

  $ CC=gcc slick run ../examples/fib.slick > gcc_fib.out
  $ CC=clang slick run ../examples/fib.slick > clang_fib.out
  $ diff gcc_fib.out clang_fib.out
  $ paste -s -d ' ' gcc_fib.out
  0 1 1 2 3 5 8 13 21 34
