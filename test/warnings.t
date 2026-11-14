Warnings. The only one so far is --warn-implicit-conversions.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

  $ cat > widen.slick <<'EOF'
  > take :: fn(x: i64) -> i64 { return x; }
  > give :: fn(x: i32) -> i64 { return x; }
  > V :: struct { big: i64 }
  > main :: fn() {
  >     a : i32 = 5;
  >     b : i64 = a;
  >     c : mut i64 = 0;
  >     c = a;
  >     print(take(a) + a);
  >     v := V{ big = a };
  >     h : f32 = 1.5;
  >     d : f64 = h;
  >     e : i64 = 7;
  >     print(give(2));
  > }
  > EOF

Without the flag, implicit widening is silent.

  $ slick run widen.slick
  10
  2

With it, every implicit conversion warns: in an initialization, an
assignment, an argument, an operand, a struct field, and a return. A literal
taking a type is not a conversion. The program still builds and runs, after
the warnings.

  $ slick run --warn-implicit-conversions widen.slick
  Warning: Implicit conversion from i32 to i64
   --> widen.slick:2:36
    |
  2 | give :: fn(x: i32) -> i64 { return x; }
    |                                    ^ Converted to i64
    |
  Note: Reported because of --warn-implicit-conversions
  Help: Write it explicitly
    |
  2 | give :: fn(x: i32) -> i64 { return cast(i64, x); }
    |                                    ++++++++++ +
  
  Warning: Implicit conversion from i32 to i64
   --> widen.slick:6:15
    |
  6 |     b : i64 = a;
    |               ^ Converted to i64
    |
  Note: Reported because of --warn-implicit-conversions
  Help: Write it explicitly
    |
  6 |     b : i64 = cast(i64, a);
    |               ++++++++++ +
  
  Warning: Implicit conversion from i32 to i64
   --> widen.slick:8:9
    |
  8 |     c = a;
    |         ^ Converted to i64
    |
  Note: Reported because of --warn-implicit-conversions
  Help: Write it explicitly
    |
  8 |     c = cast(i64, a);
    |         ++++++++++ +
  
  Warning: Implicit conversion from i32 to i64
   --> widen.slick:9:16
    |
  9 |     print(take(a) + a);
    |                ^ Converted to i64
    |
  Note: Reported because of --warn-implicit-conversions
  Help: Write it explicitly
    |
  9 |     print(take(cast(i64, a)) + a);
    |                ++++++++++ +
  
  Warning: Implicit conversion from i32 to i64
   --> widen.slick:9:21
    |
  9 |     print(take(a) + a);
    |                     ^ Converted to i64
    |
  Note: Reported because of --warn-implicit-conversions
  Help: Write it explicitly
    |
  9 |     print(take(a) + cast(i64, a));
    |                     ++++++++++ +
  
  Warning: Implicit conversion from i32 to i64
    --> widen.slick:10:19
     |
  10 |     v := V{ big = a };
     |                   ^ Converted to i64
     |
  Note: Reported because of --warn-implicit-conversions
  Help: Write it explicitly
     |
  10 |     v := V{ big = cast(i64, a) };
     |                   ++++++++++ +
  
  Warning: Implicit conversion from f32 to f64
    --> widen.slick:12:15
     |
  12 |     d : f64 = h;
     |               ^ Converted to f64
     |
  Note: Reported because of --warn-implicit-conversions
  Help: Write it explicitly
     |
  12 |     d : f64 = cast(f64, h);
     |               ++++++++++ +
  
  Warning: 'widen.slick' generated 7 warnings
  10
  2

--warnings-as-errors turns them into errors, which stop the build.

  $ slick run --warn-implicit-conversions --warnings-as-errors widen.slick
  Error: Implicit conversion from i32 to i64
   --> widen.slick:2:36
    |
  2 | give :: fn(x: i32) -> i64 { return x; }
    |                                    ^ Converted to i64
    |
  Note: Reported because of --warn-implicit-conversions
  Note: Reported as an error because of --warnings-as-errors
  Help: Write it explicitly
    |
  2 | give :: fn(x: i32) -> i64 { return cast(i64, x); }
    |                                    ++++++++++ +
  
  Error: Implicit conversion from i32 to i64
   --> widen.slick:6:15
    |
  6 |     b : i64 = a;
    |               ^ Converted to i64
    |
  Note: Reported because of --warn-implicit-conversions
  Note: Reported as an error because of --warnings-as-errors
  Help: Write it explicitly
    |
  6 |     b : i64 = cast(i64, a);
    |               ++++++++++ +
  
  Error: Implicit conversion from i32 to i64
   --> widen.slick:8:9
    |
  8 |     c = a;
    |         ^ Converted to i64
    |
  Note: Reported because of --warn-implicit-conversions
  Note: Reported as an error because of --warnings-as-errors
  Help: Write it explicitly
    |
  8 |     c = cast(i64, a);
    |         ++++++++++ +
  
  Error: Implicit conversion from i32 to i64
   --> widen.slick:9:16
    |
  9 |     print(take(a) + a);
    |                ^ Converted to i64
    |
  Note: Reported because of --warn-implicit-conversions
  Note: Reported as an error because of --warnings-as-errors
  Help: Write it explicitly
    |
  9 |     print(take(cast(i64, a)) + a);
    |                ++++++++++ +
  
  Error: Implicit conversion from i32 to i64
   --> widen.slick:9:21
    |
  9 |     print(take(a) + a);
    |                     ^ Converted to i64
    |
  Note: Reported because of --warn-implicit-conversions
  Note: Reported as an error because of --warnings-as-errors
  Help: Write it explicitly
    |
  9 |     print(take(a) + cast(i64, a));
    |                     ++++++++++ +
  
  Error: Implicit conversion from i32 to i64
    --> widen.slick:10:19
     |
  10 |     v := V{ big = a };
     |                   ^ Converted to i64
     |
  Note: Reported because of --warn-implicit-conversions
  Note: Reported as an error because of --warnings-as-errors
  Help: Write it explicitly
     |
  10 |     v := V{ big = cast(i64, a) };
     |                   ++++++++++ +
  
  Error: Implicit conversion from f32 to f64
    --> widen.slick:12:15
     |
  12 |     d : f64 = h;
     |               ^ Converted to f64
     |
  Note: Reported because of --warn-implicit-conversions
  Note: Reported as an error because of --warnings-as-errors
  Help: Write it explicitly
     |
  12 |     d : f64 = cast(f64, h);
     |               ++++++++++ +
  
  Error: Could not compile 'widen.slick' due to 7 errors
  [1]

Warnings and errors together: the summary counts both.

  $ cat > both.slick <<'EOF'
  > main :: fn() {
  >     a : i32 = 5;
  >     b : i64 = a;
  >     c : i16 = a;
  > }
  > EOF
  $ slick run --warn-implicit-conversions both.slick
  Warning: Implicit conversion from i32 to i64
   --> both.slick:3:15
    |
  3 |     b : i64 = a;
    |               ^ Converted to i64
    |
  Note: Reported because of --warn-implicit-conversions
  Help: Write it explicitly
    |
  3 |     b : i64 = cast(i64, a);
    |               ++++++++++ +
  
  Error: Cannot initialize 'c' of type i16 with a value of type i32
   --> both.slick:4:15
    |
  4 |     c : i16 = a;
    |         --- Declared as i16 here
    |               ^ This is i32
    |
  Note: Converting i32 to i16 could lose information
  Help: Convert it explicitly
    |
  4 |     c : i16 = cast(i16, a);
    |               ++++++++++ +
  
  Error: Could not compile 'both.slick' due to 1 error; 1 warning emitted
  [1]

Warnings are yellow in color, including the underline.

  $ cat > one.slick <<'EOF'
  > main :: fn() {
  >     a : u8 = 1;
  >     b : u16 = a;
  > }
  > EOF
  $ slick build --warn-implicit-conversions --color=always one.slick 2>&1 | sed -n '1,5p;$p' | cat -v
  ^[[1;33mWarning^[[0m^[[1m: Implicit conversion from u8 to u16^[[0m
   ^[[1;34m-->^[[0m one.slick:3:15
  ^[[1;34m  |^[[0m
  ^[[1;34m3 |^[[0m     b : u16 = a;
  ^[[1;34m  |^[[0m               ^[[1;33m^ Converted to u16^[[0m
  ^[[1;33mWarning^[[0m^[[1m: 'one.slick' generated 1 warning^[[0m

With the flag but nothing to warn about, nothing is printed.

  $ cat > clean.slick <<'EOF'
  > main :: fn() {
  >     a : u16 = 1;
  >     b : u16 = a;
  > }
  > EOF
  $ slick build --warn-implicit-conversions clean.slick
