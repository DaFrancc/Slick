# Slick

Slick is a hobby systems language for game development: a cleaner C with
Odin-style ergonomics and Jai-style compile-time power. The language design is
in [Slick Design Decisions.md](Slick%20Design%20Decisions.md).

This repository holds the bootstrap compiler, written in OCaml. It turns a
`.slick` file into C and hands that to the system C compiler.

```
main.slick → lex → parse → check → emit C → cc → ./main
```

## Status

Milestones 0 and 0.5 are done: `i32` and `bool`, local declarations with
`mut`, assignment and compound assignment, arithmetic, comparison and logical
operators, `if`/`else`, `while`, functions with parameters, `return` and
recursion, a built-in `print(i32)`, and Rust-style error messages.

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

## Prerequisites

- OCaml 5.x and dune 3.16 or newer
- A C11 compiler on `PATH` as `cc` (gcc and clang are both tested)

## Build, test, run

Run these through `opam exec --`, or in a shell where `eval $(opam env)` has
been run.

```
dune build
dune test
dune exec slick -- run examples/fib.slick
```

`dune test` uses `cc`. To rerun every test with clang, use `CC=clang dune
test`. If both gcc and clang are installed, one test also compares their
output directly.

## Usage

```
slick build FILE [-o OUT] [--emit-c] [--color=WHEN]
slick run FILE [--color=WHEN]
```

- `slick build main.slick` writes the executable `./main`, or `OUT` with `-o`.
- `slick build main.slick --emit-c` prints the generated C instead of
  compiling it.
- `slick run main.slick` builds to a temporary file, runs it, and exits with
  its exit code.
- `--color=auto|always|never` controls color in error messages. `auto`, the
  default, colors only when writing to a terminal.

Environment variables:

- `CC`: the C compiler to use (default `cc`).
- `SLICK_CFLAGS`: extra flags for the C compiler. The tests use
  `-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare` to check that
  the generated C is warning-free.
- `NO_COLOR`: when set to anything, turns color off unless `--color` says
  otherwise.

## Errors

Errors show the source, underline the problem, point at related code, and
suggest a fix when one is clear. Every error in a file is reported in one run.

```
Error: Cannot assign to 'count': it was declared without 'mut'
 --> game.slick:3:5
  |
2 |     count := 0;
  |     ----- Declared here without 'mut'
3 |     count += 1;
  |     ^^^^^ Cannot assign
  |
Help: Declare it with 'mut'
  |
2 |     count : mut = 0;
  |           ~~~~~~~

Error: Could not compile 'game.slick' due to 1 error
```

A runtime panic, such as dividing by zero, shows the line it happened on in
the same way.

Exit codes: 0 success, 1 compile error (or a runtime panic under `run`), 2
usage error, 3 if the C compiler rejects the generated code. Exit code 3 is
always a bug in slick, and the C file is kept so it can be inspected.

## Layout

| Path | Contents |
| --- | --- |
| `bin/main.ml` | Command-line parsing |
| `src/driver.ml` | Runs the phases and the C compiler |
| `src/lexer.ml`, `src/token.ml` | Source text to tokens |
| `src/parser.ml`, `src/ast.ml` | Tokens to syntax tree |
| `src/check.ml` | Names, types, mutability, return paths |
| `src/emit_c.ml` | Syntax tree to C |
| `src/diag.ml` | Source spans and the shape of a diagnostic |
| `src/render.ml` | Diagnostics to text: excerpts, labels, color |
| `src/report.ml` | Collects diagnostics and prints them |
| `src/suggest.ml` | "Did you mean" suggestions |
| `test/*.t` | Cram tests: each runs real programs through `slick` |
| `examples/` | Example programs |
| `plans/` | Implementation plans per milestone |
