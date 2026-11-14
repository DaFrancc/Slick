Stage 5: parameters, return values, recursion, and call checking.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

The milestone's acceptance test: recursive fib for 0 to 9.

  $ slick run ../examples/fib.slick
  0
  1
  1
  2
  3
  5
  8
  13
  21
  34

A function can be used before its definition.

  $ cat > forward.slick <<'EOF'
  > main :: fn() { print(double(21)); }
  > double :: fn(n: i32) -> i32 { return n * 2; }
  > EOF
  $ slick run forward.slick
  42

Mutual recursion.

  $ cat > mutual.slick <<'EOF'
  > is_even :: fn(n: i32) -> bool {
  >     if n == 0 { return true; }
  >     return is_odd(n - 1);
  > }
  > is_odd :: fn(n: i32) -> bool {
  >     if n == 0 { return false; }
  >     return is_even(n - 1);
  > }
  > main :: fn() {
  >     if is_even(10) { print(1); } else { print(0); }
  >     if is_odd(7) { print(1); } else { print(0); }
  >     if is_even(7) { print(1); } else { print(0); }
  > }
  > EOF
  $ slick run mutual.slick
  1
  1
  0

Arguments arrive in order, including grouped parameters.

  $ cat > args.slick <<'EOF'
  > sub :: fn(a: i32, b: i32) -> i32 { return a - b; }
  > pick :: fn(a, b: i32, flag: bool) -> i32 {
  >     if flag { return a; }
  >     return b;
  > }
  > main :: fn() {
  >     print(sub(10, 3));
  >     print(pick(1, 2, true));
  >     print(pick(1, 2, false));
  > }
  > EOF
  $ slick run args.slick
  7
  1
  2

A 'mut' parameter is the callee's own copy. 'mut' applies to every name in its
group.

  $ cat > mut_param.slick <<'EOF'
  > bump :: fn(n: mut i32) -> i32 {
  >     n += 1;
  >     return n;
  > }
  > both :: fn(a, b: mut i32) -> i32 {
  >     a += 1;
  >     b += 1;
  >     return a + b;
  > }
  > main :: fn() {
  >     x := 5;
  >     print(bump(x));
  >     print(x);
  >     print(both(1, 2));
  > }
  > EOF
  $ slick run mut_param.slick
  6
  5
  5

Parameters without 'mut' cannot be assigned to.

  $ cat > param_immutable.slick <<'EOF'
  > f :: fn(n: i32) {
  >     n = 2;
  > }
  > main :: fn() { f(1); }
  > EOF
  $ slick run param_immutable.slick
  param_immutable.slick:2:5: error: cannot assign to parameter 'n': it was declared without 'mut' on line 1
  [1]

A call that returns a value can be a statement, and its result is dropped.

  $ cat > drop.slick <<'EOF'
  > loud :: fn(n: i32) -> i32 {
  >     print(n);
  >     return n;
  > }
  > main :: fn() { loud(3); }
  > EOF
  $ slick run drop.slick
  3

Early returns, from inside a loop and from a void function.

  $ cat > early.slick <<'EOF'
  > first_over :: fn(limit: i32) -> i32 {
  >     i : mut = 0;
  >     while true {
  >         if i * i > limit { return i; }
  >         i += 1;
  >     }
  >     return -1;
  > }
  > countdown :: fn(n: i32) {
  >     i : mut = n;
  >     while true {
  >         if i == 0 { return; }
  >         print(i);
  >         i -= 1;
  >     }
  > }
  > main :: fn() {
  >     print(first_over(50));
  >     countdown(3);
  >     return;
  >     print(99);
  > }
  > EOF
  $ slick run early.slick
  8
  3
  2
  1

Return-path analysis accepts these: both branches return, every arm of a chain
returns, a nested block returns, and code after a return.

  $ cat > returns_ok.slick <<'EOF'
  > sign :: fn(n: i32) -> i32 {
  >     if n > 0 {
  >         return 1;
  >     } else if n < 0 {
  >         return -1;
  >     } else {
  >         return 0;
  >     }
  > }
  > both :: fn(b: bool) -> i32 {
  >     if b { return 1; } else { return 2; }
  > }
  > nested :: fn() -> i32 {
  >     {
  >         return 3;
  >     }
  > }
  > after :: fn() -> i32 {
  >     return 4;
  >     print(5);
  > }
  > main :: fn() {
  >     print(sign(-7));
  >     print(sign(0));
  >     print(sign(7));
  >     print(both(false));
  >     print(nested());
  >     print(after());
  > }
  > EOF
  $ slick run returns_ok.slick
  -1
  0
  1
  2
  3
  4

And rejects these. The error points at the '}' that ends the function.

  $ cat > missing_end.slick <<'EOF'
  > f :: fn(n: i32) -> i32 {
  >     print(n);
  > }
  > main :: fn() { print(f(1)); }
  > EOF
  $ slick run missing_end.slick
  missing_end.slick:3:1: error: 'f' is missing a return: not every path returns a value
  [1]

  $ cat > missing_branch.slick <<'EOF'
  > f :: fn(n: i32) -> i32 {
  >     if n > 0 {
  >         return 1;
  >     } else {
  >         print(n);
  >     }
  > }
  > main :: fn() { print(f(1)); }
  > EOF
  $ slick run missing_branch.slick
  missing_branch.slick:7:1: error: 'f' is missing a return: not every path returns a value
  [1]

  $ cat > missing_else.slick <<'EOF'
  > f :: fn(n: i32) -> i32 {
  >     if n > 0 {
  >         return 1;
  >     } else if n < 0 {
  >         return -1;
  >     }
  > }
  > main :: fn() { print(f(1)); }
  > EOF
  $ slick run missing_else.slick
  missing_else.slick:7:1: error: 'f' is missing a return: not every path returns a value
  [1]

A return inside a loop does not count, even when the loop never ends.

  $ cat > missing_loop.slick <<'EOF'
  > f :: fn() -> i32 {
  >     while true {
  >         return 1;
  >     }
  > }
  > main :: fn() { print(f()); }
  > EOF
  $ slick run missing_loop.slick
  missing_loop.slick:5:1: error: 'f' is missing a return: not every path returns a value
  [1]

A return must match the function's return type.

  $ cat > return_no_value.slick <<'EOF'
  > f :: fn() -> i32 {
  >     return;
  > }
  > main :: fn() { print(f()); }
  > EOF
  $ slick run return_no_value.slick
  return_no_value.slick:2:5: error: 'f' returns i32, but this 'return' has no value
  [1]

  $ cat > return_value_void.slick <<'EOF'
  > g :: fn() {
  >     return 1;
  > }
  > main :: fn() { g(); }
  > EOF
  $ slick run return_value_void.slick
  return_value_void.slick:2:12: error: 'g' returns nothing, but this 'return' has a value
  [1]

  $ cat > return_type.slick <<'EOF'
  > h :: fn() -> i32 {
  >     return true;
  > }
  > main :: fn() { print(h()); }
  > EOF
  $ slick run return_type.slick
  return_type.slick:2:12: error: 'h' returns i32, but this 'return' has a value of type bool
  [1]

Calls must match the function's parameters.

  $ cat > too_few.slick <<'EOF'
  > sub :: fn(a: i32, b: i32) -> i32 { return a - b; }
  > main :: fn() {
  >     print(sub(1));
  > }
  > EOF
  $ slick run too_few.slick
  too_few.slick:3:11: error: 'sub' expects 2 arguments, found 1
  [1]

  $ cat > too_many.slick <<'EOF'
  > one :: fn(a: i32) { }
  > main :: fn() {
  >     one(1, 2);
  > }
  > EOF
  $ slick run too_many.slick
  too_many.slick:3:5: error: 'one' expects 1 argument, found 2
  [1]

  $ cat > arg_type.slick <<'EOF'
  > sub :: fn(a: i32, b: i32) -> i32 { return a - b; }
  > main :: fn() {
  >     print(sub(1, true));
  > }
  > EOF
  $ slick run arg_type.slick
  arg_type.slick:3:18: error: argument 2 of 'sub' expects i32, found bool
  [1]

Locals and parameters are not functions, and functions are not values yet.

  $ cat > call_local.slick <<'EOF'
  > main :: fn() {
  >     x := 1;
  >     x();
  > }
  > EOF
  $ slick run call_local.slick
  call_local.slick:3:5: error: 'x' is not a function
  [1]

  $ cat > call_param.slick <<'EOF'
  > f :: fn(n: i32) -> i32 {
  >     return n(1);
  > }
  > main :: fn() { print(f(1)); }
  > EOF
  $ slick run call_param.slick
  call_param.slick:2:12: error: 'n' is not a function
  [1]

  $ cat > fn_value.slick <<'EOF'
  > helper :: fn() { }
  > main :: fn() {
  >     y := helper;
  > }
  > EOF
  $ slick run fn_value.slick
  fn_value.slick:3:10: error: 'helper' cannot be used as a value yet
  [1]

A function that returns nothing has no value to use.

  $ cat > void_value.slick <<'EOF'
  > helper :: fn() { }
  > main :: fn() {
  >     x := helper();
  > }
  > EOF
  $ slick run void_value.slick
  void_value.slick:3:10: error: 'helper' returns nothing and cannot be used as a value
  [1]

  $ cat > print_value.slick <<'EOF'
  > main :: fn() {
  >     print(print(1));
  > }
  > EOF
  $ slick run print_value.slick
  print_value.slick:2:11: error: 'print' returns nothing and cannot be used as a value
  [1]

No shadowing applies to parameters: a local cannot reuse a parameter's name
at any depth, two parameters cannot share a name, and a parameter cannot take
a function's name.

  $ cat > local_param.slick <<'EOF'
  > f :: fn(n: i32) {
  >     n := 1;
  > }
  > main :: fn() { f(1); }
  > EOF
  $ slick run local_param.slick
  local_param.slick:2:5: error: 'n' is already declared on line 1
  [1]

  $ cat > local_param_nested.slick <<'EOF'
  > f :: fn(n: i32) {
  >     if true {
  >         n := 2;
  >     }
  > }
  > main :: fn() { f(1); }
  > EOF
  $ slick run local_param_nested.slick
  local_param_nested.slick:3:9: error: 'n' is already declared on line 1
  [1]

  $ cat > dup_param.slick <<'EOF'
  > f :: fn(a: i32, a: i32) { }
  > main :: fn() { f(1, 2); }
  > EOF
  $ slick run dup_param.slick
  dup_param.slick:1:17: error: 'a' is already declared on line 1
  [1]

  $ cat > param_fn_name.slick <<'EOF'
  > f :: fn(main: i32) { }
  > main :: fn() { f(1); }
  > EOF
  $ slick run param_fn_name.slick
  param_fn_name.slick:1:9: error: 'main' is already declared as a function on line 2
  [1]

Names are per function: two functions can each have a parameter 'n' and a
local 'i'.

  $ cat > per_function.slick <<'EOF'
  > sum_to :: fn(n: i32) -> i32 {
  >     i : mut = 0;
  >     s : mut = 0;
  >     while i <= n {
  >         s += i;
  >         i += 1;
  >     }
  >     return s;
  > }
  > count_down :: fn(n: i32) {
  >     i : mut = n;
  >     while i > 0 {
  >         print(i);
  >         i -= 1;
  >     }
  > }
  > main :: fn() {
  >     print(sum_to(4));
  >     count_down(2);
  > }
  > EOF
  $ slick run per_function.slick
  10
  2
  1

Function names that mean something in C.

  $ cat > c_fn_names.slick <<'EOF'
  > printf :: fn(n: i32) -> i32 { return n + 1; }
  > int :: fn() -> i32 { return 3; }
  > main2 :: fn() { print(2); }
  > exit :: fn() { print(4); }
  > main :: fn() {
  >     print(printf(1));
  >     print(int());
  >     main2();
  >     exit();
  > }
  > EOF
  $ slick run c_fn_names.slick
  2
  3
  2
  4

Deep recursion.

  $ cat > deep.slick <<'EOF'
  > sum :: fn(n: i32) -> i32 {
  >     if n == 0 { return 0; }
  >     return n + sum(n - 1);
  > }
  > main :: fn() { print(sum(10000)); }
  > EOF
  $ slick run deep.slick
  50005000

Unknown parameter and return types.

  $ cat > param_type.slick <<'EOF'
  > f :: fn(n: Foo) { }
  > main :: fn() { }
  > EOF
  $ slick run param_type.slick
  param_type.slick:1:12: error: unknown type 'Foo'
  [1]

  $ cat > ret_type.slick <<'EOF'
  > f :: fn() -> Bar { }
  > main :: fn() { }
  > EOF
  $ slick run ret_type.slick
  ret_type.slick:1:14: error: unknown type 'Bar'
  [1]
