The integer types, literals, conversions and casts. Every program's C is also
compiled with strict warnings.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

Each integer type holds its whole range, and print shows it.

  $ cat > ranges.slick <<'EOF'
  > main :: fn() {
  >     a : i8 = -128;    print(a);
  >     b : i8 = 127;     print(b);
  >     c : i16 = -32768; print(c);
  >     d : i16 = 32767;  print(d);
  >     e : i32 = -2147483648; print(e);
  >     f : i64 = -9223372036854775808; print(f);
  >     g : i64 = 9223372036854775807;  print(g);
  >     h : u8 = 255;     print(h);
  >     i : u16 = 65535;  print(i);
  >     j : u32 = 4294967295; print(j);
  >     k : u64 = 18446744073709551615; print(k);
  > }
  > EOF
  $ slick run ranges.slick
  -128
  127
  -32768
  32767
  -2147483648
  -9223372036854775808
  9223372036854775807
  255
  65535
  4294967295
  18446744073709551615

Arithmetic wraps around in every type, and the wrapped value is what later
operations see: the u8 sum 200 + 100 is 44, so it is not greater than 250.

  $ cat > wrap.slick <<'EOF'
  > main :: fn() {
  >     a : mut u8 = 250;
  >     a += 10;
  >     print(a);
  >     b : mut i8 = 127;
  >     b += 1;
  >     print(b);
  >     x : u8 = 200;
  >     y : u8 = 100;
  >     print(x + y > 250);
  >     z : mut u32 = 0;
  >     z -= 1;
  >     print(z);
  >     m : mut i64 = 9223372036854775807;
  >     m += 1;
  >     print(m);
  >     n : i16 = -32768;
  >     print(-n);
  >     p : u16 = 300;
  >     print(p * p);
  > }
  > EOF
  $ slick run wrap.slick
  4
  -128
  false
  4294967295
  -9223372036854775808
  -32768
  24464

A literal takes its type from context: an annotation, an assignment, a
parameter, a return type, or the other operand. With none, it is an i32.

  $ cat > adopt.slick <<'EOF'
  > big :: fn(x: u64) -> u64 { return x; }
  > small :: fn() -> u8 { return 255; }
  > main :: fn() {
  >     print(big(18446744073709551615));
  >     print(small());
  >     a : u8 = 7;
  >     print(a + 250);
  >     print(250 + a);
  >     b : mut i64 = 0;
  >     b = 5000000000;
  >     print(b);
  >     c := 5;
  >     d : i64 = 1 + 2;
  >     print(c);
  >     print(d);
  > }
  > EOF
  $ slick run adopt.slick
  18446744073709551615
  255
  1
  1
  5000000000
  5
  3

Hexadecimal and binary literals, with '_' separators.

  $ cat > bases.slick <<'EOF'
  > main :: fn() {
  >     print(0x10);
  >     print(0xff_ff);
  >     print(0b1010);
  >     print(1_000_000);
  >     a : u32 = 0xFFFF_FFFF;
  >     print(a);
  > }
  > EOF
  $ slick run bases.slick
  16
  65535
  10
  1000000
  4294967295

  $ cat > bad_hex.slick <<'EOF'
  > main :: fn() {
  >     a := 0xZ1;
  >     b := 0b102;
  >     c := 0x;
  > }
  > EOF
  $ slick run bad_hex.slick
  Error: Invalid integer literal '0xZ1'
   --> bad_hex.slick:2:10
    |
  2 |     a := 0xZ1;
    |          ^^^^ Only hexadecimal digits and '_' are allowed
  
  Error: Invalid integer literal '0b102'
   --> bad_hex.slick:3:10
    |
  3 |     b := 0b102;
    |          ^^^^^ Only 0, 1 and '_' are allowed
  
  Error: Invalid integer literal '0x'
   --> bad_hex.slick:4:10
    |
  4 |     c := 0x;
    |          ^^ Only hexadecimal digits and '_' are allowed
  
  Error: Could not compile 'bad_hex.slick' due to 3 errors
  [1]

A literal must fit its type.

  $ cat > range_errors.slick <<'EOF'
  > main :: fn() {
  >     a : u8 = 256;
  >     b : u32 = -1;
  >     c : i8 = -129;
  >     d : i64 = 9223372036854775808;
  > }
  > EOF
  $ slick run range_errors.slick
  Error: Integer literal 256 does not fit in u8
   --> range_errors.slick:2:14
    |
  2 |     a : u8 = 256;
    |              ^^^ Too large for u8
    |
  Note: A u8 holds values from 0 to 255
  
  Error: Integer literal -1 does not fit in u32
   --> range_errors.slick:3:15
    |
  3 |     b : u32 = -1;
    |               ^^ u32 cannot be negative
    |
  Note: A u32 holds values from 0 to 4294967295
  
  Error: Integer literal -129 does not fit in i8
   --> range_errors.slick:4:14
    |
  4 |     c : i8 = -129;
    |              ^^^^ Too small for i8
    |
  Note: An i8 holds values from -128 to 127
  
  Error: Integer literal 9223372036854775808 does not fit in i64
   --> range_errors.slick:5:15
    |
  5 |     d : i64 = 9223372036854775808;
    |               ^^^^^^^^^^^^^^^^^^^ Too large for i64
    |
  Note: An i64 holds values from -9223372036854775808 to 9223372036854775807
  
  Error: Could not compile 'range_errors.slick' due to 4 errors
  [1]

A literal too large for the default i32 gets a help to give it a larger type.

  $ cat > default_big.slick <<'EOF'
  > main :: fn() {
  >     a := 3000000000;
  >     b := 10000000000000000000;
  >     print(a);
  >     print(b);
  > }
  > EOF
  $ slick run default_big.slick
  Error: Integer literal 3000000000 does not fit in i32
   --> default_big.slick:2:10
    |
  2 |     a := 3000000000;
    |          ^^^^^^^^^^ Too large for i32
    |
  Note: An i32 holds values from -2147483648 to 2147483647
  Help: Give it a larger type
    |
  2 |     a : i64 = 3000000000;
    |       ~~~~~~~
  
  Error: Integer literal 10000000000000000000 does not fit in i32
   --> default_big.slick:3:10
    |
  3 |     b := 10000000000000000000;
    |          ^^^^^^^^^^^^^^^^^^^^ Too large for i32
    |
  Note: An i32 holds values from -2147483648 to 2147483647
  Help: Give it a larger type
    |
  3 |     b : u64 = 10000000000000000000;
    |       ~~~~~~~
  
  Error: Could not compile 'default_big.slick' due to 2 errors
  [1]

Narrower values widen implicitly when nothing can be lost: to a larger type
of the same signedness, or from unsigned to a larger signed type.

  $ cat > widen.slick <<'EOF'
  > take :: fn(x: i64) -> i64 { return x; }
  > give :: fn(x: u8) -> u32 { return x; }
  > main :: fn() {
  >     a : i32 = -5;
  >     b : i64 = a;
  >     print(b);
  >     print(take(a));
  >     print(give(200));
  >     c : u16 = 60000;
  >     d : i32 = c;
  >     print(d);
  >     e : mut i64 = 1;
  >     e = a;
  >     print(e);
  >     print(a + b);
  >     print(c < d);
  > }
  > EOF
  $ slick run widen.slick
  -5
  -5
  200
  60000
  -5
  -10
  false

Anything that could lose information needs a cast.

  $ cat > narrow.slick <<'EOF'
  > main :: fn() {
  >     a : i32 = 5;
  >     b : i16 = a;
  >     c : u32 = a;
  >     d : u64 = 1;
  >     e : i64 = d;
  > }
  > EOF
  $ slick run narrow.slick
  Error: Cannot initialize 'b' of type i16 with a value of type i32
   --> narrow.slick:3:15
    |
  3 |     b : i16 = a;
    |         --- Declared as i16 here
    |               ^ This is i32
    |
  Note: Converting i32 to i16 could lose information
  Help: Convert it explicitly
    |
  3 |     b : i16 = cast(i16, a);
    |               ++++++++++ +
  
  Error: Cannot initialize 'c' of type u32 with a value of type i32
   --> narrow.slick:4:15
    |
  4 |     c : u32 = a;
    |         --- Declared as u32 here
    |               ^ This is i32
    |
  Note: Converting i32 to u32 could lose the sign
  Help: Convert it explicitly
    |
  4 |     c : u32 = cast(u32, a);
    |               ++++++++++ +
  
  Error: Cannot initialize 'e' of type i64 with a value of type u64
   --> narrow.slick:6:15
    |
  6 |     e : i64 = d;
    |         --- Declared as i64 here
    |               ^ This is u64
    |
  Note: Converting u64 to i64 could lose information
  Help: Convert it explicitly
    |
  6 |     e : i64 = cast(i64, d);
    |               ++++++++++ +
  
  Error: Could not compile 'narrow.slick' due to 3 errors
  [1]

Two operands with no lossless common type are an error.

  $ cat > mixed.slick <<'EOF'
  > main :: fn() {
  >     a : u32 = 1;
  >     b : i32 = 2;
  >     c := a + b;
  >     d := a < b;
  > }
  > EOF
  $ slick run mixed.slick
  Error: Mismatched types in '+': u32 and i32
   --> mixed.slick:4:14
    |
  4 |     c := a + b;
    |          - This is u32
    |              ^ This is i32
    |
  Note: Neither type converts to the other without losing information
  Help: Convert one side explicitly
    |
  4 |     c := a + cast(u32, b);
    |              ++++++++++ +
  
  Error: Mismatched types in '<': u32 and i32
   --> mixed.slick:5:14
    |
  5 |     d := a < b;
    |          - This is u32
    |              ^ This is i32
    |
  Note: Neither type converts to the other without losing information
  Help: Convert one side explicitly
    |
  5 |     d := a < cast(u32, b);
    |              ++++++++++ +
  
  Error: Could not compile 'mixed.slick' due to 2 errors
  [1]

cast converts between integer types, wrapping. bitcast reinterprets bits
between types of the same size.

  $ cat > casts.slick <<'EOF'
  > main :: fn() {
  >     a : i32 = -1;
  >     print(cast(u8, a));
  >     print(cast(u32, a));
  >     print(cast(i64, a));
  >     b : u64 = 18446744073709551615;
  >     print(cast(i64, b));
  >     c : i32 = 70000;
  >     print(cast(i16, c));
  >     print(bitcast(u32, a));
  >     print(bitcast(i8, cast(u8, 200)));
  > }
  > EOF
  $ slick run casts.slick
  255
  4294967295
  -1
  -1
  4464
  4294967295
  -56

A literal inside a cast takes the cast's type, so it must fit it.

  $ cat > cast_literal.slick <<'EOF'
  > main :: fn() {
  >     print(cast(i16, 70000));
  > }
  > EOF
  $ slick run cast_literal.slick
  Error: Integer literal 70000 does not fit in i16
   --> cast_literal.slick:2:21
    |
  2 |     print(cast(i16, 70000));
    |                     ^^^^^ Too large for i16
    |
  Note: An i16 holds values from -32768 to 32767
  
  Error: Could not compile 'cast_literal.slick' due to 1 error
  [1]

  $ cat > cast_errors.slick <<'EOF'
  > main :: fn() {
  >     a := cast(i32, true);
  >     b := cast(bool, 1);
  >     c : i64 = 1;
  >     d := bitcast(i32, c);
  >     e := cast(Foo, 1);
  > }
  > EOF
  $ slick run cast_errors.slick
  Error: Cannot cast from bool to i32
   --> cast_errors.slick:2:20
    |
  2 |     a := cast(i32, true);
    |                    ^^^^ This is bool
    |
  Note: 'cast' converts between number types
  
  Error: Cannot cast from i32 to bool
   --> cast_errors.slick:3:21
    |
  3 |     b := cast(bool, 1);
    |                     ^ This is i32
    |
  Note: 'cast' converts between number types
  
  Error: Cannot bitcast from i64 to i32: they differ in size
   --> cast_errors.slick:5:23
    |
  5 |     d := bitcast(i32, c);
    |                       ^ This is 8 bytes
    |
  Note: i32 is 4 bytes
  Help: To convert the value, use 'cast'
    |
  5 |     d := cast(i32, c);
    |          ~~~~
  
  Error: Unknown type 'Foo'
   --> cast_errors.slick:6:15
    |
  6 |     e := cast(Foo, 1);
    |               ^^^ Not a type
    |
  Note: The built-in types are i8, i16, i32, i64, u8, u16, u32, u64, f32, f64, bool and cstring
  
  Error: Could not compile 'cast_errors.slick' due to 4 errors
  [1]

Unary minus needs a signed type.

  $ cat > neg_unsigned.slick <<'EOF'
  > main :: fn() {
  >     a : u32 = 5;
  >     b := -a;
  > }
  > EOF
  $ slick run neg_unsigned.slick
  Error: Cannot negate a value of type u32
   --> neg_unsigned.slick:3:11
    |
  3 |     b := -a;
    |           ^ This is u32
    |
  Note: u32 has no negative values; '0 - a' wraps around
  
  Error: Could not compile 'neg_unsigned.slick' due to 1 error
  [1]

Division truncates toward zero in every type. Dividing the minimum by -1
wraps instead of trapping, and dividing by zero panics.

  $ cat > division.slick <<'EOF'
  > main :: fn() {
  >     a : i8 = -7;
  >     print(a / 2);
  >     print(a % 2);
  >     b : u8 = 255;
  >     print(b / 2);
  >     m : i64 = -9223372036854775808;
  >     print(m / -1);
  >     print(m % -1);
  >     n : i8 = -128;
  >     print(n / -1);
  >     z : u8 = 0;
  >     print(b / z);
  > }
  > EOF
  $ slick run division.slick
  -3
  -1
  127
  -9223372036854775808
  0
  -128
  Panic: Division by zero
    --> division.slick:13:15
     |
  13 |     print(b / z);
     |               ^ This is zero
  [1]

The types are names like any other, so they cannot be declared again.

  $ cat > type_names.slick <<'EOF'
  > i32 :: fn() { }
  > main :: fn() {
  >     u8 := 1;
  >     x := i64;
  > }
  > EOF
  $ slick run type_names.slick
  Error: 'i32' is a built-in type and cannot be redeclared
   --> type_names.slick:1:1
    |
  1 | i32 :: fn() { }
    | ^^^
    |
  Help: Choose a different name
  
  Error: 'u8' is a built-in type and cannot be redeclared
   --> type_names.slick:3:5
    |
  3 |     u8 := 1;
    |     ^^
    |
  Help: Choose a different name
  
  Error: 'i64' is a type, not a value
   --> type_names.slick:4:10
    |
  4 |     x := i64;
    |          ^^^
  
  Error: Could not compile 'type_names.slick' due to 3 errors
  [1]

Common names from other languages get a suggestion.

  $ cat > type_suggest.slick <<'EOF'
  > main :: fn() {
  >     a : int = 1;
  >     b : double = 1.0;
  >     c : byte = 1;
  >     d : i23 = 1;
  > }
  > EOF
  $ slick run type_suggest.slick
  Error: Unknown type 'int'
   --> type_suggest.slick:2:9
    |
  2 |     a : int = 1;
    |         ^^^ Not a type
    |
  Help: Did you mean 'i32'?
    |
  2 |     a : i32 = 1;
    |         ~~~
  
  Error: Unknown type 'double'
   --> type_suggest.slick:3:9
    |
  3 |     b : double = 1.0;
    |         ^^^^^^ Not a type
    |
  Help: Did you mean 'f64'?
    |
  3 |     b : f64 = 1.0;
    |         ~~~
  
  Error: Unknown type 'byte'
   --> type_suggest.slick:4:9
    |
  4 |     c : byte = 1;
    |         ^^^^ Not a type
    |
  Help: Did you mean 'u8'?
    |
  4 |     c : u8 = 1;
    |         ~~
  
  Error: Unknown type 'i23'
   --> type_suggest.slick:5:9
    |
  5 |     d : i23 = 1;
    |         ^^^ Not a type
    |
  Help: Did you mean 'i32'?
    |
  5 |     d : i32 = 1;
    |         ~~~
  
  Error: Could not compile 'type_suggest.slick' due to 4 errors
  [1]
