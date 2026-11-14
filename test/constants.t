Constants: top-level names for values known at compile time. Each has one
fixed type, inferred like a variable's or written out.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

The type is inferred as for ':=', or written between the colons. A constant
can use other constants, including ones declared later.

  $ cat > basics.slick <<'EOF'
  > Color :: struct { r, g, b, a: u8 }
  > HALF_W   :: SCREEN_W / 2;
  > SCREEN_W :: 800;
  > SPEED    : f32 : 400;
  > SMALL    : u8 : 200;
  > BIG      : i64 : 5000000000;
  > DEBUG    :: false;
  > TITLE    :: "Pong";
  > RAYWHITE :: Color{ 245, 245, 245, 255 };
  > BLACK    : Color : .{ a = 255 };
  > MASK     :: 1 << 4 | 1;
  > main :: fn() {
  >     print(SCREEN_W);
  >     print(HALF_W);
  >     print(SPEED);
  >     print(SMALL + 55);
  >     print(BIG);
  >     print(DEBUG);
  >     print(TITLE);
  >     print(RAYWHITE.g);
  >     print(BLACK.a);
  >     print(MASK);
  > }
  > EOF
  $ slick run basics.slick
  800
  400
  400.0
  255
  5000000000
  false
  Pong
  245
  255
  17

A constant widens like any value of its type, and narrowing or turning an
integer into a float needs a cast, as for a variable.

  $ cat > widening.slick <<'EOF'
  > MAX :: 1024;
  > take :: fn(x: i64) -> i64 { return x; }
  > main :: fn() {
  >     a : i64 = MAX;
  >     print(take(MAX));
  >     b : f32 = cast(f32, MAX);
  >     print(a + MAX);
  >     print(b);
  > }
  > EOF
  $ slick run widening.slick
  1024
  2048
  1024.0

  $ cat > narrowing.slick <<'EOF'
  > MAX :: 1024;
  > main :: fn() {
  >     a : f32 = MAX;
  >     b : u8 = MAX;
  > }
  > EOF
  $ slick run narrowing.slick
  Error: Cannot initialize 'a' of type f32 with a value of type i32
   --> narrowing.slick:3:15
    |
  3 |     a : f32 = MAX;
    |         --- Declared as f32 here
    |               ^^^ This is i32
    |
  Note: Integers and floats do not convert implicitly
  Help: Convert it explicitly
    |
  3 |     a : f32 = cast(f32, MAX);
    |               ++++++++++   +
  
  Error: Cannot initialize 'b' of type u8 with a value of type i32
   --> narrowing.slick:4:14
    |
  4 |     b : u8 = MAX;
    |         -- Declared as u8 here
    |              ^^^ This is i32
    |
  Note: Converting i32 to u8 could lose the sign
  Help: Convert it explicitly
    |
  4 |     b : u8 = cast(u8, MAX);
    |              +++++++++   +
  
  Error: Could not compile 'narrowing.slick' due to 2 errors
  [1]

A written type is checked against the value.

  $ cat > typed_errors.slick <<'EOF'
  > A : u8 : 300;
  > B : bool : 1;
  > C : i32 : 1.5;
  > main :: fn() { }
  > EOF
  $ slick run typed_errors.slick
  Error: Integer literal 300 does not fit in u8
   --> typed_errors.slick:1:10
    |
  1 | A : u8 : 300;
    |          ^^^ Too large for u8
    |
  Note: A u8 holds values from 0 to 255
  
  Error: Constant 'B' of type bool cannot hold a value of type i32
   --> typed_errors.slick:2:12
    |
  2 | B : bool : 1;
    |     ---- Declared as bool here
    |            ^ This is i32
  
  Error: Constant 'C' of type i32 cannot hold a value of type f32
   --> typed_errors.slick:3:11
    |
  3 | C : i32 : 1.5;
    |     --- Declared as i32 here
    |           ^^^ This is f32
    |
  Note: Integers and floats do not convert implicitly
  Help: Convert it explicitly
    |
  3 | C : i32 : cast(i32, 1.5);
    |           ++++++++++   +
  
  Error: Could not compile 'typed_errors.slick' due to 3 errors
  [1]

A constant's value must be known at compile time.

  $ cat > not_constant.slick <<'EOF'
  > two :: fn() -> i32 { return 2; }
  > A :: two();
  > B :: 1 + two();
  > main :: fn() { }
  > EOF
  $ slick run not_constant.slick
  Error: A constant's value must be known at compile time
   --> not_constant.slick:2:6
    |
  2 | A :: two();
    |      ^^^^^ This is a function call
  
  Error: A constant's value must be known at compile time
   --> not_constant.slick:3:10
    |
  3 | B :: 1 + two();
    |          ^^^^^ This is a function call
  
  Error: Could not compile 'not_constant.slick' due to 2 errors
  [1]

A constant that depends on itself is reported once.

  $ cat > cycle.slick <<'EOF'
  > A :: B + 1;
  > B :: A * 2;
  > C :: C;
  > main :: fn() {
  >     print(A);
  > }
  > EOF
  $ slick run cycle.slick
  Error: Constant 'A' depends on itself
   --> cycle.slick:2:6
    |
  1 | A :: B + 1;
    | - Defined here
  2 | B :: A * 2;
    |      ^ Used here, inside its own value
  
  Error: Constant 'C' depends on itself
   --> cycle.slick:3:6
    |
  3 | C :: C;
    | - Defined here
    |      ^ Used here, inside its own value
  
  Error: Could not compile 'cycle.slick' due to 2 errors
  [1]

A constant is a value, not a place in memory: it cannot be assigned to or
pointed to.

  $ cat > places.slick <<'EOF'
  > V :: struct { x: i32 }
  > MAX :: 10;
  > ORIGIN :: V{ x = 0 };
  > main :: fn() {
  >     MAX = 5;
  >     ORIGIN.x = 1;
  >     p := &MAX;
  > }
  > EOF
  $ slick run places.slick
  Error: Cannot assign to constant 'MAX'
   --> places.slick:5:5
    |
  2 | MAX :: 10;
    | --- Constant defined here
  ...
  5 |     MAX = 5;
    |     ^^^ Cannot assign
  
  Error: Cannot assign to 'ORIGIN.x': 'ORIGIN' is a constant
   --> places.slick:6:5
    |
  3 | ORIGIN :: V{ x = 0 };
    | ------ Constant defined here
  ...
  6 |     ORIGIN.x = 1;
    |     ^^^^^^^^ Cannot assign
  
  Error: Cannot take the address of constant 'MAX'
   --> places.slick:7:11
    |
  2 | MAX :: 10;
    | --- Constant defined here
  ...
  7 |     p := &MAX;
    |           ^^^ A constant is not stored anywhere
    |
  Help: Store it in a variable first
  
  Error: Could not compile 'places.slick' due to 3 errors
  [1]

Names: constants share the one namespace, so a constant cannot reuse a name,
and calling one is an error.

  $ cat > names.slick <<'EOF'
  > MAX :: 10;
  > MAX :: 20;
  > f :: fn() { }
  > f :: 1;
  > main :: fn() {
  >     MAX := 3;
  >     x := MAX();
  > }
  > EOF
  $ slick run names.slick
  Error: Constant 'MAX' is already defined
   --> names.slick:2:1
    |
  1 | MAX :: 10;
    | --- First defined here
  2 | MAX :: 20;
    | ^^^ Defined again here
  
  Error: 'f' is already declared as a constant
   --> names.slick:3:1
    |
  3 | f :: fn() { }
    | ^ Declared again here
  4 | f :: 1;
    | - Constant defined here
    |
  Note: Slick does not allow shadowing
  Help: Choose a different name
  
  Error: 'MAX' is already declared as a constant
   --> names.slick:6:5
    |
  1 | MAX :: 10;
    | --- Constant defined here
  ...
  6 |     MAX := 3;
    |     ^^^ Declared again here
    |
  Note: Slick does not allow shadowing
  Help: Choose a different name
  
  Error: 'MAX' is not a function
   --> names.slick:7:10
    |
  6 |     MAX := 3;
    |     --- 'MAX' is declared here as i32
  7 |     x := MAX();
    |          ^^^
  
  Error: Could not compile 'names.slick' due to 4 errors
  [1]

Constants are top-level only for now.

  $ cat > local.slick <<'EOF'
  > main :: fn() {
  >     N :: 5;
  >     M : i32 : 6;
  > }
  > EOF
  $ slick run local.slick
  Error: Constants can only be declared at the top level for now
   --> local.slick:2:7
    |
  2 |     N :: 5;
    |       ^^ Not allowed in a function
  
  Error: Constants can only be declared at the top level for now
   --> local.slick:3:13
    |
  3 |     M : i32 : 6;
    |             ^ Not allowed in a function
  
  Error: Could not compile 'local.slick' due to 2 errors
  [1]

Errors in a constant's value are reported once, at the definition, not at
each use.

  $ cat > once.slick <<'EOF'
  > BAD :: 1 + true;
  > main :: fn() {
  >     a := BAD;
  >     b := BAD;
  > }
  > EOF
  $ slick run once.slick
  Error: Operator '+' expects numbers, found i32 and bool
   --> once.slick:1:10
    |
  1 | BAD :: 1 + true;
    |        - i32
    |          ^
    |            ---- bool
  
  Error: Could not compile 'once.slick' due to 1 error
  [1]
