The float types f32 and f64.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

Float literals: digits on both sides of the point, an optional exponent, and
'_' separators. Without context a float literal is an f32.

  $ cat > literals.slick <<'EOF'
  > main :: fn() {
  >     print(1.5);
  >     print(-2.25);
  >     print(1e3);
  >     print(2.5e-3);
  >     print(1_000.5);
  >     a : f64 = 0.1;
  >     print(a);
  >     b := 0.1;
  >     print(b);
  > }
  > EOF
  $ slick run literals.slick
  1.5
  -2.25
  1000.0
  0.0025
  1000.5
  0.1
  0.1

print shows the shortest text that reads back as the same value. Whole
numbers get '.0', and very large or small values use an exponent.

  $ cat > printing.slick <<'EOF'
  > main :: fn() {
  >     third : f32 = 1.0 / 3.0;
  >     print(third);
  >     third64 : f64 = 1.0 / 3.0;
  >     print(third64);
  >     print(100.0);
  >     print(0.0);
  >     print(-0.0);
  >     print(1e20);
  >     print(1e-5);
  >     print(0.0001);
  >     big : f64 = 1e300;
  >     print(big * big);
  >     print(-big * big);
  >     zero : f64 = 0.0;
  >     print(zero / zero);
  > }
  > EOF
  $ slick run printing.slick
  0.33333334
  0.3333333333333333
  100.0
  0.0
  -0.0
  1e+20
  1e-05
  0.0001
  inf
  -inf
  nan

A second argument to print is the number of digits after the point.

  $ cat > precision.slick <<'EOF'
  > main :: fn() {
  >     x : f64 = 3.14159;
  >     print(x, 2);
  >     print(x, 0);
  >     print(1.0, 3);
  >     n := 4;
  >     print(x, n);
  > }
  > EOF
  $ slick run precision.slick
  3.14
  3
  1.000
  3.1416

A negative precision computed at run time panics.

  $ cat > precision_panic.slick <<'EOF'
  > main :: fn() {
  >     n := 0 - 1;
  >     print(1.5, n);
  > }
  > EOF
  $ slick run precision_panic.slick
  Panic: Precision cannot be negative
   --> precision_panic.slick:3:16
    |
  3 |     print(1.5, n);
    |                ^ This is negative
  [1]

Integer literals can take a float type. f32 widens to f64 implicitly; integers
and floats need a cast.

  $ cat > conversions.slick <<'EOF'
  > half :: fn(x: f64) -> f64 { return x / 2; }
  > main :: fn() {
  >     health : f32 = 100;
  >     print(health);
  >     print(half(health));
  >     print(half(3));
  >     n : i32 = 7;
  >     print(cast(f32, n) / 2);
  >     print(cast(i32, 3.99));
  >     print(cast(i32, -3.99));
  >     print(cast(u8, 300.0));
  >     print(cast(u8, -5.0));
  >     print(cast(i64, 1e30));
  >     zero : f32 = 0.0;
  >     print(cast(i32, zero / zero));
  >     print(cast(f32, 0.1));
  >     print(bitcast(u32, 1.0));
  >     print(bitcast(u64, 1.0));
  >     print(bitcast(f32, 1065353216));
  > }
  > EOF
  $ slick run conversions.slick
  100.0
  50.0
  1.5
  3.5
  3
  -3
  255
  0
  9223372036854775807
  0
  0.1
  1065353216
  4607182418800017408
  1.0

Dividing a float by zero gives an infinity rather than a panic.

  $ cat > divzero.slick <<'EOF'
  > main :: fn() {
  >     zero : f32 = 0.0;
  >     print(1.0 / zero);
  > }
  > EOF
  $ slick run divzero.slick
  inf

Errors: integers and floats do not mix, % does not work on floats, f64 does not
narrow to f32 implicitly, a float literal cannot be an integer, and a literal
must fit its type.

  $ cat > errors.slick <<'EOF'
  > main :: fn() {
  >     n : i32 = 1;
  >     x : f32 = 1.5;
  >     a := n + x;
  >     b := x % 2.0;
  >     d : f64 = 2.5;
  >     e : f32 = d;
  >     f : i32 = 2.5;
  >     g : f32 = 1e39;
  >     h : f32 = n;
  > }
  > EOF
  $ slick run errors.slick
  Error: Mismatched types in '+': i32 and f32
   --> errors.slick:4:14
    |
  4 |     a := n + x;
    |          - This is i32
    |              ^ This is f32
    |
  Note: Integers and floats do not convert implicitly
  Help: Convert one side explicitly
    |
  4 |     a := cast(f32, n) + x;
    |          ++++++++++ +
  
  Error: Operator '%' does not work on floats
   --> errors.slick:5:12
    |
  5 |     b := x % 2.0;
    |          - This is f32
    |            ^
    |
  Note: Float remainder is not supported yet
  
  Error: Cannot initialize 'e' of type f32 with a value of type f64
   --> errors.slick:7:15
    |
  7 |     e : f32 = d;
    |         --- Declared as f32 here
    |               ^ This is f64
    |
  Note: Converting f64 to f32 could lose precision
  Help: Convert it explicitly
    |
  7 |     e : f32 = cast(f32, d);
    |               ++++++++++ +
  
  Error: Cannot initialize 'f' of type i32 with a value of type f32
   --> errors.slick:8:15
    |
  8 |     f : i32 = 2.5;
    |         --- Declared as i32 here
    |               ^^^ This is f32
    |
  Note: Integers and floats do not convert implicitly
  Help: Convert it explicitly
    |
  8 |     f : i32 = cast(i32, 2.5);
    |               ++++++++++   +
  
  Error: Float literal 1e39 does not fit in f32
   --> errors.slick:9:15
    |
  9 |     g : f32 = 1e39;
    |               ^^^^ Too large for f32
  
  Error: Cannot initialize 'h' of type f32 with a value of type i32
    --> errors.slick:10:15
     |
  10 |     h : f32 = n;
     |         --- Declared as f32 here
     |               ^ This is i32
     |
  Note: Integers and floats do not convert implicitly
  Help: Convert it explicitly
     |
  10 |     h : f32 = cast(f32, n);
     |               ++++++++++ +
  
  Error: Could not compile 'errors.slick' due to 6 errors
  [1]

A float literal takes its type from context, so there are no suffixes.

  $ cat > suffix.slick <<'EOF'
  > main :: fn() {
  >     i := 1.5f;
  > }
  > EOF
  $ slick run suffix.slick
  Error: Invalid float literal '1.5f'
   --> suffix.slick:2:10
    |
  2 |     i := 1.5f;
    |          ^^^^ Only digits, '.', '_' and an exponent are allowed
  
  Error: Could not compile 'suffix.slick' due to 1 error
  [1]
