# Milestone 2 implementation plan: C interop and Pong

Plan for the executing agent. Read `Slick Design Decisions.md` first; it is
the source of truth, and this plan only fills in what it leaves open. The
earlier plans set the conventions this one keeps:

- `plans/milestone-0.md`: OCaml style (section 7), tests (section 9) and
  working rules (section 11).
- `plans/milestone-0.5.md`: the diagnostic format and message style
  (sections 2 and 6).
- `plans/milestone-1.md`: typing with an expected type (section 3.2), and
  the C invariants (section 5).

Everything that compiles today keeps compiling and keeps its behavior.

## 1. What gets built

1. **Foreign blocks.** `foreign "raylib" { ... }` declares C functions and
   names the library to link. `#link_prefix` and `#link_name` rename them.
2. **Constants.** Every constant has one fixed type. `NAME :: value;`
   infers it the way `:=` does, and `NAME : T : value;` writes it out.
3. **`cstring` and string literals.** `"Pong"` is a `cstring`, a
   null-terminated string for C.
4. **Linking.** slick links every library named by a foreign block. A link
   failure is a user error with a clear message, not an internal compiler
   error.
5. **Pong.** `examples/pong.slick`: two paddles and a ball, drawn with
   raylib. No score yet.

### Done when

1. `dune build` and `dune test` pass with no warnings under `cc` and
   `CC=clang`, and `dune build @fmt` reports nothing.
2. `examples/pong.slick` builds and links against raylib, and plays: both
   paddles move, the ball bounces off walls and paddles, and it resets when
   it leaves the screen.
3. Foreign calls into libc and libm work in the tests, including one that
   returns a struct by value.
4. Every message in section 7 has a test showing its full output.
5. The design doc and `README.md` describe the new features.

### The programmer's part

raylib must be installed to link Pong: on Fedora, `sudo dnf install
raylib-devel`. The tests do not need it; the one test that links Pong runs
only when raylib is found (section 8).

## 2. Decisions

### 2.1 Made by the programmer

- **P1. Foreign functions are declared in blocks only.** There is no
  per-function `#foreign` attribute.
- **P2. Renaming.** The name before `::` is always the Slick name. The C
  symbol is the Slick name, or `#link_prefix` on the block followed by the
  Slick name, or exactly the `#link_name` on the function, which ignores the
  prefix.
- **P3. Declarations inside a block end with `;`**, like other bodiless
  declarations.
- **P4. Every constant has one fixed type**, inferred like a variable's
  (`MAX :: 1024;` is an `i32`) or written (`SPEED : f32 : 400;`). Uses do
  not adapt to their context: `x : f32 = MAX;` needs a cast, as it would
  for an `i32` variable. Constants that adapt at each use were considered
  and rejected: they are an implicit conversion, and they would complicate
  `#run` and generic type inference later.
- **P5. Out of scope:** variadics (C or Slick), null pointers, arrays,
  platform-specific linking, callbacks, and exporting Slick functions to C.
  They go in the design doc's open questions (section 5).
- **P6. Pong shows no score.** Turning a number into text needs variadics
  or arrays.

### 2.2 Defaults chosen here

- **D1. Constants are top-level only.** Local constants can come later.
- **D2. A constant's value must be a constant expression:** literals,
  other constants, unary and binary operators, `cast` and `bitcast`, and
  struct literals, all made of constant expressions. No calls, variables,
  `&` or `*`.
- **D3. A constant is checked once, at its definition.** A written type is
  the expected type for its expression, so `SPEED : f32 : 400;` works and
  `B : u8 : 300;` is the usual range error. Without one, literals take
  their defaults (`i32`, `f32`). Every use has the constant's type and
  widens like any value.
- **D4. String literals are always `cstring` for now.** When `string`
  arrives, a literal will take `string` or `cstring` from context, with
  `string` the default.
- **D5. A `cstring` literal cannot contain a zero byte**, since C would cut
  it off there. `\0` is an error.
- **D6. Escapes:** `\n` `\t` `\r` `\\` `\"` `\'` `\0`, `\xHH`, and
  `\u{H...}` (encoded as UTF-8). Characters outside ASCII may appear
  directly in a string literal. Backtick raw strings come with `string`.
- **D7. `cstring` supports no operators.** No `==` (it would compare
  addresses) and no indexing. `print(s)` prints it.
- **D8. The library name is passed as `-l<name>`.** Each library is linked
  once, in the order first seen. `SLICK_LDFLAGS` adds flags to the link
  step, such as `-L` paths.
- **D9. Foreign functions are declared under a mangled C name** with an
  assembler label naming the real symbol (section 4.4). This keeps them
  clear of anything the runtime's headers declare: binding libc's `abs` or
  `puts` must not clash with `<stdlib.h>` or `<stdio.h>`.
- **D10. Attributes take string literals as arguments** for now:
  `#link_name("SDL_Init")`, not a constant.

## 3. The language in this milestone

### 3.1 Foreign blocks

```
foreign "raylib" {
    InitWindow  :: fn(width, height: i32, title: cstring);
    WindowShouldClose :: fn() -> bool;
}

foreign "SDL3" #link_prefix("SDL_") {
    Init      :: fn(flags: u32) -> bool;                 // links SDL_Init
    GLGetProc :: fn(name: cstring) -> *mut u8
                     #link_name("SDL_GL_GetProcAddress");
}

foreign "m" { Sqrt :: fn(x: f64) -> f64 #link_name("sqrt"); }
```

Grammar:

```
ForeignBlock := 'foreign' StringLit Attribute* '{' ForeignDecl* '}'
ForeignDecl  := Name '::' 'fn' '(' Params? ')' ('->' Type)? Attribute* ';'
Attribute    := '#' Name '(' StringLit ')'
```

- Top level only. The block's `}` takes no `;`.
- Inside a block, only bodiless function declarations. A body, a struct or
  a constant inside a block is an error.
- The block accepts `#link_prefix`; a declaration accepts `#link_name`.
  Anything else is an unknown or misplaced attribute.
- Parameter and return types: numbers, `bool`, pointers, `cstring` and
  structs. Structs pass by value with C's layout, since a Slick struct is a
  plain C struct.
- A foreign function is called like any other. It shares the function
  namespace: no two functions, foreign or not, have the same Slick name.
- `main` cannot be foreign. A parameter of a foreign function can have
  `mut`, but it means nothing and is an error.
- Two declarations of the same C symbol are allowed if they have different
  Slick names; the C compiler checks they agree.

### 3.2 Constants

```
SCREEN_W :: 800;                    // i32, inferred
SCREEN_H : f32 : 450;               // f32, written
HALF_W   :: SCREEN_W / 2;           // i32: 400
SPEED    :: 400.0;                  // f32
DEBUG    :: false;
TITLE    :: "Pong";                 // cstring
RAYWHITE :: Color{ 245, 245, 245, 255 };
ORIGIN   : Vector2 : .{ 0, 0 };
```

- Top level only (D1), in any order, like functions and structs. A
  constant can use constants declared later; a cycle is an error.
- The type is fixed at the definition (D3). With `SCREEN_W :: 800;`,
  `x : i64 = SCREEN_W;` widens as usual, and `y : f32 = SCREEN_W;` is an
  error with the usual "Convert it explicitly" help.
- Without a written type, a struct literal needs its name:
  `RED :: Color{ ... };`. `.{ }` needs a written type: `ORIGIN : Vector2 :
  .{ 0, 0 };`.
- Constants cannot be assigned to, and `&` of a constant is an error: a
  constant is a value, not a place in memory.
- A constant shares the one namespace of functions, structs, built-in names
  and locals.

### 3.3 `cstring` and string literals

- `cstring` is a built-in type: a pointer to null-terminated, read-only
  bytes. It maps to `const char *`.
- A string literal has type `cstring` (D4), with the escapes in D6.
- `print(s)` prints a `cstring` and a newline.
- No other operations (D7).

## 4. Compiler changes

### 4.1 Lexer and tokens

- `foreign` becomes a keyword. Add it to the parser's keyword suggestions.
- `String of string` holds the decoded bytes. An unterminated string, an
  unknown escape, a bad `\x` or `\u{}`, and a newline inside a string are
  each an error with a span on the offending part. Recovery: a string
  without its closing `"` ends at the end of the line.
- `Directive of string` for `#name`. A `#` not followed by a name is an
  unexpected character.
- Non-ASCII bytes are allowed inside string literals; they are still errors
  elsewhere.

### 4.2 AST

- `ty` gains `Cstring`. `ty_name` is `cstring`.
- `expr_kind` gains `String_lit of string`.
- `var_ref` resolves to a local or a constant: add a mutable
  `var_const : const_decl option`.
- `func` gains `f_foreign : foreign_info option`, where `foreign_info =
  { lib : string; symbol : string }`. A foreign function's `body` is an
  empty block.
- `const_decl = { c_name; c_name_span; c_ann : type_ann option; c_value :
  expr; mutable c_ty : ty; mutable c_state : const_state }`, with
  `const_state = Unchecked | Checking | Checked | Broken`.
- `file` gains `consts : const_decl list` and `libraries : string list`.

### 4.3 Checker

**Constants** are checked on demand, so their order does not matter:

- On first use, or in a final pass over all constants, a constant moves
  from `Unchecked` to `Checking`, its expression is checked, and it becomes
  `Checked` or `Broken`. Reaching a `Checking` constant is a cycle.
- The check uses the written type, if any, as the expected type, then
  coerces to it like a declaration does. It also checks that the
  expression is constant (D2). Errors are reported once, at the definition,
  and leave the constant `Broken`.
- A use of a `Checked` constant has type `c_ty`, like a variable. A use of
  a `Broken` one has type `Err`, so nothing is reported twice.
- `place_of` treats a constant as `Not_place`, with its own messages
  (section 7).

**Foreign functions** go in the function table like any other, with their
signature resolved the same way. The missing-return check skips them, as
does the body check.

**Types:** `resolve_type` knows `cstring`. Add `cstring` to the built-in
type names in notes and suggestions.

**print** accepts a `cstring`.

### 4.4 C emission

- **String literals** are C string literals, escaped with the existing
  `c_string_literal`. Their type is `const char *`, which is what `cstring`
  maps to.
- **Foreign functions** are declared once each, before the prototypes:

  ```c
  #define SLICKRT_STR2(x) #x
  #define SLICKRT_STR(x) SLICKRT_STR2(x)
  #define SLICKRT_SYM(name) __asm__(SLICKRT_STR(__USER_LABEL_PREFIX__) name)

  extern void slickf_InitWindow(int32_t, int32_t, const char *) SLICKRT_SYM("InitWindow");
  ```

  Calls use `slickf_InitWindow`. The assembler label makes the linker see
  the real symbol, `InitWindow`, while the C name stays clear of any
  declaration in the included headers (D9). `__USER_LABEL_PREFIX__` is `_`
  on macOS and empty on Linux. gcc and clang both support this; MSVC is not
  a target. Emit the macros only when the program has foreign functions.
- **Constants** produce no C of their own. Each use emits the constant's
  checked expression in place, in parentheses, with the definition's
  conversion if it had one. A constant expression has no side effects,
  except an integer division that can panic, which panics at the use.
- A foreign function's struct parameters and return values use the same C
  struct as the rest of the program. `bool` is C's `bool`, which matches
  C libraries compiled as C99 or later.

### 4.5 Driver

- Compile and link in two steps: `cc -c` to an object file, then
  `cc -o OUT obj -l<lib>... $SLICK_LDFLAGS`.
- A failure in the first step is still an internal compiler error (exit 3,
  C file kept). A failure in the second is a user error, exit 1:

  ```
  Error: Could not link 'pong.slick'
  Note: It links with: -lraylib
  Help: Check that these libraries are installed, or add a search path with SLICK_LDFLAGS="-L<dir>"
  ```

  The linker's own output is shown above it.
- `--emit-c` is unchanged and prints only C.

## 5. Design doc updates

- **Declarations and syntax:** constants have one fixed type, inferred
  like `:=` or written (`SCREEN_H : f32 : 450;`).
- **A new "C interop" section:** foreign blocks, renaming, how types map,
  no headers, linking, and what is not supported yet.
- **Strings:** literals are `cstring` until `string` exists.
- **Open questions:** C variadics (foreign-only `...`, planned first);
  Slick variadics (`..T` over slices, with arrays; `format` with generics,
  either `any` or compile-time specialization); null pointers for C; arrays
  for C; platform-specific linking; callbacks; exporting Slick functions to
  C; a binding generator from C headers; naming convention (the programmer
  prefers PascalCase for functions).
- **Milestone 2** line: the scope above.

## 6. Pong

`examples/pong.slick`, about 100 lines:

- The raylib bindings at the top, in one `foreign "raylib"` block: window,
  frame time, drawing (`ClearBackground`, `DrawRectangleRec`,
  `DrawCircleV`, `DrawText` for a title line), input (`IsKeyDown`),
  `CheckCollisionCircleRec` and `GetRandomValue`.
- Structs matching raylib's: `Color`, `Vector2`, `Rectangle`.
- Constants for keys, colors, screen size and speeds.
- `Paddle` and `Ball` structs, with `MovePaddle`, `ResetBall` and
  `UpdateBall` taking pointers, as in the stress-test example.
- W/S and Up/Down move the paddles. The ball speeds up a little on each hit
  and resets when it leaves the screen.

## 7. Message catalog

| Case | Header | Primary label | More |
| --- | --- | --- | --- |
| Body in a foreign block | `A foreign function cannot have a body` | On the `{` | Note: `Its code is in the library 'raylib'` |
| Other item in a foreign block | `Only function declarations can go in a foreign block` | On the item | |
| Foreign function outside a block | `Expected '{' to start the function body` (existing parse error) | | Note: `To declare a C function, put it in a 'foreign' block` when the declaration ends with ';' |
| Unknown attribute | `Unknown attribute '#link_nme'` | On it | Did you mean, among the attributes valid there |
| Misplaced attribute | `'#link_prefix' goes on a foreign block, not a function` | On it | |
| Attribute argument | `'#link_name' expects a string, like #link_name("SDL_Init")` | On the argument | |
| `mut` on a foreign parameter | `Parameters of a foreign function cannot be 'mut'` | On `mut` | Deletion help |
| Foreign `main` | `'main' cannot be a foreign function` | On the name | |
| Unsupported type | `Type '...' cannot cross into C` | On the type | Only if any appear; all M2 types can |
| Constant cycle | `Constant 'A' depends on itself` | On the first use in the cycle | Secondary labels along the path |
| Not a constant expression | `A constant's value must be known at compile time` | On the offending part: `This is a function call` / `This is a variable` | |
| Assign to a constant | `Cannot assign to constant 'MAX'` | On the target | Secondary at the definition |
| `&` of a constant | `Cannot take the address of constant 'MAX'` | On it | Help: `Store it in a variable first` |
| Local constant | `Constants can only be declared at the top level for now` | On `::` | |
| Unterminated string | `Unterminated string literal` | From `"` to the end of the line | Help: insert `"` |
| Unknown escape | `Unknown escape '\q'` | On it | Note: the list of escapes |
| Zero byte in a cstring | `A cstring cannot contain a zero byte` | On the `\0` | Note: `C would treat it as the end of the string` |
| Link failure | `Could not link 'pong.slick'` | | See section 4.5 |
| `==` on cstrings | `Cannot compare cstrings with '=='` | On the operator | Note: `It would compare their addresses, not their text` |

## 8. Tests

- `foreign.t`:
  - libc and libm through foreign blocks: `Sqrt` from `sqrt`, `Abs` from
    `abs`, `Puts` from `puts`. `abs` and `puts` are declared in the
    runtime's headers, which checks D9;
  - `div` returning glibc's `div_t { quot, rem: i32 }` by value;
  - `#link_prefix` and `#link_name`;
  - each foreign-block error in section 7;
  - a link failure against a library that does not exist.
- `constants.t`: inferred and written types; widening at uses, and the
  cast a narrowing or int-to-float use needs; constants using later
  constants; struct and `cstring` constants; each constant error in
  section 7.
- `strings.t`: escapes, UTF-8, `print` of a `cstring`, and each string
  error.
- Pong: `--emit-c` must compile as an object file without raylib (`cc -c`),
  since no headers are used. A second test links it only if `pkg-config
  --exists raylib` succeeds, and prints the same line either way, so the
  test passes on machines without raylib.

The test that links Pong cannot open a window. Playing it is the
programmer's check.

## 9. Stages

Work on a branch, `milestone-2`. After each stage, `dune build`, `dune
test`, `CC=clang dune test` and `dune build @fmt` must pass. Do not commit
until the programmer asks.

1. **Strings:** lexer, `cstring`, literals, `print`, escapes and errors.
2. **Constants:** parsing both forms, on-demand checking, copies at uses,
   cycles, and the constant errors.
3. **Attributes:** `#name("...")` parsing, shared by both attributes.
4. **Foreign blocks:** parsing, the checker, emission with assembler labels,
   and libc tests.
5. **Linking:** two-step compile, library flags, `SLICK_LDFLAGS`, and the
   link error.
6. **Pong**, the README and the design doc.

## 10. Pitfalls

- **Emitting a shared expression.** A constant's expression is emitted at
  every use, so emitting must not change it. Conversions at a use go on the
  use's own node, never on the shared expression.
- **ABI mismatches are silent.** A wrong foreign declaration compiles and
  links, then misbehaves. Bindings should use sized types matching the C
  ones: raylib's `int` is `i32`, and `float` is `f32`.
- **Struct field order** must match C exactly, or values arrive in the
  wrong fields.
- **The assembler label prefix.** Test on Linux; the macOS prefix is
  covered by `__USER_LABEL_PREFIX__` but not tested here.
