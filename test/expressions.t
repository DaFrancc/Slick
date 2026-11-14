Stage 2: operators, precedence, literals, and their type errors.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

Precedence and associativity.

  $ cat > prec.slick <<'EOF'
  > main :: fn() {
  >     print(1 + 2 * 3);
  >     print((1 + 2) * 3);
  >     print(10 - 4 - 3);
  >     print(100 / 10 / 5);
  >     print(2 * 3 % 4);
  >     print(20 - 2 * 3 - 4);
  > }
  > EOF
  $ slick run prec.slick
  7
  9
  3
  2
  2
  10

Unary minus binds tighter than any binary operator.

  $ cat > unary.slick <<'EOF'
  > main :: fn() {
  >     print(-2 * 3);
  >     print(- -5);
  >     print(2 - -3);
  >     print(-(2 + 3));
  >     print(-(-(4)));
  > }
  > EOF
  $ slick run unary.slick
  -6
  5
  5
  -5
  4

Division truncates toward zero, and the remainder takes the sign of the
dividend.

  $ cat > div.slick <<'EOF'
  > main :: fn() {
  >     print(7 / 2);
  >     print(-7 / 2);
  >     print(7 / -2);
  >     print(-7 % 2);
  >     print(7 % -2);
  > }
  > EOF
  $ slick run div.slick
  3
  -3
  -3
  -1
  1

Digit separators.

  $ cat > sep.slick <<'EOF'
  > main :: fn() { print(1_000_000); }
  > EOF
  $ slick run sep.slick
  1000000

Integer overflow wraps, including at the edges of i32 and in the two cases
where C division would trap.

  $ cat > wrap.slick <<'EOF'
  > main :: fn() {
  >     print(2147483647 + 1);
  >     print(-2147483648);
  >     print(-2147483648 - 1);
  >     print(65536 * 65536);
  >     print(-(-2147483648));
  >     print(-2147483648 / -1);
  >     print(-2147483648 % -1);
  > }
  > EOF
  $ slick run wrap.slick
  -2147483648
  -2147483648
  2147483647
  0
  -2147483648
  -2147483648
  0

A literal with nothing giving it a type is an i32, so it must fit in one.
2147483648 only fits when negated. No integer type holds the second one.

  $ cat > big.slick <<'EOF'
  > main :: fn() {
  >     print(2147483648);
  > }
  > EOF
  $ slick run big.slick
  Error: Integer literal 2147483648 does not fit in i32
   --> big.slick:2:11
    |
  2 |     print(2147483648);
    |           ^^^^^^^^^^ Too large for i32
    |
  Note: An i32 holds values from -2147483648 to 2147483647
  
  Error: Could not compile 'big.slick' due to 1 error
  [1]

  $ cat > huge.slick <<'EOF'
  > main :: fn() {
  >     print(99999999999999999999999);
  > }
  > EOF
  $ slick run huge.slick
  Error: Integer literal 99999999999999999999999 is too large
   --> huge.slick:2:11
    |
  2 |     print(99999999999999999999999);
    |           ^^^^^^^^^^^^^^^^^^^^^^^ Larger than any integer type
    |
  Note: The largest is u64, which holds up to 18446744073709551615
  
  Error: Could not compile 'huge.slick' due to 1 error
  [1]

Dividing by zero is a runtime panic. Output printed before it still appears
first.

  $ cat > divzero.slick <<'EOF'
  > main :: fn() {
  >     print(1);
  >     print(1 / 0);
  >     print(2);
  > }
  > EOF
  $ slick run divzero.slick
  1
  Panic: Division by zero
   --> divzero.slick:3:15
    |
  3 |     print(1 / 0);
    |               ^ This is zero
  [1]

  $ cat > remzero.slick <<'EOF'
  > main :: fn() {
  >     print(1);
  >     print(1 % 0);
  > }
  > EOF
  $ slick run remzero.slick
  1
  Panic: Remainder by zero
   --> remzero.slick:3:15
    |
  3 |     print(1 % 0);
    |               ^ This is zero
  [1]

An expression can break across lines anywhere, including before an operator.

  $ cat > breaks.slick <<'EOF'
  > main :: fn() {
  >     print(10
  >         - 4);
  >     print(1 +
  >         2);
  > }
  > EOF
  $ slick run breaks.slick
  6
  3

Operand type errors, each pointing at the operator.

  $ cat > add_bool.slick <<'EOF'
  > main :: fn() {
  >     print(1 + true);
  > }
  > EOF
  $ slick run add_bool.slick
  Error: Operator '+' expects numbers, found i32 and bool
   --> add_bool.slick:2:13
    |
  2 |     print(1 + true);
    |           - i32
    |             ^
    |               ---- bool
  
  Error: Could not compile 'add_bool.slick' due to 1 error
  [1]

  $ cat > less_bool.slick <<'EOF'
  > main :: fn() {
  >     b := false < 1;
  > }
  > EOF
  $ slick run less_bool.slick
  Error: Operator '<' expects numbers, found bool and i32
   --> less_bool.slick:2:16
    |
  2 |     b := false < 1;
    |          ----- bool
    |                ^
    |                  - i32
  
  Error: Could not compile 'less_bool.slick' due to 1 error
  [1]

  $ cat > not_int.slick <<'EOF'
  > main :: fn() {
  >     b := !1;
  > }
  > EOF
  $ slick run not_int.slick
  Error: Operator '!' expects bool, found i32
   --> not_int.slick:2:10
    |
  2 |     b := !1;
    |          ^
    |           - i32
    |
  Help: To test for zero, compare it: '1 == 0'
  
  Error: Could not compile 'not_int.slick' due to 1 error
  [1]

  $ cat > neg_bool.slick <<'EOF'
  > main :: fn() {
  >     print(-true);
  > }
  > EOF
  $ slick run neg_bool.slick
  Error: Operator '-' expects a number, found bool
   --> neg_bool.slick:2:11
    |
  2 |     print(-true);
    |           ^
    |            ---- bool
  
  Error: Could not compile 'neg_bool.slick' due to 1 error
  [1]

  $ cat > eq_mixed.slick <<'EOF'
  > main :: fn() {
  >     b := 1 == true;
  > }
  > EOF
  $ slick run eq_mixed.slick
  Error: Operator '==' needs both sides to have the same type, found i32 and bool
   --> eq_mixed.slick:2:12
    |
  2 |     b := 1 == true;
    |          - i32
    |            ^^
    |               ---- bool
  
  Error: Could not compile 'eq_mixed.slick' due to 1 error
  [1]

  $ cat > and_int.slick <<'EOF'
  > main :: fn() {
  >     b := true && 1;
  > }
  > EOF
  $ slick run and_int.slick
  Error: Operator '&&' expects bool operands, found bool and i32
   --> and_int.slick:2:15
    |
  2 |     b := true && 1;
    |          ---- bool
    |               ^^
    |                  - i32
  
  Error: Could not compile 'and_int.slick' due to 1 error
  [1]

Comparisons cannot be chained.

  $ cat > chain.slick <<'EOF'
  > main :: fn() {
  >     print(1 < 2 < 3);
  > }
  > EOF
  $ slick run chain.slick
  Error: Comparisons cannot be chained
   --> chain.slick:2:17
    |
  2 |     print(1 < 2 < 3);
    |             -
    |                 ^
    |
  Help: Combine them with '&&'
    |
  2 |     print(1 < 2 && 2 < 3);
    |                 +++++
  
  Error: Could not compile 'chain.slick' due to 1 error
  [1]

Only calls can be statements.

  $ cat > nothing.slick <<'EOF'
  > main :: fn() {
  >     1 + 2;
  > }
  > EOF
  $ slick run nothing.slick
  Error: This expression does nothing
   --> nothing.slick:2:5
    |
  2 |     1 + 2;
    |     ^^^^^ Its value is not used
    |
  Help: Only calls can be statements. To keep the value, give it a name: 'value := 1 + 2;'.
  
  Error: Could not compile 'nothing.slick' due to 1 error
  [1]

Malformed expressions.

  $ cat > paren.slick <<'EOF'
  > main :: fn() {
  >     print((1 + 2);
  > }
  > EOF
  $ slick run paren.slick
  Error: Unclosed '('
   --> paren.slick:2:18
    |
  2 |     print((1 + 2));
    |                  + Expected ')'
  
  Error: Could not compile 'paren.slick' due to 1 error
  [1]

A ')' missing at the end of a line is reported there, not at the start of
the next line. The missing ')' is shown in place, with '+' under it.

  $ cat > paren_eol.slick <<'EOF'
  > fib :: fn(n: i32) -> i32 { return n; }
  > main :: fn() {
  >     i : mut = 0;
  >     print(fib(i)
  >     i += 1;
  > }
  > EOF
  $ slick run paren_eol.slick
  Error: Unclosed '('
   --> paren_eol.slick:4:17
    |
  4 |     print(fib(i))
    |                 + Expected ')'
  
  Error: Could not compile 'paren_eol.slick' due to 1 error
  [1]

  $ cat > missing_operand.slick <<'EOF'
  > main :: fn() {
  >     print(1 +);
  > }
  > EOF
  $ slick run missing_operand.slick
  Error: Expected an expression, found ')'
   --> missing_operand.slick:2:14
    |
  2 |     print(1 +);
    |              ^ Expected an expression
  
  Error: Could not compile 'missing_operand.slick' due to 1 error
  [1]

print takes one or two arguments. The second, a precision, only applies to
floats.

  $ cat > print_two.slick <<'EOF'
  > main :: fn() {
  >     print(1, 2);
  > }
  > EOF
  $ slick run print_two.slick
  Error: A precision only applies to floats
   --> print_two.slick:2:14
    |
  2 |     print(1, 2);
    |           - This is i32
    |              ^ Precision
  
  Error: Could not compile 'print_two.slick' due to 1 error
  [1]

  $ cat > print_none.slick <<'EOF'
  > main :: fn() {
  >     print();
  > }
  > EOF
  $ slick run print_none.slick
  Error: 'print' expects 1 or 2 arguments, found 0
   --> print_none.slick:2:10
    |
  2 |     print();
    |          ^^ Found 0 arguments
  
  Error: Could not compile 'print_none.slick' due to 1 error
  [1]

A comparison used as a statement was probably meant as an assignment.

  $ cat > eq_stmt.slick <<'EOF'
  > main :: fn() {
  >     x : mut = 0;
  >     x == 1;
  > }
  > EOF
  $ slick run eq_stmt.slick
  Error: This expression does nothing
   --> eq_stmt.slick:3:5
    |
  3 |     x == 1;
    |     ^^^^^^ Its value is not used
    |
  Help: To assign, use '='
    |
  3 |     x = 1;
    |       ~
  
  Error: Could not compile 'eq_stmt.slick' due to 1 error
  [1]

'&' and '|' are bitwise operators, so on bools they suggest '&&' and '||'.

  $ cat > amp.slick <<'EOF'
  > main :: fn() {
  >     if true & false { }
  > }
  > EOF
  $ slick run amp.slick
  Error: Operator '&' does not work on bool
   --> amp.slick:2:13
    |
  2 |     if true & false { }
    |             ^
    |
  Help: For a logical and, use '&&'
    |
  2 |     if true && false { }
    |             ~~
  
  Error: Could not compile 'amp.slick' due to 1 error
  [1]

  $ cat > pipe.slick <<'EOF'
  > main :: fn() {
  >     if true | false { }
  > }
  > EOF
  $ slick run pipe.slick
  Error: Operator '|' does not work on bool
   --> pipe.slick:2:13
    |
  2 |     if true | false { }
    |             ^
    |
  Help: For a logical or, use '||'
    |
  2 |     if true || false { }
    |             ~~
  
  Error: Could not compile 'pipe.slick' due to 1 error
  [1]

