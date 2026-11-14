C functions, declared in foreign blocks. These tests call the C library and
the math library, which every system has. An empty library name links
nothing extra: the C library is always linked.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

The name before '::' is the Slick name. '#link_name' gives the C symbol when
it differs. 'abs' and 'puts' are also declared by the C headers the runtime
includes, and they do not clash.

  $ cat > libc.slick <<'EOF'
  > foreign "m" {
  >     Sqrt :: fn(x: f64) -> f64 #link_name("sqrt");
  > }
  > foreign "" {
  >     Abs  :: fn(x: i32) -> i32 #link_name("abs");
  >     Puts :: fn(s: cstring) -> i32 #link_name("puts");
  > }
  > main :: fn() {
  >     print(Sqrt(2.0));
  >     print(Abs(-42));
  >     r := Puts("printed by C");
  > }
  > EOF
  $ slick run libc.slick
  1.4142135623730951
  42
  printed by C

Structs cross by value with C's layout. glibc's div_t holds the quotient,
then the remainder.

  $ cat > div.slick <<'EOF'
  > DivT :: struct { quot, rem: i32 }
  > foreign "" { Div :: fn(a, b: i32) -> DivT #link_name("div"); }
  > main :: fn() {
  >     r := Div(17, 5);
  >     print(r.quot);
  >     print(r.rem);
  > }
  > EOF
  $ slick run div.slick
  3
  2

'#link_prefix' on the block is put in front of every Slick name, unless a
function has its own '#link_name'.

  $ cat > prefix.slick <<'EOF'
  > foreign "" #link_prefix("str") {
  >     len :: fn(s: cstring) -> u64;
  >     Compare :: fn(a, b: cstring) -> i32 #link_name("strcmp");
  > }
  > main :: fn() {
  >     print(len("hello"));
  >     print(Compare("abc", "abc"));
  > }
  > EOF
  $ slick run prefix.slick
  5
  0

A foreign function is declared under its own C name, with an assembler label
giving the real symbol.

  $ slick build libc.slick --emit-c | grep -E 'SLICKRT_SYM\("'
  extern double slickf_Sqrt(double) SLICKRT_SYM("sqrt");
  extern int32_t slickf_Abs(int32_t) SLICKRT_SYM("abs");
  extern int32_t slickf_Puts(const char *) SLICKRT_SYM("puts");

A library that cannot be found is the user's error, not slick's. The
linker's own output varies, so only slick's lines are shown.

  $ cat > missing.slick <<'EOF'
  > foreign "slicknosuchlib" { Nothing :: fn(); }
  > main :: fn() { Nothing(); }
  > EOF
  $ slick run missing.slick 2>&1 | grep -E '^(Error|Note|Help)'
  Error: Could not link 'missing.slick'
  Note: It links with: -lslicknosuchlib
  Help: Check that these libraries are installed, or add a search path with SLICK_LDFLAGS="-L<dir>"

  $ slick run missing.slick > /dev/null 2>&1; echo $?
  1

Errors inside a foreign block: a body, an item that is not a function, an
unknown or misplaced attribute, and a bad attribute argument.

  $ cat > block_errors.slick <<'EOF'
  > foreign "m" #link_name("x") {
  >     Sqrt :: fn(x: f64) -> f64 { return x; }
  >     PI :: 3.14;
  >     Cos :: fn(x: f64) -> f64 #link_nme("cos");
  >     Sin :: fn(x: f64) -> f64 #link_prefix("s");
  >     Tan :: fn(x: f64) -> f64 #link_name(tan);
  > }
  > main :: fn() { }
  > EOF
  $ slick run block_errors.slick
  Error: '#link_name' goes on a function in a foreign block, not the block
   --> block_errors.slick:1:13
    |
  1 | foreign "m" #link_name("x") {
    |             ^^^^^^^^^^ Not allowed here
  
  Error: A foreign function cannot have a body
   --> block_errors.slick:2:31
    |
  2 |     Sqrt :: fn(x: f64) -> f64 { return x; }
    |                               ^ Not allowed in a foreign block
    |
  Note: Its code is in the library 'm'
  
  Error: Only function declarations can go in a foreign block
   --> block_errors.slick:3:5
    |
  3 |     PI :: 3.14;
    |     ^^ Not a function declaration
  
  Error: Unknown attribute '#link_nme'
   --> block_errors.slick:4:30
    |
  4 |     Cos :: fn(x: f64) -> f64 #link_nme("cos");
    |                              ^^^^^^^^^ Unknown
    |
  Help: Did you mean '#link_name'?
    |
  4 |     Cos :: fn(x: f64) -> f64 #link_name("cos");
    |                              ~~~~~~~~~~
  
  Error: '#link_prefix' goes on a foreign block, not a function
   --> block_errors.slick:5:30
    |
  5 |     Sin :: fn(x: f64) -> f64 #link_prefix("s");
    |                              ^^^^^^^^^^^^ Not allowed here
  
  Error: '#link_name' expects a string, like #link_name("name")
   --> block_errors.slick:6:40
    |
  6 |     Tan :: fn(x: f64) -> f64 #link_name(tan);
    |                                        ^ Expected a string in parentheses
  
  Error: Could not compile 'block_errors.slick' due to 6 errors
  [1]

A function with no body outside a foreign block is a parse error that points
to foreign blocks.

  $ cat > no_body.slick <<'EOF'
  > Sqrt :: fn(x: f64) -> f64;
  > main :: fn() { }
  > EOF
  $ slick run no_body.slick
  Error: Expected '{' to start the function body, found ';'
   --> no_body.slick:1:26
    |
  1 | Sqrt :: fn(x: f64) -> f64;
    |                          ^ Expected '{' to start the function body
    |
  Note: To declare a C function, put it in a 'foreign' block
  
  Error: Could not compile 'no_body.slick' due to 1 error
  [1]

The library name is required.

  $ cat > no_lib.slick <<'EOF'
  > foreign { Sqrt :: fn(x: f64) -> f64; }
  > main :: fn() { }
  > EOF
  $ slick run no_lib.slick
  Error: Expected the library's name, like foreign "raylib", found '{'
   --> no_lib.slick:1:9
    |
  1 | foreign { Sqrt :: fn(x: f64) -> f64; }
    |         ^ Expected the library's name, like foreign "raylib"
  
  Error: Could not compile 'no_lib.slick' due to 1 error
  [1]

Checker errors: a 'mut' parameter, a foreign 'main', and a name already taken.

  $ cat > check_errors.slick <<'EOF'
  > foreign "" {
  >     Abs :: fn(x: mut i32) -> i32 #link_name("abs");
  >     main :: fn();
  >     print :: fn(s: cstring);
  > }
  > EOF
  $ slick run check_errors.slick
  Error: Parameters of a foreign function cannot be 'mut'
   --> check_errors.slick:2:15
    |
  2 |     Abs :: fn(x: mut i32) -> i32 #link_name("abs");
    |               ^ Declared 'mut'
  
  Error: 'main' cannot be a foreign function
   --> check_errors.slick:3:5
    |
  3 |     main :: fn();
    |     ^^^^
  
  Error: 'print' is a built-in function and cannot be redeclared
   --> check_errors.slick:4:5
    |
  4 |     print :: fn(s: cstring);
    |     ^^^^^
    |
  Help: Choose a different name
  
  Error: Could not compile 'check_errors.slick' due to 3 errors
  [1]

Structs passed by value, floats and bools, against a small C library built
here. Its functions have the same shapes as raylib's: a struct of four u8s,
a struct of two floats, and a struct of four floats. SLICK_LDFLAGS tells the
linker where to find it.

  $ cat > shapes.c <<'EOF'
  > #include <stdbool.h>
  > typedef struct { unsigned char r, g, b, a; } Color;
  > typedef struct { float x, y; } Vector2;
  > typedef struct { float x, y, width, height; } Rectangle;
  > int ColorSum(Color c) { return c.r + c.g + c.b + c.a; }
  > Vector2 Scale(Vector2 v, float k) { Vector2 r = { v.x * k, v.y * k }; return r; }
  > bool Inside(Vector2 p, Rectangle r) {
  >     return p.x >= r.x && p.x <= r.x + r.width && p.y >= r.y && p.y <= r.y + r.height;
  > }
  > EOF
  $ cc -c -o shapes.o shapes.c && ar rcs libshapes.a shapes.o

  $ cat > shapes.slick <<'EOF'
  > Color     :: struct { r, g, b, a: u8 }
  > Vector2   :: struct { x, y: f32 }
  > Rectangle :: struct { x, y, width, height: f32 }
  > foreign "shapes" {
  >     ColorSum :: fn(c: Color) -> i32;
  >     Scale    :: fn(v: Vector2, k: f32) -> Vector2;
  >     Inside   :: fn(p: Vector2, r: Rectangle) -> bool;
  > }
  > main :: fn() {
  >     print(ColorSum(.{ 1, 2, 3, 250 }));
  >     v := Scale(.{ 1.5, -2 }, 2);
  >     print(v.x);
  >     print(v.y);
  >     box := Rectangle{ 0, 0, 10, 5 };
  >     print(Inside(.{ 3, 4 }, box));
  >     print(Inside(.{ 3, 6 }, box));
  > }
  > EOF
  $ SLICK_LDFLAGS="-L." slick run shapes.slick
  256
  3.0
  -4.0
  true
  false

Pong uses only what these tests cover. Its C compiles without raylib, since
no headers are read; linking it needs raylib, so that step only runs where
raylib is installed, and prints the same either way.

  $ slick build ../examples/pong.slick --emit-c > pong.c && cc -std=c11 -c -o pong.o pong.c && echo compiles
  compiles

  $ if pkg-config --exists raylib; then slick build ../examples/pong.slick -o pong && echo linked; else echo linked; fi
  linked
