String literals. Until Slick has its 'string' type, a literal is a cstring: a
null-terminated string for C.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

print shows a cstring. Escapes are decoded, and characters outside ASCII can
be written directly or with \u{...}.

  $ cat > basics.slick <<'EOF'
  > main :: fn() {
  >     print("Hello, Slick");
  >     print("tab:\there");
  >     print("quote: \" backslash: \\ apostrophe: \'");
  >     print("hex: \x41\x42");
  >     print("héllo \u{E9} \u{1F600}");
  >     print("two\nlines");
  >     s : cstring = "named";
  >     print(s);
  >     t := s;
  >     print(t);
  > }
  > EOF
  $ slick run basics.slick
  Hello, Slick
  tab:	here
  quote: " backslash: \ apostrophe: '
  hex: AB
  héllo é 😀
  two
  lines
  named
  named

A cstring can be a field and a parameter. Since it points to text, it has no
zero value, so a variable or field of that type needs a value.

  $ cat > fields.slick <<'EOF'
  > Player :: struct { name: cstring, hp: i32 }
  > greet :: fn(p: Player) { print(p.name); }
  > main :: fn() {
  >     greet(Player{ name = "Archer", hp = 10 });
  > }
  > EOF
  $ slick run fields.slick
  Archer

  $ cat > uninit.slick <<'EOF'
  > Player :: struct { name: cstring, hp: i32 }
  > main :: fn() {
  >     s : cstring;
  >     p := Player{ hp = 1 };
  > }
  > EOF
  $ slick run uninit.slick
  Error: 's' must be given an initial value
   --> uninit.slick:3:5
    |
  3 |     s : cstring;
    |     ^
    |
  Note: A cstring points to text, so it cannot be zero
  
  Error: Field 'name' must be given a value
   --> uninit.slick:4:10
    |
  4 |     p := Player{ hp = 1 };
    |          ^^^^^^^ Missing 'name'
    |
  Note: 'name' is a cstring, which points to text, so it cannot be zero
  
  Error: Could not compile 'uninit.slick' due to 2 errors
  [1]

Comparing cstrings with == would compare addresses, so it is an error.

  $ cat > compare.slick <<'EOF'
  > main :: fn() {
  >     same := "a" == "a";
  > }
  > EOF
  $ slick run compare.slick
  Error: Cannot compare cstrings with '=='
   --> compare.slick:2:17
    |
  2 |     same := "a" == "a";
    |                 ^^
    |
  Note: It would compare their addresses, not their text
  
  Error: Could not compile 'compare.slick' due to 1 error
  [1]

Escape errors: an unknown escape, a zero byte, and bad \x and \u forms.

  $ cat > escapes.slick <<'EOF'
  > main :: fn() {
  >     print("a\qb");
  >     print("zero\0here");
  >     print("\x4");
  >     print("\u{110000}");
  >     print("\u41");
  > }
  > EOF
  $ slick run escapes.slick
  Error: Unknown escape '\q'
   --> escapes.slick:2:13
    |
  2 |     print("a\qb");
    |             ^^
    |
  Note: The escapes are \n \t \r \\ \" \' \0 \xHH and \u{...}
  
  Error: A cstring cannot contain a zero byte
   --> escapes.slick:3:16
    |
  3 |     print("zero\0here");
    |                ^^
    |
  Note: C would treat it as the end of the string
  
  Error: Invalid escape: '\x' needs two hex digits
   --> escapes.slick:4:12
    |
  4 |     print("\x4");
    |            ^^
  
  Error: '\u{110000}' is not a Unicode code point
   --> escapes.slick:5:12
    |
  5 |     print("\u{110000}");
    |            ^^^^^^^^^^
  
  Error: Invalid escape: write '\u{...}'
   --> escapes.slick:6:12
    |
  6 |     print("\u41");
    |            ^^
  
  Error: Could not compile 'escapes.slick' due to 5 errors
  [1]

A string must end on its line.

  $ cat > unterminated.slick <<'EOF'
  > main :: fn() {
  >     print("no end);
  > }
  > EOF
  $ slick run unterminated.slick
  Error: Unterminated string literal
   --> unterminated.slick:2:11
    |
  2 |     print("no end);
    |           ^^^^^^^^^ Needs a closing '"'
    |
  Help: Close it
    |
  2 |     print("no end");
    |                  +
  
  Error: Could not compile 'unterminated.slick' due to 1 error
  [1]
