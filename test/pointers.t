Pointers: *T points to read-only data and *mut T to mutable data.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

&x gives a *T and &mut x a *mut T. Writing through a *mut T changes the
variable it points to.

  $ cat > basics.slick <<'EOF'
  > main :: fn() {
  >     x : mut i32 = 1;
  >     p := &mut x;
  >     *p = 5;
  >     print(x);
  >     *p += 2;
  >     print(*p);
  >     q : *i32 = &x;
  >     print(*q + 1);
  > }
  > EOF
  $ slick run basics.slick
  5
  7
  8

A function can change its caller's variables through a *mut parameter.

  $ cat > params.slick <<'EOF'
  > swap :: fn(a, b: *mut i64) {
  >     t := *a;
  >     *a = *b;
  >     *b = t;
  > }
  > read :: fn(p: *i64) -> i64 { return *p; }
  > main :: fn() {
  >     x : mut i64 = 1;
  >     y : mut i64 = 2;
  >     swap(&mut x, &mut y);
  >     print(x);
  >     print(y);
  >     print(read(&x));
  >     print(read(&mut y));
  > }
  > EOF
  $ slick run params.slick
  2
  1
  2
  1

Pointers to pointers, and repointing a 'mut' pointer variable.

  $ cat > nested.slick <<'EOF'
  > main :: fn() {
  >     a : mut i32 = 1;
  >     b : mut i32 = 2;
  >     p : mut *mut i32 = &mut a;
  >     pp := &mut p;
  >     **pp = 10;
  >     print(a);
  >     *pp = &mut b;
  >     *p = 20;
  >     print(b);
  > }
  > EOF
  $ slick run nested.slick
  10
  20

Pointers compare with == and !=. A *mut T and a *T to the same type compare
fine.

  $ cat > compare.slick <<'EOF'
  > main :: fn() {
  >     a : mut i32 = 1;
  >     b : mut i32 = 1;
  >     p := &mut a;
  >     q : *i32 = &a;
  >     print(p == q);
  >     print(p != &b);
  > }
  > EOF
  $ slick run compare.slick
  true
  true

Writing needs a mutable place: '&mut' of a variable declared without 'mut',
and writing through a read-only pointer, are errors with a fix.

  $ cat > mut_errors.slick <<'EOF'
  > set :: fn(p: *i32) {
  >     *p = 1;
  > }
  > main :: fn() {
  >     count := 0;
  >     a := &mut count;
  >     x : mut i32 = 0;
  >     r := &x;
  >     *r = 2;
  >     s : *i32 = &x;
  >     *s += 1;
  > }
  > EOF
  $ slick run mut_errors.slick
  Error: Cannot assign through 'p': it points to a read-only i32
   --> mut_errors.slick:2:5
    |
  1 | set :: fn(p: *i32) {
    |              ---- Declared as *i32 here
  2 |     *p = 1;
    |     ^^ Cannot assign
    |
  Help: Make it a mutable pointer
    |
  1 | set :: fn(p: *mut i32) {
    |               ++++
  
  Error: Cannot take a mutable pointer to 'count': it was declared without 'mut'
   --> mut_errors.slick:6:10
    |
  5 |     count := 0;
    |     ----- Declared here without 'mut'
  6 |     a := &mut count;
    |          ^^^^^^^^^^ Needs 'mut'
    |
  Help: Declare it with 'mut'
    |
  5 |     count : mut = 0;
    |           ~~~~~~~
  
  Error: Cannot assign through 'r': it points to a read-only i32
   --> mut_errors.slick:9:5
    |
  8 |     r := &x;
    |     - Declared as *i32 here
  9 |     *r = 2;
    |     ^^ Cannot assign
    |
  Help: Make it a mutable pointer
    |
  8 |     r := &mut x;
    |           ++++
  
  Error: Cannot assign through 's': it points to a read-only i32
    --> mut_errors.slick:11:5
     |
  10 |     s : *i32 = &x;
     |         ---- Declared as *i32 here
  11 |     *s += 1;
     |     ^^ Cannot assign
     |
  Help: Make it a mutable pointer
     |
  10 |     s : *mut i32 = &x;
     |          ++++
  
  Error: Could not compile 'mut_errors.slick' due to 4 errors
  [1]

A *T does not become a *mut T.

  $ cat > ptr_mismatch.slick <<'EOF'
  > main :: fn() {
  >     x : mut i32 = 0;
  >     p : *mut i32 = &x;
  >     q : *i64 = &x;
  > }
  > EOF
  $ slick run ptr_mismatch.slick
  Error: Cannot initialize 'p' of type *mut i32 with a value of type *i32
   --> ptr_mismatch.slick:3:20
    |
  3 |     p : *mut i32 = &x;
    |         -------- Declared as *mut i32 here
    |                    ^^ This is *i32
    |
  Note: A pointer to read-only data cannot become a '*mut'
  Help: Take a mutable pointer
    |
  3 |     p : *mut i32 = &mut x;
    |                     ++++
  
  Error: Cannot initialize 'q' of type *i64 with a value of type *i32
   --> ptr_mismatch.slick:4:16
    |
  4 |     q : *i64 = &x;
    |         ---- Declared as *i64 here
    |                ^^ This is *i32
  
  Error: Could not compile 'ptr_mismatch.slick' due to 2 errors
  [1]

Only places in memory have addresses, and only pointers can be dereferenced.

  $ cat > place_errors.slick <<'EOF'
  > one :: fn() -> i32 { return 1; }
  > main :: fn() {
  >     a := &one();
  >     b := &5;
  >     c := &&a;
  >     n := 5;
  >     d := *n;
  >     e : mut i32 = 0;
  >     f := &e < &e;
  > }
  > EOF
  $ slick run place_errors.slick
  Error: Cannot take the address of a temporary value
   --> place_errors.slick:3:11
    |
  3 |     a := &one();
    |           ^^^^^ Not stored anywhere
    |
  Help: Store it in a variable first
  
  Error: Cannot take the address of a temporary value
   --> place_errors.slick:4:11
    |
  4 |     b := &5;
    |           ^ Not stored anywhere
    |
  Help: Store it in a variable first
  
  Error: Cannot take the address of a temporary value
   --> place_errors.slick:5:11
    |
  5 |     c := &&a;
    |           ^^ Not stored anywhere
    |
  Help: Store it in a variable first
  
  Error: Cannot dereference a value of type i32
   --> place_errors.slick:7:11
    |
  7 |     d := *n;
    |           ^ This is i32
  
  Error: Operator '<' does not work on pointers
   --> place_errors.slick:9:13
    |
  9 |     f := &e < &e;
    |          -- *i32
    |             ^
    |               -- *i32
    |
  Note: Pointers can only be compared with '==' and '!='
  
  Error: Could not compile 'place_errors.slick' due to 5 errors
  [1]

A pointer can never be null, so a pointer variable needs a value.

  $ cat > uninit.slick <<'EOF'
  > main :: fn() {
  >     p : *i32;
  > }
  > EOF
  $ slick run uninit.slick
  Error: 'p' must be given an initial value
   --> uninit.slick:2:5
    |
  2 |     p : *i32;
    |     ^
    |
  Note: Its type *i32 is a pointer, and pointers cannot be zero
  
  Error: Could not compile 'uninit.slick' due to 1 error
  [1]

'*void' is not a type, and an unknown type behind '*' is reported once.

  $ cat > bad_types.slick <<'EOF'
  > main :: fn() {
  >     x : i32 = 0;
  >     p : *void = &x;
  >     q : *mut Foo = &x;
  > }
  > EOF
  $ slick run bad_types.slick
  Error: Unknown type 'void'
   --> bad_types.slick:3:10
    |
  3 |     p : *void = &x;
    |          ^^^^ Not a type
    |
  Note: The built-in types are i8, i16, i32, i64, u8, u16, u32, u64, f32, f64 and bool
  
  Error: Unknown type 'Foo'
   --> bad_types.slick:4:14
    |
  4 |     q : *mut Foo = &x;
    |              ^^^ Not a type
    |
  Note: The built-in types are i8, i16, i32, i64, u8, u16, u32, u64, f32, f64 and bool
  
  Error: Could not compile 'bad_types.slick' due to 2 errors
  [1]
