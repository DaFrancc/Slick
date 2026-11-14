# Milestone 0 implementation plan

Plan for the executing agent. Read `Slick Design Decisions.md` first; it is the
source of truth and this plan only fills in what it leaves open for Milestone 0.

"First milestone" is taken to mean **Milestone 0** in the design doc (the repo
contains no code yet): a minimal Turing-complete core pushed through the whole
pipeline, ending with recursive `fib` printed for 0 to 9.

## 1. What gets built

A command-line compiler, `slick`, written in plain OCaml, that turns one
`.slick` file into a native executable by emitting C and calling the system C
compiler.

```
main.slick --lex--> tokens --parse--> AST --check--> annotated AST --emit--> main.c --cc--> ./main
```

- No LLVM, no assembly, no IR. The backend is C text handed to `cc`. This is
  locked in the design doc ("emits C", "call `cc`"); a real IR and own codegen
  are Milestone 5.
- One error is reported per run: the compiler prints it and exits.
- No dependencies beyond the OCaml standard library and dune.

### Done when

1. `dune build` and `dune test` pass from a clean checkout, with no warnings.
2. `slick run examples/fib.slick` prints `0 1 1 2 3 5 8 13 21 34`, one per line.
3. Every diagnostic the compiler can produce has a test that expects its text.
4. Every passing test program's generated C compiles with
   `-Wall -Wextra -Werror -Wno-unused` under both gcc and clang.
5. `README.md` says how to build, test and run.

## 2. Prerequisites

Checked on this machine (Fedora 45) on 2026-11-14. There are two OCaml
toolchains installed:

| Toolchain | Contents | Where it is on `PATH` |
| --- | --- | --- |
| opam switch `default` | OCaml 5.4.1, dune 3.25.0, ocamlformat 0.29.0 | the programmer's interactive terminal |
| Fedora packages | OCaml 5.5.1, dune 3.24.2 | non-interactive shells, including the agent's |

`gcc` 16.2.1 and `clang` 23.1.5 are installed. `ocaml-lsp-server` is not.

**Use the opam switch for everything**, so the agent builds with the same
compiler the programmer's terminal and editor use. Run every OCaml command
through `opam exec --`:

```
opam exec -- dune build
opam exec -- dune test
opam exec -- dune exec slick -- run examples/fib.slick
```

Check `opam exec -- dune --version` prints 3.25.0 before starting. If it
fails, stop and ask; do not install packages yourself. Mixing the two
toolchains in one `_build` directory works but forces a full rebuild on every
switch.

Add a `.ocamlformat` file containing `version = 0.29.0` and keep the code
formatted with `opam exec -- dune fmt`.

## 3. Decisions made while planning

### Decided by the programmer (2026-11-14)

These are settled. P1 and P2 are recorded in the design doc. P3 applies to
this milestone only.

| # | Decision |
| --- | --- |
| P1 | Statements end with `;`. Newlines are plain whitespace. |
| P2 | No shadowing. A name cannot be declared while the same name is visible. |
| P3 | The agent writes every part of Milestone 0, the checker included. |

### Defaults chosen by this plan

The design doc does not decide these. The plan picks a default for each so
work can proceed. Do not edit the design doc; list these in the final report
so the programmer can accept or overrule them.

| # | Question | Default for M0 |
| --- | --- | --- |
| D1 | Logical operator spelling | `&&`, `\|\|`, `!` |
| D2 | Remainder operator | `%` and `%=` exist for integers |
| D3 | Precedence, low to high | `\|\|`, `&&`, comparisons, `+ -`, `* / %`, unary `- !`, call |
| D4 | Chained comparison `a < b < c` | Parse error |
| D5 | Integer overflow | Wraps (two's complement), via `-fwrapv` |
| D6 | Division | Truncates toward zero. Divide or remainder by zero is a runtime panic. `MIN / -1` wraps to `MIN`, `MIN % -1` is `0`. |
| D7 | Evaluation order | Strictly left to right, for operands and call arguments. Confirmed by the programmer on 2026-11-14; no longer open. |
| D8 | `print` | Prints the `i32` in decimal followed by a newline |
| D9 | `main` | `main :: fn() { }`, no parameters, no return value. Process exits 0. |
| D10 | Declaration order | Top-level functions can be used before their definition |
| D11 | Expression statements | Only calls. `a + b;` on its own is an error. |
| D12 | Unused call results | Allowed (`#must_use` comes later) |
| D13 | Diagnostic format | `path:line:col: error: message`, path as typed on the command line |
| D14 | Runtime panic | `path:line: panic: message` on stderr, exit code 1 |
| D15 | Where `;` goes | After every declaration, assignment, call statement and `return`, including the last one before `}`. Not after the `}` of a block, `if`, `while` or function definition. A `;` with no statement is an error. |
| D16 | What counts as shadowing | Any visible local or parameter, any top-level function, and `print`. Two blocks that do not nest may reuse a name. |

## 4. Scope

### In

- Types `i32` and `bool`.
- Top level: function definitions only, `name :: fn(params) -> T { ... }`.
- Parameters, grouped (`a, b: i32`) and optionally `mut` (`n: mut i32`).
- Local declarations: `x := e`, `x : T = e`, `x : mut = e`, `x : mut T = e`,
  and `x : T` / `x : mut T` (zero-initialized).
- Assignment `=` and compound `+= -= *= /= %=`, with the immutability check.
- Integer literals in decimal with `_` separators; `true`, `false`.
- Operators: `+ - * / %`, unary `-`, `== != < <= > >=`, `&& || !`, parentheses.
- `if` / `else if` / `else`, `while`, nested `{ }` blocks, `return`.
- Calls, recursion, mutual recursion, forward references.
- Built-in `print(i32)`.
- Line comments `//`.

### Out (do not build, however natural it looks)

Everything else in the design doc, in particular: other numeric types, casts,
hex and float literals, structs, pointers, arrays, slices, strings, `for`,
`loop`, `break`, `continue`, `match`, `defer`, top-level constants and
variables, function values, generics, attributes, modules, UFCS, `?T`,
bitwise operators, multiple returns.

Reserve the keywords the design doc already uses (`for in loop break continue
match struct enum defer errdefer try import as cast bitcast`) so that using
one as a name fails now, with `'for' is not supported yet`.

## 5. Language rules for M0

### 5.1 Semicolons (P1, D15)

Newlines are whitespace; the lexer has no newline token. Every declaration,
assignment, call statement and `return` ends with `;`. Nothing follows the `}`
of a block, `if`, `while` or function definition.

```
fib :: fn(n: i32) -> i32 {
    if n < 2 { return n; }
    return fib(n - 1) + fib(n - 2);
}

main :: fn() {
    i : mut = 0;
    while i < 10 {
        print(fib(i));
        i += 1;
    }
}
```

A missing `;` is the most common mistake a user will make, so report it where
the statement ended, not at the next token (which is usually on the next
line). Each token records its end position as well as its start; the error
points just past the last token of the statement.

### 5.2 Grammar

```
file        = { top_decl } EOF
top_decl    = IDENT "::" "fn" "(" [ params ] ")" [ "->" type ] block
params      = param_group { "," param_group }
param_group = IDENT { "," IDENT } ":" [ "mut" ] type
type        = IDENT                       // resolved by the checker: i32, bool
block       = "{" { stmt } "}"
stmt        = decl | if | while | return | block | simple
decl        = IDENT ":=" expr ";"
            | IDENT ":" [ "mut" ] [ type ] [ "=" expr ] ";"   // needs a type or an initializer
if          = "if" expr block [ "else" ( if | block ) ]
while       = "while" expr block
return      = "return" [ expr ] ";"
simple      = expr [ ( "=" | "+=" | "-=" | "*=" | "/=" | "%=" ) expr ] ";"

expr        = or
or          = and { "||" and }
and         = cmp { "&&" cmp }
cmp         = add [ ( "==" | "!=" | "<" | "<=" | ">" | ">=" ) add ]
add         = mul { ( "+" | "-" ) mul }
mul         = unary { ( "*" | "/" | "%" ) unary }
unary       = ( "-" | "!" ) unary | primary
primary     = INT | "true" | "false" | IDENT [ "(" [ expr { "," expr } ] ")" ] | "(" expr ")"
```

Lex `:=` and `::` as single tokens.

### 5.3 Typing

- An integer literal is `i32`. It must fit; `-2147483648` is allowed (fold the
  negated literal in the checker). In the lexer, accumulate the digits by hand
  and report the range error as soon as the value passes 2147483648. Do not
  call `int_of_string`: it raises on a literal too large for OCaml's `int`.
- `+ - * / %` and unary `-` take `i32` and give `i32`. `< <= > >=` take `i32`
  and give `bool`. `== !=` take two `i32` or two `bool`. `&& || !` take `bool`.
- `if` and `while` conditions must be `bool`. There is no implicit conversion.
- A declaration with both a type and an initializer requires them to match.
- A function with a return type must return on every path. Use the simple
  rule: a block returns if its last statement is `return`, or an `if` with an
  `else` whose branches all return. Code after a `return` is allowed.
- One namespace, and no shadowing (P2, D16). Declaring a local or parameter is
  an error if the name is already visible: a parameter, a local in this block
  or any enclosing block, a top-level function, or `print`. A name becomes
  free again when its block ends, so two blocks that do not nest can both
  declare `i`.
- Calling a local and using a function name as a value are both errors in M0.

### 5.4 Diagnostics

Only the first message is fixed by the design doc. The rest are suggested
wording; keep them in this plain style and give each one a test.

```
cannot assign to 'count': it was declared without 'mut' on line 3
undeclared name 'x'
'x' is already declared on line 3
'fib' is already declared as a function on line 1
'x' needs a type or an initial value
unknown type 'Foo'
cannot initialize 'x' of type i32 with a value of type bool
cannot assign a value of type bool to 'x' of type i32
operator '+' expects i32 operands, found i32 and bool
operator '==' needs both sides to have the same type, found i32 and bool
operator '!' expects bool, found i32
condition of 'if' must be bool, found i32
integer literal 2147483648 does not fit in i32
unknown function 'f'
'x' is not a function
'f' cannot be used as a value yet
'f' expects 2 arguments, found 3
argument 2 of 'f' expects i32, found bool
'f' returns nothing and cannot be used as a value
'f' returns i32, but this 'return' has no value
'f' returns nothing, but this 'return' has a value
'f' returns i32, but this 'return' has a value of type bool
'f' is missing a return: not every path returns a value
function 'f' is already defined on line 3
'print' is a built-in function and cannot be redeclared
this expression does nothing; only calls can be used as statements
cannot assign to this expression
comparisons cannot be chained; combine them with '&&'
no 'main' function found
'main' must take no parameters and return nothing
unexpected character '@'
expected ';' at the end of this statement
unexpected ';'
expected ')', found '{'                // general parser form: expected X, found Y
'for' is not supported yet
```

## 6. Repository layout

```
dune-project            (lang dune 3.16), one package "slick"
.gitignore              _build/, *.install
README.md
bin/dune, bin/main.ml   CLI only: argument handling, calls Driver
src/dune                (library (name slick))
src/diag.ml             source locations, fatal error reporting
src/token.ml            token type, display names
src/lexer.ml            string -> token array
src/ast.ml              AST types
src/parser.ml           token array -> AST
src/check.ml            name resolution, types, mutability, returns
src/emit_c.ml           annotated AST -> C text, plus the C prelude
src/driver.ml           read file, run phases, write C, invoke cc, run
examples/fib.slick
test/dune               cram tests
test/*.t/               one directory test per area, with .slick fixtures
plans/
```

### CLI

```
slick build FILE [-o OUT]     compile to ./<basename> or OUT
slick run FILE                compile to a temp file, run it, exit with its code
slick build FILE --emit-c     print the generated C to stdout, do not call cc
```

- C compiler is `$CC` if set, else `cc`. Flags: `-std=c11 -fwrapv`, then
  `$SLICK_CFLAGS` if set.
- Exit codes: 0 success, 1 compile error, 2 usage error, 3 if `cc` rejects the
  generated C. In that last case keep the `.c` file and print its path; it is
  a compiler bug.
- Use `Sys.command` with `Filename.quote` and `Filename.temp_file`. No `unix`
  library.

## 7. OCaml conventions

The design doc requires OCaml plain enough to port to Slick line by line.
Slick has no closures, exceptions, functors or garbage-collected tricks.

- Use variants, records (with `mutable` fields for state), `match`, arrays,
  lists, `Hashtbl` with string keys, `Buffer`, `Printf`.
- Do not use functors (`Map.Make`, `Set.Make`), GADTs, objects, polymorphic
  variants, first-class modules, labelled or optional arguments, ppx,
  ocamllex or menhir.
- Do not use exceptions for control flow. `Diag.fatal loc msg` prints the
  diagnostic and calls `exit 1`; it has type `loc -> string -> 'a`.
- Prefer named recursive functions and loops to anonymous functions that
  capture locals. `List.iter f xs` with a named `f` is fine.
- The lexer and parser are hand-written: a token array plus a `mutable pos`,
  recursive descent with one function per grammar rule.
- The checker annotates the AST in place through `mutable` fields (expression
  type, resolved symbol) instead of building a second tree.
- Leave dune's default dev warnings on. Fix warnings, do not disable them.

Starting shape for the AST (adjust as needed):

```ocaml
type ty = I32 | Bool | Void

type symbol = {                 (* one per parameter or local, made by the checker *)
  sym_name : string;
  sym_ty : ty;
  sym_mut : bool;
  sym_loc : Diag.loc;
  sym_id : int;                 (* unique within the function, used for C names *)
}

type expr = { kind : expr_kind; loc : Diag.loc; mutable ty : ty }
and expr_kind =
  | Int of int
  | BoolLit of bool
  | Var of var_ref              (* { name; mutable sym : symbol option } *)
  | Call of call                (* { callee; args; mutable has_call ... } *)
  | Unary of unop * expr
  | Binary of binop * expr * expr
```

## 8. C emission

### 8.1 Shape of the output

```c
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

static void slickrt_print_i32(int32_t v) { printf("%d\n", v); }
static void slickrt_panic(const char *file, int line, const char *msg) { ... }
static int32_t slickrt_div_i32(int32_t a, int32_t b, const char *file, int line) { ... }
static int32_t slickrt_rem_i32(int32_t a, int32_t b, const char *file, int line) { ... }

static int32_t slick_fib(int32_t n_1);      /* prototypes for every function first */
static void slick_main(void);

static int32_t slick_fib(int32_t n_1) { ... }
static void slick_main(void) { ... }

int main(void) { slick_main(); return 0; }
```

### 8.2 Names

- User function `f` becomes `slick_f`. Runtime helpers are `slickrt_*`, which
  no user function can collide with.
- Every parameter and local becomes `<name>_<id>`, with `id` unique within the
  function; compiler temporaries are `tmp_<id>` from the same counter. This
  avoids C keywords (a local named `int` or `register`) and keeps user names
  apart from temporaries (a local named `tmp`).

### 8.3 Left-to-right evaluation (D7)

C does not fix the order in which call arguments or the operands of `+` are
evaluated, and gcc and clang differ in practice. Emitting `f(a(), b())`
directly would make Slick's order depend on the C compiler.

`emit_expr` returns a C expression string and may first append statements to
the current output (declarations of temporaries). Rules:

- A call that returns a value is always stored in a fresh temporary, and the
  temporary is the result: `int32_t tmp_7 = slick_f(a_1, b_2);`.
- In `a op b` and in an argument list, if a later operand contains a call,
  the earlier operand is stored in a temporary first, unless it is a literal
  or already a temporary. Pointers arrive in Milestone 1, after which a call
  can change a variable read earlier in the same expression; build the
  general rule now.
- `a && b` where `b` contains a call cannot be a C `&&`, because `b`'s
  temporaries would run unconditionally. Emit
  `bool tmp = a; if (tmp) { <b's statements> tmp = b; }` and likewise with
  `if (!tmp)` for `||`. When `b` has no call, emit a plain C `&&` or `||`.
- `if` whose condition produced statements: emit them before the `if`. For
  `else if`, nest: `else { <statements> if (...) { } else { } }`.
- `while` whose condition produced statements:
  `while (1) { <statements> if (!(cond)) break; <body> }`.
- Compound assignment is emitted as `x = x op e`, so `/=` and `%=` reuse the
  division helpers.

### 8.4 Traps that are easy to miss

- **Parentheses.** Parenthesize every non-atomic operand, never the whole
  expression. `if ((a == b))` makes clang warn by default.
- **`-2147483648`.** In C the literal `2147483648` is a `long`, so
  `(-2147483648) - 1` is computed in 64 bits and does not wrap. Emit the
  minimum as `INT32_MIN`.
- **Division.** `/` and `%` always go through `slickrt_div_i32` and
  `slickrt_rem_i32`, which check for zero and handle `INT32_MIN / -1` (a
  hardware trap on x86 if left to C).
- **Output order.** stdout is buffered when it is not a terminal, stderr is
  not. `slickrt_panic` must `fflush(stdout)` before writing, or tests will
  see the panic before earlier `print` output.
- **Zero-init.** `x : mut i32;` emits `int32_t x_1 = 0;` and `b : bool;`
  emits `bool b_2 = false;`, never an uninitialized C variable.
- **Unused C warnings.** A Slick program may legitimately have unused locals;
  that is why the strict test flags include `-Wno-unused`. If another warning
  fires on legitimate Slick code, drop that one warning from the test flags
  rather than bending the emitter.

## 9. Tests

All tests are dune cram tests under `test/`, running the real `slick` binary:
`(cram (deps %{bin:slick}))`, with the executable given a `public_name`.

Rules:

- **Write the test before the code**, with the expected output typed by hand.
- **Never run `dune promote` to make a test pass.** Promotion writes whatever
  the compiler currently prints into the expectation. Use it only for a diff
  you have read line by line and that is correct.
- Only write tests that fail when the behaviour is broken. A test that passes
  either way is worse than none.
- One error per fixture file, because the compiler stops at the first error.
- The snippets in the stage tables are abbreviated. Each fixture is a complete
  program with a `main`, and every statement in it ends with `;`.
- Start each `run.t` with
  `export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused"` so every program
  also checks the generated C.
- One test reruns the main programs (at least `fib` and the evaluation-order
  fixtures) with `CC=clang` and with `CC=gcc`. Guard it with
  `(enabled_if %{bin-available:clang})`.

## 10. Stages

Vertical slices: each stage adds a feature through every phase, lexer to C, so
there is a running compiler after stage 1 and every test is end to end. Finish
and verify one stage before starting the next.

### Stage 0: scaffolding

Create the dune project, an empty library, a `slick` executable that prints
usage and exits 2, `.gitignore`, and one cram test for the usage message.

This stage exists to prove the harness. Confirm that the cram test finds
`slick` on its path, that a directory test can read its fixture files, and
that a deliberately wrong expectation fails. If a shared fixtures directory
does not work with cram's sandbox, keep fixtures inside each test directory.

### Stage 1: walking skeleton

Goal: `main :: fn() { print(42); }` compiles and runs.

Build: `Diag` with locations; lexer with identifiers, keywords, integer
literals, punctuation and `//` comments; parser for parameterless functions
and call statements; checker with a function table, the built-in `print`, and
the `main` checks; emitter with the prelude; driver and CLI (`build`, `run`,
`-o`, `--emit-c`), including the `cc` failure path.

| Test first | Catches |
| --- | --- |
| `print(42);` prints `42` | any phase not wired up |
| three `print` calls print in order, written on three lines and again on one line | statements lost or reordered; newlines mattering when they should not |
| `print(\n 1\n);` across lines | a newline treated as more than whitespace |
| comment-only lines, trailing comments, a comment on the last line with no final newline | comment handling at end of line and end of file |
| `print(1)` with no `;`, followed by another statement on the next line | missing-`;` error, reported at the end of line 1, not at line 2 |
| `print(1)` with no `;` as the last statement before `}` | `;` is required before `}` (D15) |
| a lone `;` in a block; `};` after a function body | stray-`;` error |
| file with no `main` | missing-main check |
| `main` with a parameter or a return type | main signature check |
| two functions with the same name; redefining `print` | duplicate detection |
| `@` in the source | lexer error with correct line and column |
| nonexistent input file, no arguments, unknown subcommand | usage paths and exit code 2 |
| `slick build` then run the output; `-o` | output naming |
| `slick run` on a program, then check `$?` is 0 | exit code propagation |

### Stage 2: expressions

Build: all operators, precedence, parentheses, `_` in literals, `true` and
`false`, operand type checks, literal range check, the division helpers.
`print` only takes `i32`, so observe booleans through `if` once stage 4
exists; in this stage test them through type errors.

| Test first | Catches |
| --- | --- |
| `print(1 + 2 * 3)` is 7, `print((1 + 2) * 3)` is 9 | precedence |
| `print(10 - 4 - 3)` is 3, `print(100 / 10 / 5)` is 2 | associativity |
| `print(-2 * 3)`, `print(- -5)`, `print(2 - -3)` | unary minus binding |
| `print(-7 / 2)` is -3, `print(-7 % 2)` is -1 | D6 truncation |
| `print(1_000_000)` | digit separators |
| `print(2147483647 + 1)` is -2147483648 | D5 wrapping |
| `print(-2147483648)` and `print(-2147483648 - 1)` is 2147483647 | the `INT32_MIN` trap in 8.4 |
| `print(2147483648)`; `print(99999999999999999999999)` | literal range error, including a literal too large for OCaml's `int` |
| `print(1 / 0)` and `print(1 % 0)` after an earlier `print` | runtime panic, message, exit code 1, output order |
| `print(true)`, `print(1 + true)`, `print(!1)`, `print(-true)`, `print(1 == true)`, `print(1 < 2 < 3)` | each operand type error and the chained-comparison error |
| `1 + 2;` as a statement | D11 |
| `print(10\n - 4);` is 6, with the line broken before the operator | the second line parsed as a new statement or a unary minus |

### Stage 3: locals and mutability

Build: all declaration forms, scopes as a stack of hash tables, symbols with
unique ids, assignment and compound assignment, the immutability check, the
no-shadowing check. Declaring a name searches the whole scope stack and the
function table, not only the innermost scope.

| Test first | Catches |
| --- | --- |
| each of the six declaration forms, value printed | declaration parsing, zero-init |
| `x := 1; x = 2;` | the design doc's immutability error, exact text and line |
| `x : i32 = 1; x += 1;` | compound assignment also checked |
| `x : mut = 1;` then each of `= += -= *= /= %=` | compound operators compute the right value |
| `x : mut = 5; x /= 0;` | compound division uses the helper |
| use before declaration; never declared | undeclared name |
| same name twice in one block | P2, same scope |
| inner block declares a name from an enclosing block | P2, nested scope; fails if only the innermost scope is searched |
| a name declared two blocks deep that exists in the outermost block | P2 through more than one level |
| two sibling blocks each declare `x`; both values print | sibling reuse is allowed (D16); fails if names are never released |
| `{ x := 1; }` then `x := 2;` after the block | a name is free again once its block ends |
| use of `x` after the block that declared it | scope exit |
| a local named `print`; a local named like a top-level function, defined before and after the use | P2 against functions, with forward references |
| locals named `int`, `double`, `register`, `tmp` | C name collisions |
| `x : bool = 1;`, `x : mut i32 = true;`, assigning `bool` to an `i32` | initializer and assignment type checks |
| `x : mut;` with no type or value; `x : Foo;` | declaration errors |
| `1 = 2;` | assignment target check |

### Stage 4: control flow

Build: `if` / `else if` / `else`, `while`, nested blocks, condition checks.

| Test first | Catches |
| --- | --- |
| `if`/`else` on a true and a false condition | branch selection |
| three-way `else if` chain, each arm hit once | chain parsing, dangling else |
| each comparison operator on equal, less and greater inputs | operator mapping |
| `&&`, `\|\|`, `!` truth tables through `if` | logical operators |
| `true \|\| false && false` takes the branch | `&&` binds tighter than `\|\|` |
| `while` counting 0 to 4; a `while` whose condition is false at once | loop, zero iterations |
| nested `while` loops with counters `i` and `j`; two loops in a row whose bodies each declare `t` | scoping inside loops, sibling reuse |
| a name declared in the `if` branch and again in the `else` branch | branches are sibling scopes |
| `if 1 { }`, `while 0 { }` | condition type errors |

### Stage 5: functions

Build: parameters (grouped, `mut`), return types, `return`, call checking,
two-pass checking for forward references, C prototypes, the return-path check.

| Test first | Catches |
| --- | --- |
| `examples/fib.slick` prints the ten values | the milestone's acceptance test |
| function defined after its caller | D10, prototypes |
| mutually recursive `is_even` / `is_odd` | prototypes, recursion |
| `sub(10, 3)` is 7 | argument order |
| grouped parameters `a, b: i32, flag: bool` | parameter group parsing |
| assigning to a plain parameter; assigning to a `mut` parameter | parameter immutability, and that `mut` does not leak to the caller |
| wrong argument count; wrong argument type; unknown function | call checks |
| calling a local; using a function name as a value | namespace errors |
| void function used in an expression | void-value error |
| the three `return` mismatches in 5.4 | return checks |
| missing return at the end; missing in one `if` branch; `if`/`else` both returning is accepted | return-path analysis, both directions |
| early `return` inside `while` | return from a nested scope |
| local with the same name as a parameter, at the top of the body and inside a nested block | P2 against parameters |
| two parameters with the same name; a parameter named like a function | P2 for parameters |
| two functions that each have a parameter `n` and a local `i` | names are per function, not global |
| function named `main2`, `printf`, `int` | C name collisions |
| recursion 10 000 deep (sum to n) | nothing quadratic or broken in call emission |

### Stage 6: evaluation order

Build: the rules in 8.3. Use a helper in the fixtures:
`noisy :: fn(n: i32) -> i32 { print(n); return n; }`.

| Test first | Catches |
| --- | --- |
| `add(noisy(1), noisy(2))` prints 1 then 2 | argument order; fails today under gcc |
| `noisy(1) + noisy(2) * noisy(3)` prints 1, 2, 3 | operand order |
| `noisy(1) - noisy(2)` gives -1 | temporaries bound to the right operand |
| `f(noisy(1), g(noisy(2), noisy(3)), noisy(4))` | nested calls |
| `false && check(1)` does not print; `true && check(1)` does | short-circuit with a call on the right |
| `true \|\| check(1)` does not print; `false \|\| check(1)` does | same for `\|\|` |
| `a() && b() && c()` where `b` is false: `c` not called | chained short-circuit |
| `while keep_going(i) { }` with a printing condition: called once per iteration | loop condition re-evaluated, not hoisted out |
| `if a() { } else if b() { }`: `b` not called when `a` is true | `else if` statements nested, not hoisted above the chain |
| all of the above under `CC=gcc` and `CC=clang` | compiler-dependent order |

### Stage 7: finish

- Sweep section 5.4: every message has a test. Sweep the lexer and parser for
  `Diag.fatal` calls with no test.
- Confirm the strict-flags and two-compiler checks cover every passing
  program.
- Read the generated C for `fib.slick` and check it is readable.
- Write `README.md`: prerequisites, `dune build`, `dune test`, `slick run`.
- Run `dune build 2>&1` from clean (`dune clean` first) and confirm no
  warnings.

## 11. Working rules

- Do not commit or push unless the programmer asks. If asked to commit, branch
  off `main` first.
- Create and edit files with the Write and Edit tools, not shell redirection
  or `sed`, so every change shows as a diff.
- Stay inside the scope in section 4. If something seems to need a feature
  from a later milestone, stop and ask.
- If the design doc and this plan disagree, the design doc wins; say so. The
  one exception is P3: the design doc says the interesting parts are written
  by hand, but for this milestone the agent writes everything.
- If a default in section 3 turns out to be awkward in practice, finish the
  stage with the default and raise it, rather than changing it silently.

## 12. Final report

When done, report in this order:

1. Whether each "done when" item holds, with the command output for `dune
   test` and `slick run examples/fib.slick`.
2. Anything skipped or left failing.
3. The defaults D1 to D16 from section 3 as a list for the programmer to
   accept or overrule, plus any new language questions that came up.
4. Notes for Milestone 1 discovered along the way. Known already: `if x {`
   becomes ambiguous once struct literals `T{ }` exist; `i8`/`i16`/`u8`
   arithmetic needs a cast after every operation because C promotes to `int`;
   `x += f()` needs a decision on whether `x` is read before `f` runs.
