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

Milestone 0 is done: `i32` and `bool`, local declarations with `mut`,
assignment and compound assignment, arithmetic, comparison and logical
operators, `if`/`else`, `while`, functions with parameters, `return` and
recursion, and a built-in `print(i32)`.

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
slick build FILE [-o OUT] [--emit-c]
slick run FILE
```

- `slick build main.slick` writes the executable `./main`, or `OUT` with `-o`.
- `slick build main.slick --emit-c` prints the generated C instead of
  compiling it.
- `slick run main.slick` builds to a temporary file, runs it, and exits with
  its exit code.

Environment variables:

- `CC`: the C compiler to use (default `cc`).
- `SLICK_CFLAGS`: extra flags for the C compiler. The tests use
  `-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare` to check that
  the generated C is warning-free.

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
| `src/diag.ml` | Locations and error reporting |
| `test/*.t` | Cram tests: each runs real programs through `slick` |
| `examples/` | Example programs |
| `plans/` | Implementation plans per milestone |
