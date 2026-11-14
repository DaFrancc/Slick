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

A literal must fit in i32. 2147483648 only fits when negated.

  $ cat > big.slick <<'EOF'
  > main :: fn() {
  >     print(2147483648);
  > }
  > EOF
  $ slick run big.slick
  big.slick:2:11: error: integer literal 2147483648 does not fit in i32
  [1]

  $ cat > huge.slick <<'EOF'
  > main :: fn() {
  >     print(99999999999999999999999);
  > }
  > EOF
  $ slick run huge.slick
  huge.slick:2:11: error: integer literal 99999999999999999999999 does not fit in i32
  [1]

  $ cat > hex.slick <<'EOF'
  > main :: fn() {
  >     print(0x10);
  > }
  > EOF
  $ slick run hex.slick
  hex.slick:2:11: error: '0x10' is not a valid integer literal
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
  divzero.slick:3: panic: division by zero
  [1]

  $ cat > remzero.slick <<'EOF'
  > main :: fn() {
  >     print(1);
  >     print(1 % 0);
  > }
  > EOF
  $ slick run remzero.slick
  1
  remzero.slick:3: panic: remainder by zero
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

  $ cat > print_bool.slick <<'EOF'
  > main :: fn() {
  >     print(true);
  > }
  > EOF
  $ slick run print_bool.slick
  print_bool.slick:2:11: error: argument 1 of 'print' expects i32, found bool
  [1]

  $ cat > add_bool.slick <<'EOF'
  > main :: fn() {
  >     print(1 + true);
  > }
  > EOF
  $ slick run add_bool.slick
  add_bool.slick:2:13: error: operator '+' expects i32 operands, found i32 and bool
  [1]

  $ cat > less_bool.slick <<'EOF'
  > main :: fn() {
  >     print(false < 1);
  > }
  > EOF
  $ slick run less_bool.slick
  less_bool.slick:2:17: error: operator '<' expects i32 operands, found bool and i32
  [1]

  $ cat > not_int.slick <<'EOF'
  > main :: fn() {
  >     print(!1);
  > }
  > EOF
  $ slick run not_int.slick
  not_int.slick:2:11: error: operator '!' expects bool, found i32
  [1]

  $ cat > neg_bool.slick <<'EOF'
  > main :: fn() {
  >     print(-true);
  > }
  > EOF
  $ slick run neg_bool.slick
  neg_bool.slick:2:11: error: operator '-' expects i32, found bool
  [1]

  $ cat > eq_mixed.slick <<'EOF'
  > main :: fn() {
  >     print(1 == true);
  > }
  > EOF
  $ slick run eq_mixed.slick
  eq_mixed.slick:2:13: error: operator '==' needs both sides to have the same type, found i32 and bool
  [1]

  $ cat > and_int.slick <<'EOF'
  > main :: fn() {
  >     print(true && 1);
  > }
  > EOF
  $ slick run and_int.slick
  and_int.slick:2:16: error: operator '&&' expects bool operands, found bool and i32
  [1]

  $ cat > cmp_result.slick <<'EOF'
  > main :: fn() {
  >     print(1 == 1);
  > }
  > EOF
  $ slick run cmp_result.slick
  cmp_result.slick:2:11: error: argument 1 of 'print' expects i32, found bool
  [1]

Comparisons cannot be chained.

  $ cat > chain.slick <<'EOF'
  > main :: fn() {
  >     print(1 < 2 < 3);
  > }
  > EOF
  $ slick run chain.slick
  chain.slick:2:17: error: comparisons cannot be chained; combine them with '&&'
  [1]

Only calls can be statements.

  $ cat > nothing.slick <<'EOF'
  > main :: fn() {
  >     1 + 2;
  > }
  > EOF
  $ slick run nothing.slick
  nothing.slick:2:5: error: this expression does nothing; only calls can be used as statements
  [1]

Malformed expressions.

  $ cat > paren.slick <<'EOF'
  > main :: fn() {
  >     print((1 + 2);
  > }
  > EOF
  $ slick run paren.slick
  paren.slick:2:18: error: expected ')', found ';'
  [1]

  $ cat > missing_operand.slick <<'EOF'
  > main :: fn() {
  >     print(1 +);
  > }
  > EOF
  $ slick run missing_operand.slick
  missing_operand.slick:2:14: error: expected an expression, found ')'
  [1]

Argument counts for print.

  $ cat > print_two.slick <<'EOF'
  > main :: fn() {
  >     print(1, 2);
  > }
  > EOF
  $ slick run print_two.slick
  print_two.slick:2:5: error: 'print' expects 1 argument, found 2
  [1]

  $ cat > print_none.slick <<'EOF'
  > main :: fn() {
  >     print();
  > }
  > EOF
  $ slick run print_none.slick
  print_none.slick:2:5: error: 'print' expects 1 argument, found 0
  [1]
