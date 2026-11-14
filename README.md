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

Milestones 0, 0.5, 1 and 2 are done:

- **Types:** `i8` to `i64`, `u8` to `u64`, `f32`, `f64`, `bool` and
  `cstring`. Literals take their type from context, narrower values widen
  implicitly when nothing can be lost, and `cast(T, x)` and `bitcast(T, x)`
  do the rest.
- **Constants:** `MAX :: 1024;` or `SPEED : f32 : 400;`, at the top level.
- **C interop:** `foreign "raylib" { ... }` declares C functions and links
  their library. See `examples/pong.slick`.
- **Structs:** declared at the top level, built with named, positional or
  `.{ }` literals, and passed and returned by value.
- **Pointers:** `*T` and `*mut T`, `&x` and `&mut x`, and `*p`. Field access
  goes through a pointer by itself.
- **Operators:** arithmetic, comparison and logical operators, plus the
  bitwise ones with Go's precedence, so `flags & MASK == 0` means what it
  says. Evaluation is strictly left to right.
- **Statements:** local declarations with `mut`, assignment and compound
  assignment, `if`/`else`, `while`, and functions with parameters, `return`
  and recursion.
- **Output:** a built-in `print` for every number type, `bool` and
  `cstring`. Floats
  print as the shortest text that reads back exactly, and `print(x, 2)` prints
  two digits after the point.
- **Diagnostics:** Rust-style error messages, and an opt-in warning for
  implicit conversions.

```
Vec2 :: struct { x, y: f32 }

step :: fn(pos: *mut Vec2, vel: Vec2, dt: f32) {
    pos.x += vel.x * dt;
    pos.y += vel.y * dt;
}

main :: fn() {
    p : mut = Vec2{ 0, 10 };
    step(&mut p, .{ 2, -1 }, 0.5);
    print(p.x);   // 1.0
    print(p.y);   // 9.5
}
```

See `examples/` for more.

## Prerequisites

- OCaml 5.x and dune 3.16 or newer
- A C11 compiler on `PATH` as `cc` (gcc and clang are both tested)
- For `examples/pong.slick` only: raylib (on Fedora, `sudo dnf install
  raylib-devel`). The tests do not need it.

## Calling C

C functions are declared in a `foreign` block that names their library.
slick reads no C headers, so the declarations must match the C ones: C's
`int` is `i32`, `float` is `f32`, and structs need the same fields in the same
order.

```
Color :: struct { r, g, b, a: u8 }

foreign "raylib" {
    InitWindow      :: fn(width, height: i32, title: cstring);
    ClearBackground :: fn(color: Color);
}

foreign "m" { Sqrt :: fn(x: f64) -> f64 #link_name("sqrt"); }
```

The name before `::` is the Slick name. `#link_name("...")` gives a
different C symbol, and `#link_prefix("SDL_")` on a block puts a prefix in
front of every name in it. Variadic C functions, null pointers and callbacks
are not supported yet.

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
slick build FILE [-o OUT] [--emit-c] [OPTIONS]
slick run FILE [OPTIONS]
```

- `slick build main.slick` writes the executable `./main`, or `OUT` with `-o`.
- `slick build main.slick --emit-c` prints the generated C instead of
  compiling it.
- `slick run main.slick` builds to a temporary file, runs it, and exits with
  its exit code.
- `--color=auto|always|never` controls color in error messages. `auto`, the
  default, colors only when writing to a terminal.
- `--warn-implicit-conversions` warns about every implicit conversion, such
  as an `i32` passed where an `i64` is expected.
- `--warnings-as-errors` turns every warning into an error.

Environment variables:

- `CC`: the C compiler to use (default `cc`).
- `SLICK_CFLAGS`: extra flags for the C compiler. The tests use
  `-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare` to check that
  the generated C is warning-free.
- `SLICK_LDFLAGS`: extra flags for linking, such as `-L<dir>` for a library
  that is not installed system-wide.
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

Exit codes: 0 success, 1 compile error, link error (usually a missing
library) or a runtime panic under `run`, 2 usage error, 3 if the C compiler
rejects the generated code. Exit code 3 is
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
| `src/options.ml` | Command-line settings the phases read |
| `test/*.t` | Cram tests: each runs real programs through `slick` |
| `examples/` | Example programs |
| `plans/` | Implementation plans per milestone |
