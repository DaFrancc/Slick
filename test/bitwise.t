Bitwise operators, with Go-style precedence.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

Each operator, and ~.

  $ cat > ops.slick <<'EOF'
  > main :: fn() {
  >     a : u8 = 0b1100;
  >     b : u8 = 0b1010;
  >     print(a & b);
  >     print(a | b);
  >     print(a ^ b);
  >     print(~a);
  >     print(a << 2);
  >     print(a >> 2);
  >     c : i32 = -1;
  >     print(~c);
  > }
  > EOF
  $ slick run ops.slick
  8
  14
  6
  243
  48
  3
  0

'&' binds like '*' and '|' like '+', both tighter than comparisons, so
'flags & 8 == 8' tests a bit. In C it would mean 'flags & (8 == 8)'.

  $ cat > precedence.slick <<'EOF'
  > main :: fn() {
  >     flags : u32 = 12;
  >     print(flags & 8 == 8);
  >     print(flags & 1 == 0);
  >     print(1 | 2 << 2);
  >     print(1 + 2 << 2);
  >     print(6 & 3 + 1);
  > }
  > EOF
  $ slick run precedence.slick
  true
  true
  9
  9
  3

A shift amount wraps modulo the width, the result has the left side's type,
and >> on a signed value keeps the sign. A negative value shifts left
without trouble.

  $ cat > shifts.slick <<'EOF'
  > main :: fn() {
  >     a : u8 = 1;
  >     n : i32 = 9;
  >     print(a << n);
  >     b : i64 = 1;
  >     print(b << 40);
  >     c : i32 = -16;
  >     print(c >> 2);
  >     print(c << 1);
  >     d : u32 = 0x80000000;
  >     print(d >> 31);
  >     e : i8 = -128;
  >     print(e >> 7);
  > }
  > EOF
  $ slick run shifts.slick
  2
  1099511627776
  -4
  -32
  1
  -1

Compound assignment.

  $ cat > compound.slick <<'EOF'
  > main :: fn() {
  >     x : mut u32 = 1;
  >     x <<= 4;
  >     print(x);
  >     x |= 3;
  >     print(x);
  >     x &= 6;
  >     print(x);
  >     x ^= 0xFF;
  >     print(x);
  >     x >>= 1;
  >     print(x);
  > }
  > EOF
  $ slick run compound.slick
  16
  19
  2
  253
  126

Mixed widths widen, as for arithmetic.

  $ cat > mixed.slick <<'EOF'
  > main :: fn() {
  >     a : u8 = 0xF0;
  >     b : u32 = 0xFF00;
  >     print(a | b);
  > }
  > EOF
  $ slick run mixed.slick
  65520

Errors: a literal shift amount that is too large or negative, bitwise
operators on bools or floats, and ~ on a bool.

  $ cat > errors.slick <<'EOF'
  > main :: fn() {
  >     a : i32 = 1;
  >     b := a << 32;
  >     c := a >> -1;
  >     d := true ^ false;
  >     e := 1.5 & 2.5;
  >     f := ~true;
  >     g : mut bool = true;
  >     g |= false;
  > }
  > EOF
  $ slick run errors.slick
  Error: Shift amount 32 is too large for i32
   --> errors.slick:3:15
    |
  3 |     b := a << 32;
    |               ^^ Too large
    |
  Note: An i32 can be shifted by 0 to 31
  
  Error: Shift amount cannot be negative
   --> errors.slick:4:15
    |
  4 |     c := a >> -1;
    |               ^^ Negative
  
  Error: Operator '^' does not work on bool
   --> errors.slick:5:15
    |
  5 |     d := true ^ false;
    |               ^
    |
  Help: To test whether they differ, use '!='
    |
  5 |     d := true != false;
    |               ~~
  
  Error: Operator '&' expects integers, found f32 and f32
   --> errors.slick:6:14
    |
  6 |     e := 1.5 & 2.5;
    |          --- f32
    |              ^
    |                --- f32
  
  Error: Operator '~' expects an integer, found bool
   --> errors.slick:7:10
    |
  7 |     f := ~true;
    |          ^
    |           ---- bool
    |
  Help: For a logical not, use '!'
    |
  7 |     f := !true;
    |          ~
  
  Error: Operator '|=' does not work on bool
   --> errors.slick:9:7
    |
  9 |     g |= false;
    |       ^^
    |
  Help: For a logical or, write 'g = g || false'
  
  Error: Could not compile 'errors.slick' due to 6 errors
  [1]
