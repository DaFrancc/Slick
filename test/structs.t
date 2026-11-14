Structs: declarations, literals, fields, and passing by value.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

Milestone 1's acceptance test: particles moving under gravity, using structs,
pointers, floats, bit flags and the other integer types.

  $ slick run ../examples/particles.slick
  1
  2.000
  1.500
  true
  2
  4.000
  7.750
  false
  4
  2432902008176640000
  7.4
  7
  3.700000047683716

A struct is declared at the top level, in any order. Its literal names the
fields, in any order, or gives them all by position. Omitted fields are zero.

  $ cat > basics.slick <<'EOF'
  > Line :: struct { from, to: Vec2, width: f32 }
  > Vec2 :: struct { x, y: f32 }
  > main :: fn() {
  >     a := Vec2{ x = 1, y = 2 };
  >     b := Vec2{ y = 4, x = 3 };
  >     c := Vec2{ 5, 6 };
  >     d := Vec2{ y = 7 };
  >     e : Vec2;
  >     print(a.x);
  >     print(b.y);
  >     print(c.x + c.y);
  >     print(d.x);
  >     print(e.y);
  >     l := Line{ from = a, to = .{ 9, 10 }, width = 0.5 };
  >     print(l.to.y);
  >     print(l.from.x);
  > }
  > EOF
  $ slick run basics.slick
  1.0
  4.0
  11.0
  0.0
  0.0
  10.0
  1.0

Fields of a 'mut' struct can be assigned, including nested ones. Assigning a
struct copies it.

  $ cat > assign.slick <<'EOF'
  > Vec2 :: struct { x, y: i32 }
  > Box :: struct { min, max: Vec2 }
  > main :: fn() {
  >     b : mut = Box{ max = .{ 10, 10 } };
  >     b.min.x = 2;
  >     b.max.y += 5;
  >     copy := b;
  >     b.min.x = 100;
  >     print(copy.min.x);
  >     print(copy.max.y);
  >     b = copy;
  >     print(b.min.x);
  > }
  > EOF
  $ slick run assign.slick
  2
  15
  2

Structs are passed and returned by value. Through a *mut pointer, a function
changes the caller's struct; field access goes through the pointer by itself.

  $ cat > functions.slick <<'EOF'
  > Vec2 :: struct { x, y: f32 }
  > add :: fn(a, b: Vec2) -> Vec2 {
  >     return .{ a.x + b.x, a.y + b.y };
  > }
  > scale :: fn(v: *mut Vec2, k: f32) {
  >     v.x *= k;
  >     v.y *= k;
  > }
  > length2 :: fn(v: *Vec2) -> f32 {
  >     return v.x * v.x + v.y * v.y;
  > }
  > main :: fn() {
  >     a : mut = add(.{ 1, 2 }, Vec2{ 3, 4 });
  >     scale(&mut a, 0.5);
  >     print(a.x);
  >     print(a.y);
  >     print(length2(&a));
  >     print(add(a, a).y);
  > }
  > EOF
  $ slick run functions.slick
  2.0
  3.0
  13.0
  6.0

A struct can point to another struct, or to its own type. A struct with a
pointer field must be given one.

  $ cat > pointer_fields.slick <<'EOF'
  > Player :: struct { hp: i32 }
  > Turret :: struct { owner: *mut Player, range: f32 }
  > hurt :: fn(t: Turret) { t.owner.hp -= 10; }
  > main :: fn() {
  >     p : mut = Player{ hp = 100 };
  >     t := Turret{ owner = &mut p };
  >     hurt(t);
  >     hurt(t);
  >     print(p.hp);
  >     print(t.owner.hp);
  > }
  > EOF
  $ slick run pointer_fields.slick
  80
  80

An empty struct, and integer and bool fields with their zero values.

  $ cat > empty.slick <<'EOF'
  > Marker :: struct {}
  > Flags :: struct { on: bool, count: u8, total: i64, }
  > main :: fn() {
  >     m := Marker{};
  >     f : Flags;
  >     print(f.on);
  >     print(f.count);
  >     print(f.total);
  > }
  > EOF
  $ slick run empty.slick
  false
  0
  0

In an 'if' or 'while' condition, 'Name {' starts the body, so a struct
literal there needs parentheses.

  $ cat > condition.slick <<'EOF'
  > V :: struct { x: i32 }
  > main :: fn() {
  >     if (V{ x = 3 }).x == 3 { print(1); }
  >     limit := 2;
  >     i : mut = 0;
  >     while i < limit { i += 1; }
  >     print(i);
  > }
  > EOF
  $ slick run condition.slick
  1
  2

Literal errors: an unknown field, a field given twice, too few positional
values, named and positional values mixed, a missing pointer field, '.{ }'
with no type to take, and a name that is not a struct.

  $ cat > literal_errors.slick <<'EOF'
  > Vec3 :: struct { x, y, z: f32 }
  > Turret :: struct { owner: *Vec3, range: f32 }
  > f :: fn() { }
  > main :: fn() {
  >     a := Vec3{ x = 1, w = 2 };
  >     b := Vec3{ x = 1, x = 2 };
  >     c := Vec3{ 1, 2 };
  >     d := Vec3{ 1, y = 2, z = 3 };
  >     e := Turret{ range = 5 };
  >     g := .{ 1, 2 };
  >     h := f{};
  >     i := Vec4{};
  >     j := Vec3{ x = true };
  > }
  > EOF
  $ slick run literal_errors.slick
  Error: Struct 'Vec3' has no field 'w'
   --> literal_errors.slick:5:23
    |
  5 |     a := Vec3{ x = 1, w = 2 };
    |                       ^ Unknown field
    |
  Help: Did you mean 'x'?
    |
  5 |     a := Vec3{ x = 1, x = 2 };
    |                       ~
  
  Error: Field 'x' is given twice
   --> literal_errors.slick:6:23
    |
  6 |     b := Vec3{ x = 1, x = 2 };
    |                - First given here
    |                       ^ Given again here
  
  Error: Expected 3 values for 'Vec3', found 2
   --> literal_errors.slick:7:10
    |
  1 | Vec3 :: struct { x, y, z: f32 }
    | ---- Struct defined here
  ...
  7 |     c := Vec3{ 1, 2 };
    |          ^^^^^^^^^^^^ Found 2 values
    |
  Note: Positional values must give every field; name them to leave some out
  
  Error: Struct literal mixes named and positional values
   --> literal_errors.slick:8:16
    |
  8 |     d := Vec3{ 1, y = 2, z = 3 };
    |                ^ Positional value
  
  Error: Field 'owner' must be given a value
   --> literal_errors.slick:9:10
    |
  9 |     e := Turret{ range = 5 };
    |          ^^^^^^^ Missing 'owner'
    |
  Note: 'owner' is a pointer, and pointers cannot be zero
  
  Error: Cannot tell the type of this struct literal
    --> literal_errors.slick:10:10
     |
  10 |     g := .{ 1, 2 };
     |          ^^
     |
  Help: Write the struct's name before '{'
  
  Error: 'f' is not a struct
    --> literal_errors.slick:11:10
     |
   3 | f :: fn() { }
     | - Function defined here
  ...
  11 |     h := f{};
     |          ^ Not a struct
  
  Error: Unknown struct 'Vec4'
    --> literal_errors.slick:12:10
     |
  12 |     i := Vec4{};
     |          ^^^^ Not defined
     |
  Help: Did you mean 'Vec3'?
     |
  12 |     i := Vec3{};
     |          ~~~~
  
  Error: Field 'x' of 'Vec3' has type f32, found bool
    --> literal_errors.slick:13:20
     |
   1 | Vec3 :: struct { x, y, z: f32 }
     |                           --- Declared as f32 here
  ...
  13 |     j := Vec3{ x = true };
     |                    ^^^^ This is bool
  
  Error: Could not compile 'literal_errors.slick' due to 9 errors
  [1]

Field errors: an unknown field, a field of something that is not a struct,
and a field through two pointers.

  $ cat > field_errors.slick <<'EOF'
  > Vec2 :: struct { x, y: f32 }
  > main :: fn() {
  >     v := Vec2{ 1, 2 };
  >     a := v.z;
  >     n := 5;
  >     b := n.x;
  >     p := &v;
  >     pp := &p;
  >     c := pp.x;
  >     d := (*pp).x;
  > }
  > EOF
  $ slick run field_errors.slick
  Error: Struct 'Vec2' has no field 'z'
   --> field_errors.slick:4:12
    |
  4 |     a := v.z;
    |            ^ Unknown field
    |
  Help: Did you mean 'x'?
    |
  4 |     a := v.x;
    |            ~
  
  Error: A value of type i32 has no fields
   --> field_errors.slick:6:10
    |
  6 |     b := n.x;
    |          ^ This is i32
  
  Error: Cannot access a field through two pointers
   --> field_errors.slick:9:10
    |
  9 |     c := pp.x;
    |          ^^ This is **Vec2
    |
  Help: Dereference it first
    |
  9 |     c := (*pp).x;
    |          ++  +
  
  Error: Could not compile 'field_errors.slick' due to 3 errors
  [1]

Mutability follows the struct: fields of a struct declared without 'mut', or
reached through a read-only pointer, cannot be assigned.

  $ cat > mut_errors.slick <<'EOF'
  > Vec2 :: struct { x, y: f32 }
  > nudge :: fn(v: *Vec2) { v.x += 1; }
  > main :: fn() {
  >     v := Vec2{ 1, 2 };
  >     v.x = 3;
  >     p := &mut v.y;
  > }
  > EOF
  $ slick run mut_errors.slick
  Error: Cannot assign through 'v': it points to a read-only Vec2
   --> mut_errors.slick:2:25
    |
  2 | nudge :: fn(v: *Vec2) { v.x += 1; }
    |                ----- Declared as *Vec2 here
    |                         ^^^ Cannot assign
    |
  Help: Make it a mutable pointer
    |
  2 | nudge :: fn(v: *mut Vec2) { v.x += 1; }
    |                 ++++
  
  Error: Cannot assign to 'v.x': 'v' was declared without 'mut'
   --> mut_errors.slick:5:5
    |
  4 |     v := Vec2{ 1, 2 };
    |     - Declared here without 'mut'
  5 |     v.x = 3;
    |     ^^^ Cannot assign
    |
  Help: Declare it with 'mut'
    |
  4 |     v : mut = Vec2{ 1, 2 };
    |       ~~~~~~~
  
  Error: Cannot take a mutable pointer to 'v.y': 'v' was declared without 'mut'
   --> mut_errors.slick:6:10
    |
  4 |     v := Vec2{ 1, 2 };
    |     - Declared here without 'mut'
  5 |     v.x = 3;
  6 |     p := &mut v.y;
    |          ^^^^^^^^ Needs 'mut'
    |
  Help: Declare it with 'mut'
    |
  4 |     v : mut = Vec2{ 1, 2 };
    |       ~~~~~~~
  
  Error: Could not compile 'mut_errors.slick' due to 3 errors
  [1]

Declaration errors: a field declared twice, a struct that contains itself by
value, a name already taken, and a 'mut' field.

  $ cat > decl_errors.slick <<'EOF'
  > Vec2 :: struct { x, y: f32, x: i32 }
  > Node :: struct { value: i32, next: Node }
  > A :: struct { b: B }
  > B :: struct { a: A }
  > List :: struct { head: *List }
  > Vec2 :: struct { a: i32 }
  > i32 :: struct { a: i32 }
  > print :: struct { a: i32 }
  > main :: fn() {
  >     Vec2 := 5;
  > }
  > EOF
  $ slick run decl_errors.slick
  Error: Field 'x' is declared twice
   --> decl_errors.slick:1:29
    |
  1 | Vec2 :: struct { x, y: f32, x: i32 }
    |                  - First declared here
    |                             ^ Declared again here
  
  Error: Struct 'Node' contains itself
   --> decl_errors.slick:2:30
    |
  2 | Node :: struct { value: i32, next: Node }
    |                              ^^^^ Contains 'Node' by value
    |
  Note: A struct cannot contain itself, directly or through other structs' fields
  Help: Point to it instead, with a pointer field
  
  Error: Struct 'A' contains itself
   --> decl_errors.slick:3:15
    |
  3 | A :: struct { b: B }
    |               ^ Contains 'B' by value
  4 | B :: struct { a: A }
    |               - Contains 'A' by value
    |
  Note: A struct cannot contain itself, directly or through other structs' fields
  Help: Point to it instead, with a pointer field
  
  Error: Struct 'Vec2' is already defined
   --> decl_errors.slick:6:1
    |
  1 | Vec2 :: struct { x, y: f32, x: i32 }
    | ---- First defined here
  ...
  6 | Vec2 :: struct { a: i32 }
    | ^^^^ Defined again here
  
  Error: 'i32' is a built-in type and cannot be redeclared
   --> decl_errors.slick:7:1
    |
  7 | i32 :: struct { a: i32 }
    | ^^^
    |
  Help: Choose a different name
  
  Error: 'print' is a built-in function and cannot be redeclared
   --> decl_errors.slick:8:1
    |
  8 | print :: struct { a: i32 }
    | ^^^^^
    |
  Help: Choose a different name
  
  Error: 'Vec2' is already declared as a struct
    --> decl_errors.slick:10:5
     |
   1 | Vec2 :: struct { x, y: f32, x: i32 }
     | ---- Struct defined here
  ...
  10 |     Vec2 := 5;
     |     ^^^^ Declared again here
     |
  Note: Slick does not allow shadowing
  Help: Choose a different name
  
  Error: Could not compile 'decl_errors.slick' due to 7 errors
  [1]

  $ cat > mut_field.slick <<'EOF'
  > P :: struct { a: mut i32 }
  > main :: fn() { }
  > EOF
  $ slick run mut_field.slick
  Error: Fields cannot be declared 'mut'
   --> mut_field.slick:1:18
    |
  1 | P :: struct { a: mut i32 }
    |                  ^^^
    |
  Note: A field is mutable when its struct is
  Help: Remove it
    |
  1 | P :: struct { a: mut i32 }
    |                  ----
  
  Error: Could not compile 'mut_field.slick' due to 1 error
  [1]

A struct with a pointer field, declared without a value, is an error, since
pointers cannot be zero. So is comparing structs with '=='.

  $ cat > misc_errors.slick <<'EOF'
  > Turret :: struct { owner: *i32 }
  > Group :: struct { lead: Turret }
  > V :: struct { x: i32 }
  > main :: fn() {
  >     t : Turret;
  >     g : Group;
  >     a := V{ 1 };
  >     b := a == a;
  >     print(a);
  >     c := V(1);
  >     d := V;
  > }
  > EOF
  $ slick run misc_errors.slick
  Error: 't' must be given an initial value
   --> misc_errors.slick:5:5
    |
  5 |     t : Turret;
    |     ^
    |
  Note: Its type Turret contains the pointer field 'owner', and pointers cannot be zero
  
  Error: 'g' must be given an initial value
   --> misc_errors.slick:6:5
    |
  6 |     g : Group;
    |     ^
    |
  Note: Its type Group contains the pointer field 'lead.owner', and pointers cannot be zero
  
  Error: Cannot compare structs with '=='
   --> misc_errors.slick:8:12
    |
  8 |     b := a == a;
    |            ^^
    |
  Note: Compare their fields one by one
  
  Error: 'print' takes a number, a bool or a cstring
   --> misc_errors.slick:9:11
    |
  9 |     print(a);
    |           ^ This is V
  
  Error: 'V' is a struct, not a function
    --> misc_errors.slick:10:10
     |
   3 | V :: struct { x: i32 }
     | - Struct defined here
  ...
  10 |     c := V(1);
     |          ^
     |
  Help: To make one, write 'V{ ... }'
  
  Error: 'V' is a struct, not a value
    --> misc_errors.slick:11:10
     |
   3 | V :: struct { x: i32 }
     | - Struct defined here
  ...
  11 |     d := V;
     |          ^
  
  Error: Could not compile 'misc_errors.slick' due to 6 errors
  [1]

Field syntax errors are reported, and the rest of the file is still parsed.

  $ cat > syntax.slick <<'EOF'
  > V :: struct { x: i32 y: i32 }
  > W :: struct { a: i32 }
  > main :: fn() {
  >     v := V{ x = 1 2 };
  >     print(1);
  > }
  > EOF
  $ slick run syntax.slick
  Error: Expected ',' or '}', found 'y'
   --> syntax.slick:1:22
    |
  1 | V :: struct { x: i32 y: i32 }
    |                      ^ Expected ',' or '}'
  
  Error: Expected ',' or '}', found '2'
   --> syntax.slick:4:19
    |
  4 |     v := V{ x = 1 2 };
    |                   ^ Expected ',' or '}'
  
  Error: Could not compile 'syntax.slick' due to 2 errors
  [1]
