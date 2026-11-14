# Milestone 1 implementation plan: structs, pointers and the numeric types

Plan for the executing agent. Read `Slick Design Decisions.md` first; it is
the source of truth, and this plan only fills in what it leaves open. Then
read the earlier plans for the conventions this one keeps:

- `plans/milestone-0.md`: OCaml style (section 7), tests (section 9) and
  working rules (section 11).
- `plans/milestone-0.5.md`: the diagnostic format and message style
  (sections 2 and 6). Every new error in this milestone follows them.

Everything that compiles today keeps compiling and keeps its behavior. The
generated C may change shape.

## 1. What gets built

1. **Numeric types:** `i8` `i16` `i32` `i64` `u8` `u16` `u32` `u64` `f32`
   `f64`, with typed literals, lossless implicit widening, `cast` and
   `bitcast`.
2. **Bitwise operators:** `&` `|` `^` `<<` `>>` and prefix `~`, with Go-style
   precedence, plus their compound assignments.
3. **Literals:** float literals, and hexadecimal and binary integers.
4. **Pointers:** `*T` and `*mut T`, `&x`, `&mut x`, `*p`, assignment through
   `*mut` pointers.
5. **Structs:** declarations, literals (named, positional and `.{ }`), field
   access with auto-dereference, assignment to fields, passing and returning
   by value.
6. **Warnings:** the first one, `--warn-implicit-conversions`, and
   `--warnings-as-errors`.
7. **`print`** for every number type and `bool`, with an optional precision
   for floats.

### Done when

1. `dune build` and `dune test` pass with no warnings under `cc` and
   `CC=clang`, and `dune build @fmt` reports nothing.
2. `examples/particles.slick` (section 9.2) builds, runs and prints the
   expected output, and has a test.
3. Every rule in section 3 has a test showing it works, and every message in
   section 8 has a test showing its full output.
4. The generated C compiles cleanly under the test flags
   (`-Wall -Wextra -Werror` and the rest) for every test program.
5. `README.md` and the design doc describe the new features.

## 2. Decisions

### 2.1 Made by the programmer

- **P1. Bitwise operators are in, with Go-style precedence.** `<<` `>>` `&`
  bind like `*`, while `|` `^` bind like `+`. All bind tighter than
  comparisons, so `flags & MASK == 0` means `(flags & MASK) == 0`.
- **P2. Mixed integer types widen when lossless.** `i32 + i64` is `i64`.
  When neither side converts to the other losslessly (`u32 + i32`), it is an
  error that suggests a `cast`.
- **P3. Integers never convert to floats implicitly.** Only integer to
  integer and float to float widen. Integer literals still adopt float types
  (`health : f32 = 100;`).
- **P4. `print` shows floats as the shortest text that reads back
  exactly**, with `.0` on whole numbers. `print(x, n)` prints `n` digits
  after the point instead.
- **P5. `--warn-implicit-conversions`** warns on every implicit numeric
  conversion. **`--warnings-as-errors`** turns every warning into an error.

### 2.2 Defaults chosen here

The programmer can override any of these; each is cheap to change.

- **D1. Flags use two dashes**, like `--emit-c`. The design doc's
  `-warn-implicit-conversions` becomes `--warn-implicit-conversions`.
- **D2. `%` is integers only.** Float remainder needs `fmod` and `-lm`; it
  can come later.
- **D3. Shift amounts wrap:** `x << n` shifts by `n` modulo the width of
  `x`, like Rust's release builds and Java. This matches "overflow wraps for
  now". A literal shift amount that is too large is a compile error.
- **D4. Float to integer `cast` saturates**, as in Rust: values beyond the
  target's range give its minimum or maximum, and NaN gives 0. C leaves this
  undefined, so it goes through a helper.
- **D5. Struct literals are not allowed directly in `if` and `while`
  conditions**; parentheses allow them. Otherwise `if x == Foo { ... }` is
  ambiguous. Rust and Go have the same rule.
- **D6. Field access auto-dereferences one level.** `p.x` works for
  `p: *Vec3`; for `pp: **Vec3`, write `(*pp).x`.
- **D7. Pointers compare with `==` and `!=` only.** No `<`, no arithmetic,
  no conversion to or from integers (`ptr_add` comes later).
- **D8. Structs cannot be compared with `==`.** That waits for operator
  overloading.
- **D9. Unary `-` on an unsigned type is an error.** A note suggests
  `0 - x` for wrapping negation.
- **D10. An empty struct is allowed.** C forbids empty structs, so the C
  side gets one unused `char` field.
- **D11. No constant folding.** `x : u8 = 200 + 100;` wraps to 44 at run
  time. Each literal is range-checked on its own.
- **D12. A literal adopting a float type is not checked for exactness.**
  `x : f32 = 16777217;` rounds silently.
- **D13. The precision in `print(x, n)` is any integer expression.** A
  negative value panics at run time with a source excerpt, like division by
  zero.
- **D14. `*mut T` converts implicitly to `*T`**, at the top level only. It
  is not a numeric conversion, so it never warns.
- **D15. `inf`, `-inf` and `nan` print as written here.** Floats whose
  decimal exponent is below -4 or at least 16 print in exponent form, as
  Python does (`1e+20`, `1e-05`). Everything else is written out in full.

## 3. The language in this milestone

### 3.1 Types

```
Type := '*' 'mut'? Type
      | Name                      // i8 ... u64, f32, f64, bool, or a struct
```

- A leading `mut` in a declaration or parameter still makes the variable
  mutable: `q : mut *Enemy`. The `mut` after `*` belongs to the pointer:
  `p : *mut Enemy`.
- `void` is not a type that can be written. `*void` is an error.
- The type names are not reserved words. A local or struct named `i32` is
  an error, because type names are taken (see 3.6).

### 3.2 Literals

- **Integers:** decimal, `0x` hexadecimal and `0b` binary, each with `_`
  separators: `1_000`, `0xFF_00`, `0b1010`. Values up to 2^64 - 1.
- **Floats:** `digits '.' digits exponent?` or `digits exponent`, where an
  exponent is `e` or `E`, an optional sign, and digits: `4.5`, `1e9`,
  `2.5e-3`, `1_000.5`. `1.` and `.5` are not floats. `1.x` is `1`, then
  `.x`.
- An integer literal takes its type from context if there is one, otherwise
  `i32`. Context is an annotated declaration, an assignment target, a
  parameter, a return type, a struct field, a `cast` target, or the other
  operand of a binary operator.
- A float literal works the same way, with `f32` as the default. It can
  only take float types.
- An integer literal can take a float type. A float literal cannot take an
  integer type.
- Each literal is checked against the range of its type. Negative literals
  are the `-` folded in by the parser, as today.

**Which expressions count as literals.** Typing is bidirectional:
`check_expr` takes the expected type, if any. A **literal-like** expression
is a literal, or `-` or `~` applied to one, or an arithmetic or bitwise
operator whose operands are both literal-like. For a shift, only the left
operand counts.

For a binary operator with one literal-like side, check the other side
first, then check the literal-like side expecting that type. When both
sides are literal-like, pass the outer expectation down to both. For a
comparison there is no outer expectation, so the default applies. Errors
are sorted by position, so checking out of order does not show.

### 3.3 Conversions

Implicit conversions are lossless widenings:

| From | To |
| --- | --- |
| `iN` | `iM`, M > N |
| `uN` | `uM` and `iM`, M > N |
| `f32` | `f64` |
| `*mut T` | `*T` (D14) |

They apply at the **coercion sites**: initializing an annotated
declaration, assignment, call arguments, `return`, struct literal fields,
and the operands of a binary operator (P2). For a binary operator, the
narrower operand widens to the other's type. Shift amounts are the
exception: the two sides of a shift never unify, and the result has the
left side's type.

With `--warn-implicit-conversions`, every numeric widening at a coercion
site warns (section 8.4). A literal adopting a type is not a conversion and
never warns.

Explicit casts are builtins:

- `cast(T, e)` converts between any two numeric types. Integer to integer
  wraps, float to integer saturates (D4), integer to float rounds, and float
  to float rounds. `bool` and pointers cannot be cast.
- `bitcast(T, e)` reinterprets the bits between numeric types of the same
  size: `i32`, `u32` and `f32`; `i64`, `u64` and `f64`; `i8` and `u8`;
  `i16` and `u16`.

`cast` and `bitcast` are not keywords. The parser handles an identifier
`cast` or `bitcast` followed by `(` specially, because the first argument is
a type. A local or function named `cast` or `bitcast` is an error, like
`print`.

### 3.4 Operators

Precedence, highest first. Everything is left-associative except prefix
operators. Comparisons still do not chain.

| Level | Operators |
| --- | --- |
| Postfix | `f(...)`, `.field` |
| Prefix | `-` `!` `~` `*` `&` `&mut` |
| Multiplicative | `*` `/` `%` `<<` `>>` `&` |
| Additive | `+` `-` `\|` `^` |
| Comparison | `==` `!=` `<` `<=` `>` `>=` |
| Logical and | `&&` |
| Logical or | `\|\|` |

Operand types:

- `+ - * /` take integers or floats. `%` takes integers (D2). Mixed types
  widen (P2).
- `& | ^` take integers and widen like arithmetic. On `bool` they are an
  error that suggests `&&` or `||`.
- `<< >>` take an integer on each side, of any types. The result has the
  left side's type. The amount wraps modulo the width (D3), and `>>` on a
  signed type is arithmetic.
- `~` takes an integer. `!` still takes only `bool`. Unary `-` takes signed
  integers and floats (D9).
- `==` and `!=` take two numbers (widening), two `bool`s, or two pointers to
  the same type (D7). `< <= > >=` take numbers only.
- `&&`, `||` and `!` are unchanged.

Compound assignment adds `&=`, `|=`, `^=`, `<<=` and `>>=`. `a op= b` has
the type rules of `a = a op b`, except that the result is not widened: it
must convert to `a`'s type.

Overflow wraps for every integer type, and integer division by zero panics
for every integer type, as today. Float division by zero gives an infinity
or NaN, with no panic.

### 3.5 Pointers

- `&e` gives `*T`, and `&mut e` gives `*mut T`. `e` must be a **place**: a
  local or parameter, a field of a place, `*p`, or a field reached through a
  pointer. `&f()` is an error.
- `&mut e` needs a mutable place. A local or parameter is mutable when
  declared `mut`. A field is mutable when its struct is. `*p` and `p.f` are
  mutable when `p` is a `*mut`.
- `*e` dereferences a pointer and is a place.
- Assignment, including compound assignment, needs a mutable place.
- Pointers are never null, so a variable or field whose type contains a
  pointer must be initialized explicitly (3.6).
- There is no escape analysis. Returning `&local` is allowed and dangles, as
  the design doc accepts.

### 3.6 Structs

```
Name :: struct { x, y: f32, owner: *Player }
```

- Top level only, like functions, and in any order: a struct or function
  can use a struct declared later in the file.
- Field groups work like parameter groups (`x, y: f32`), separated by `,`,
  with an optional trailing comma. A leading `mut` on a field is an error
  (the design doc says fields take their mutability from their struct).
- The closing `}` ends the declaration, with no `;`. A stray `;` gets the
  existing stray-semicolon error.
- A struct cannot contain itself by value, directly or through other
  structs. Through a pointer is fine.
- Names share one namespace: built-in type names, structs, functions,
  `print`, `cast`, `bitcast` and locals. With no shadowing, any clash is an
  error.

**Literals:**

```
p := Vec3{ x = 1, y = 2, z = 3 };   // named, any order
q := Vec3{ 1, 2, 3 };               // positional: every field, in order
r : Vec3 = .{ x = 1 };              // type from context; y and z are zero
spawn(.{ 1, 2, 0 });
```

- Named fields can come in any order. An omitted field is zero.
- Positional values must give every field. Named and positional values
  cannot be mixed.
- A field cannot be given twice.
- `.{ }` needs a struct type from context (3.2's list of contexts);
  otherwise it is an error.
- A literal must give every field whose type contains a pointer, directly
  or through by-value struct fields.
- Fields are evaluated in source order, not declaration order.

**Fields and values:**

- `e.f` reads a field of a struct value or of a pointer to a struct (D6).
  `e.f` is a place when `e` is a place or a pointer.
- Structs are assigned, passed and returned by value.
- A declaration without an initializer zeroes the struct. That is an error
  if the type contains a pointer.
- `==` on structs is an error (D8). `print` of a struct is an error.

### 3.7 print

- `print(x)` takes any integer, float or `bool`. Integers print in decimal,
  and `bool` prints `true` or `false`.
- Floats print the shortest decimal that reads back as the same value (P4).
  A whole number gets `.0`. Exponent form is for exponents below -4 or from
  16 on, and `inf`, `-inf` and `nan` print as such (D15).
- `print(x, n)` needs `x` to be a float and `n` an integer. It prints `n`
  digits after the point (`%.*f`). A negative `n` panics (D13).

## 4. Compiler changes by module

### 4.1 `token.ml` and `lexer.ml`

New token kinds:

- Punctuation and operators: `Dot`, `Amp`, `Pipe`, `Caret`, `Tilde`, `Shl`,
  `Shr`, `AmpAssign`, `PipeAssign`, `CaretAssign`, `ShlAssign`, `ShrAssign`.
- Keyword: `Struct`.
- Literals: `Int of Int64.t` and `Float of string`.

The lexer changes:

- Match three-character operators (`<<=`, `>>=`) before two-character ones.
- `Int` holds the literal's magnitude as an **unsigned** `Int64.t`. The
  lexer only rejects values above 2^64 - 1 ("does not fit in any integer
  type"). Range checks per type move to the checker. Accumulate the value by
  hand with an overflow check, as `lex_int` does now. Use
  `Int64.unsigned_compare` and `Int64.unsigned_div`.
- `Float` holds the source text with `_` removed. Check the syntax in the
  lexer; reject `1e` and `1e+`.
- Lex `0x` and `0b` prefixes. Invalid digits get the existing invalid-literal
  error, with the note naming the allowed digits.
- Remove the single `&` and `|` helps and the `.`-after-digit note. Those
  are tokens now. The `&` and `|` advice moves to the checker (section 8).

### 4.2 `ast.ml`

The core change is the type:

```ocaml
type int_kind = I8 | I16 | I32 | I64 | U8 | U16 | U32 | U64
type float_kind = F32 | F64

type ty =
  | Int_ty of int_kind
  | Float_ty of float_kind
  | Bool
  | Void
  | Ptr of bool * ty   (* mutable pointee? *)
  | Struct of string   (* by name; look the definition up in a table *)
  | Err
```

`Struct of string` refers to a struct by name, never by record. A record
that contains its own fields would make polymorphic `=` loop forever on
`Node :: struct { next: *Node }`. With names, `=` and `<>` on `ty` stay
safe, and `mismatch` keeps working. Keep it that way: no record or function
values inside `ty`.

Other changes:

- `type_ann` becomes a type expression:
  `{ t_kind : Named of string | Pointer of bool * type_ann; t_span }`.
  `t_span` covers the whole written type, for edits like `*i32` to
  `*mut i32`.
- Expression kinds:
  - `Int of int_lit`, where `int_lit = { value : Int64.t; neg : bool }`,
    replaces `Int of int`.
  - `Float of float_lit`, where `float_lit = { text : string; fneg : bool }`.
  - `Field of field_access`: the object, the field name and span, and a
    mutable `auto_deref : bool` the checker fills in.
  - `Deref of expr` and `Addr_of of bool * expr` (the bool is `&mut`).
  - `Cast of cast_kind * type_ann * expr`, with `cast_kind = Convert | Bits`.
  - `Struct_lit of struct_lit`: an optional type name and its span, the
    items, and a mutable resolved struct name. Each item is `{ name; span;
    value }`, where `name` is `None` for a positional value.
- `binop` gains `Band | Bor | Bxor | Shl | Shr`, and `unop` gains `Bnot`.
- `assign.a_target` can be any expression; the checker checks it is a place.
- Top level: `type item = Func of func | Struct_decl of struct_decl`, and
  `file = { path; items }`. A `struct_decl` has the name and its span, the
  fields (name, span, type annotation, mutable resolved type), and the span
  of its closing `}`.
- Implicit conversions must be visible to the emitter. Add a mutable
  `conv : ty option` to `expr`: the type the checker converted the
  expression to at a coercion site. The emitter wraps the expression in a C
  cast to that type. This also gives the warning one place to come from.

`ty_name` prints the types as written: `i64`, `*mut Vec3`, `Vec3`.

### 4.3 `parser.ml`

- `parse_type` parses section 3.1's grammar. Call sites that check
  `Token.Ident _` to decide whether a type follows (`parse_decl`) also accept
  `Token.Star`.
- The expression grammar follows section 3.4. Add `&` and `<<` `>>` to the
  multiplicative level and `|` `^` to the additive level. Add `~`, `*`, `&`
  and `&mut` to `parse_unary`. Add a postfix loop after `parse_primary` for
  `.field`. Calls stay identifier-only.
- `-` folding into literals now covers floats too.
- `parse_primary` handles `cast(Type, expr)` and `bitcast(Type, expr)`,
  `Name{ ... }`, and `.{ ... }`.
- A `no_struct_lit` field on the parser, set while parsing an `if` or
  `while` condition and cleared inside parentheses, turns off `Name{`
  literals (D5).
- The assignment target is any expression. The parser's "Cannot assign to
  this expression" error moves to the checker, which knows what a place is.
- Top level: `Name :: fn ...` or `Name :: struct { ... }`. Field groups reuse
  the parameter-group parser, with a flag that rejects a leading `mut`.
  `fail_top_level`'s note becomes "Only functions and structs can be defined
  at the top level for now".
- Recovery: a bad field skips to the next `,` or `}`. A bad struct literal
  item skips to the next `,` or `}` at its brace depth.

### 4.4 `check.ml`

Passes over the file:

1. **Collect struct names.** Duplicates and clashes with built-in type names
   are reported here.
2. **Resolve field types.** Unknown types get suggestions from built-in and
   struct names.
3. **Find by-value cycles** with a depth-first search over struct fields.
   Report each cycle once, at the first struct in it.
4. **Declare functions**, as today, with the new namespace rules (3.6).
5. **Check bodies.**

Expression checking changes:

- `check_expr c e expected` with `expected : ty option` (3.2).
- `coerce c e target`, called at every coercion site, does the following:
  - accepts equal types;
  - for a lossless widening, sets `e.conv` and, with the flag, warns;
  - otherwise reports a mismatch, with a note on why the conversion is not
    implicit and a `cast` help (section 8.2).
- Places: `place_info e` returns whether `e` is a place and, if it is not
  mutable, why. That reason drives the error text for assignment and
  `&mut`.
- `print` is no longer a regular signature. Check it specially: one or two
  arguments (3.7).
- `Err` keeps absorbing follow-on errors in every new rule.

The checker needs the struct table (name to `struct_decl`) and the warning
flag. Keep the flags in a small new module, `options.ml`, holding a mutable
record (`warn_implicit`, `warnings_as_errors`). `bin/main.ml` sets it, and
`check.ml` and `report.ml` read it. That avoids a cycle with `driver.ml`.

### 4.5 `report.ml` and `render.ml`

- Count warnings separately from errors.
- With `--warnings-as-errors`, `report` turns a `Warning` into an `Error`
  and adds the note "Reported as an error because of --warnings-as-errors".
  It then counts as an error and stops compilation as usual.
- Warnings are printed even when compilation succeeds. `print_all` runs
  after checking whether or not there are errors.
- Summary lines:
  - errors: `Error: Could not compile 'game.slick' due to 2 errors`;
  - errors and warnings: the same, followed by `; 1 warning emitted`;
  - warnings only: `Warning: 'game.slick' generated 1 warning`.
- The renderer already colors `Warning` yellow. Check that the underline
  carets and the location arrow use the warning color too, and test it.

### 4.6 `emit_c.ml`

See section 5.

### 4.7 `driver.ml` and `bin/main.ml`

- Parse `--warn-implicit-conversions` and `--warnings-as-errors` for both
  `build` and `run`, and set `Options`.
- Usage text:

  ```
  Usage: slick build FILE [-o OUT] [--emit-c] [OPTIONS]
         slick run FILE [OPTIONS]
  Options: --color=WHEN  --warn-implicit-conversions  --warnings-as-errors
  ```
- `compile_to_c` prints the diagnostics after checking when there are only
  warnings, then goes on.

## 5. C emission

### 5.1 Types and names

| Slick | C |
| --- | --- |
| `i8` ... `i64` | `int8_t` ... `int64_t` |
| `u8` ... `u64` | `uint8_t` ... `uint64_t` |
| `f32`, `f64` | `float`, `double` |
| `*T` | `<T> const *` (east const, so nesting composes) |
| `*mut T` | `<T> *` |
| `Vec3` | `slickT_Vec3` |

- Field `x` becomes `f_x`. The prefix keeps fields clear of C keywords and
  of macros such as `bool` and `errno`.
- `slickT_` cannot clash with `slick_<function>`. A local starting with
  `slick` already gets a `u_` prefix.
- Output order:
  1. the prelude;
  2. `typedef struct slickT_X slickT_X;` for every struct;
  3. struct definitions, ordered so that every by-value field's struct comes
     first (a topological sort, which pass 3 proved acyclic);
  4. panic sites, prototypes, then functions.

### 5.2 The invariant

**Every emitted C expression has exactly the C type of its Slick type.**
C's integer promotions break this, so:

- Arithmetic, bitwise and unary results on types narrower than `int` (`i8`
  `i16` `u8` `u16`) are cast back: `(uint8_t)(a + b)`. Without the cast, `a
  + b > c` on `u8` values compares the unwrapped sum.
- Implicit conversions (`e.conv`) emit an explicit cast: `(int64_t)a`. This
  also keeps `-Wsign-compare` quiet.
- Integer literals carry their type: `INT64_C(5)`, `UINT64_C(5)`, `5u`.
  Literals of narrow types are plain `5`, since their uses are cast. The
  minimums are written as `INT32_MIN` and `INT64_MIN`. The narrow minimums
  fit in `int`.
- Float literals use their source text, which avoids rounding twice: `4.5f`
  for `f32`, `4.5` for `f64`. An integer literal of a float type adds `.0`.
  A literal with an exponent stays as written.

### 5.3 Operations

- **Division and remainder:** one pair of helpers per integer type, emitted
  only for the types used. Generate the C text from an OCaml template. The
  signed versions keep the `-1` special case, and the unsigned versions
  only check for zero. Float division is plain `/`.
- **Shifts:** mask the amount with `& (width - 1)`. Shift signed values left
  in the unsigned type of the same width, then cast back, because left
  shifts of negative values are undefined in C. Right shifts stay in the
  signed type: gcc and clang shift arithmetically.
- **`cast`:**
  - integer to integer, and integer to float, are a C cast;
  - float to integer goes through `slickrt_f2i_<kind>(double)`, which
    saturates. Compare against the limits as doubles, carefully: `(double)
    INT64_MAX` rounds up to 2^63, so test with `>=`;
  - float to float is a C cast.
- **`bitcast`:** a union compound literal, which is valid C11:
  `((union { float a; uint32_t b; }){ .a = x }).b`.
- **Struct literals:** a compound literal with designated initializers,
  `(slickT_Vec3){ .f_x = ..., .f_y = ... }`. Every field is written out, in
  declaration order, with omitted ones set to their zero value, so no C
  compiler can warn about missing initializers.
- **Zero values:** a scalar is `0`, `0.0f`, `0.0` or `false`. A struct is a
  compound literal with every field set to its zero value, built the same
  way.
- **Deref, address-of and field access** are `(*p)`, `&x` and `x.f_y` or
  `p->f_y`.
- **print:** one helper per type, `slickrt_print_<type>`. Floats use the
  shortest round-trip loop: `%.*e` with 1 to 9 significant digits for `f32`
  or 1 to 17 for `f64`, stopping at the first that `strtof` or `strtod` reads
  back equal. With a moderate exponent (D15), the value is then written with
  `%.*f` at the same number of significant digits, plus `.0` if it has no
  point. `print(x, n)` uses `%.*f` after a negative check that panics
  through a rendered site. A literal precision needs no site, since the
  checker rejects a negative one.

### 5.4 Evaluation order

The existing rules carry over. New cases:

- **`has_effect`:** integer `/` and `%`, calls, and `print` with a precision
  (it can panic). Float division, shifts, casts, field access, dereference
  and address-of have no effect of their own; they pass through their
  operands. A struct literal has an effect if any field does.
- **Stability:** a dereference or a field read is not stable, like a local.
  It is saved in a temporary before a later operand with an effect, because
  a call can now change memory through a pointer. `&local` and `&field of a
  local` are stable.
- **Struct literal fields** are evaluated in source order, using the same
  machinery as call arguments, before the compound literal is built. C does
  not order initializer expressions.
- **Assignment** evaluates the target's place first:
  - A **fixed** place is a local, or a field of a fixed place. Its address
    cannot change, so it needs nothing.
  - Any other place (through a pointer or a dereference) has its address
    saved first when the value has an effect: `T *tmp = &place;`, then the
    value, then `*tmp = value;`.
- **Compound assignment** follows Java: compute the place, read the old
  value, evaluate the right side, then store. So `x += f(&mut x)` uses `x`'s
  value from before the call. Save the old value in a temporary when the
  right side has an effect.

## 6. Design doc updates

Already done along with this plan:

- P1 to P5;
- D1 to D6;
- the precedence table;
- the literal grammar;
- the expanded Milestone 1 line;
- the Open questions entries.

If a default changes during the work, update the doc to match. Stage 9
checks that the doc and the compiler agree.

## 7. Out of scope

- Arrays, slices and strings.
- `?T` and null.
- `---`.
- Value constants (`MAX :: 1024;`) and globals.
- UFCS and operator overloading.
- Function pointers.
- Enums and `match`.
- `for`, `loop`, `break` and `continue`.
- `ptr_add`, and casts between pointers and integers.
- Constant folding and compile-time overflow detection (D11).
- Debug and release builds.
- Warnings other than implicit conversions, such as unused variables or
  returning `&local`.

If a test or the example program wants one of these, change the test.

## 8. Message catalog

Each new error follows Milestone 0.5's format and sentence case, labels the
offending code, points at the related declaration when there is one, and
offers a help with an edit when the fix is clear. The tables give the
header, the primary label, and the rest. The executing agent words the
cases not listed here in the same style, and every message gets a test.

### 8.1 Literals and types

| Case | Header | Primary label | More |
| --- | --- | --- | --- |
| Literal out of range | `Integer literal 300 does not fit in u8` | `Too large for u8` | Note: `A u8 holds values from 0 to 255` |
| Negative to unsigned | `Integer literal -1 does not fit in u32` | `u32 cannot be negative` | Same note |
| Too large for the default `i32` | `Integer literal 3000000000 does not fit in i32` | `Too large for i32` | In a declaration without a type, help: `Give it a larger type` with the edit `x : i64 = ...` |
| Above 2^64 - 1 (lexer) | `Integer literal ... is too large` | `Larger than any integer type` | Note: `The largest is u64, up to 18446744073709551615` |
| Float literal as integer | The site's mismatch header, like `Cannot initialize 'x' of type u8 with a value of type f32` | `This is f32` | Note: `Integers and floats do not convert implicitly`. Help: `Convert it explicitly` with the edit `cast(u8, 4.5)` |
| Float literal out of range | `Float literal 1e40 does not fit in f32` | `Too large for f32` | Help: `Use f64` when there is an annotation to edit |
| Unknown type | (existing) | (existing) | Suggestions now include struct names. The fallback note lists the built-in types |

### 8.2 Conversions and operators

| Case | Header | Primary label | More |
| --- | --- | --- | --- |
| Narrowing at a coercion site | (existing mismatch header) | (existing) | Note: `Converting i32 to i16 could lose information`, or `could change the sign`, or `could lose precision`, or `Integers and floats do not convert implicitly`. Help: `Convert it explicitly` with the edit wrapping the value in `cast(i16, ...)` |
| No common type | `Mismatched types in '+': i32 and u32` | On the right operand: `This is u32` | Secondary on the left: `This is i32`. Help: `Convert one side explicitly` with an edit casting the right side to the left's type |
| `%` on floats | `Operator '%' does not work on floats` | `This is f32` | Note: `Float remainder is not supported yet` |
| `&` or `\|` on bools | `Operator '&' does not work on bool` | On the operator | Help: `For a logical and, use '&&'` with the edit |
| Literal shift too large | `Shift amount 40 is too large for i32` | `Too large` | Note: `An i32 can be shifted by 0 to 31` |
| Negating unsigned | `Cannot negate a value of type u32` | `This is u32` | Note: `u32 has no negative values; '0 - x' wraps around` |
| Struct `==` | `Cannot compare structs with '=='` | On the operator | Note: `Compare their fields one by one` |
| Bad `cast` | `Cannot cast from Vec3 to i32` | `This is Vec3` | Note: `cast converts between number types` |
| `bitcast` size | `Cannot bitcast from f64 to i32: they differ in size` | `This is 8 bytes` | Note: `i32 is 4 bytes`. Help: `To convert the value, use cast` with the edit |

### 8.3 Pointers, places and structs

| Case | Header | Primary label | More |
| --- | --- | --- | --- |
| Not a place | `Cannot assign to this expression` / `Cannot take the address of a temporary value` | `Not a place in memory` | Help for `&`: `Store it in a variable first` |
| `&mut` of an immutable local | `Cannot take a mutable pointer to 'count': it was declared without 'mut'` | `Needs 'mut'` | Secondary at the declaration, and the existing `Declare it with 'mut'` help |
| Field of an immutable local | `Cannot assign to 'v.x': 'v' was declared without 'mut'` | `Cannot assign` | As above |
| Through a read-only pointer | `Cannot assign through 'p': it points to a read-only Vec3` | `Cannot assign` | Secondary at the pointer's written type: `Declared as *Vec3 here`. Help: `Make it a mutable pointer` with the edit `*mut Vec3`. If the type was inferred from `&v`, the help changes `&v` to `&mut v` instead |
| Deref of a non-pointer | `Cannot dereference a value of type i32` | `This is i32` | |
| Unknown field | `Struct 'Vec3' has no field 'w'` | `Unknown field` | Did you mean, or a note listing the fields |
| Field of a non-struct | `A value of type i32 has no fields` | `This is i32` | |
| Field through `**T` | `Cannot access a field through two pointers` | `This is **Vec3` | Help: `Dereference it first` with the edit `(*pp).x` |
| Duplicate field | `Field 'x' is declared twice` | `Declared again here` | Secondary: `First declared here` |
| By-value cycle | `Struct 'Node' contains itself` | On the field: `Contains 'Node' by value` | For indirect cycles, secondary labels along the path. Note: `A struct cannot contain itself, directly or through other structs' fields` |
| `mut` on a field | `Fields cannot be declared 'mut'` | On `mut` | Note: `A field is mutable when its struct is`. Help: deletion edit |
| Missing pointer field | `Field 'owner' must be given a value` | On the literal's type name, or `.{`: `Missing 'owner'` | Note: `'owner' is a pointer, and pointers cannot be zero` |
| Uninitialized pointer variable | `'t' must be given an initial value` | On the name | Note: `Its type Turret contains the pointer field 'owner', and pointers cannot be zero` |
| Positional count | `Expected 3 values for 'Vec3', found 2` | On the literal | Note: `Positional values must give every field; name them to leave some out` |
| Mixed named and positional | `Struct literal mixes named and positional values` | On the first positional value | |
| Field given twice | `Field 'x' is given twice` | `Given again here` | Secondary: `First given here` |
| `.{ }` without a type | `Cannot tell the type of this struct literal` | On `.{` | Help: `Write the struct's name before '{'` |
| `Name{` not a struct | `'Foo' is not a struct` | On the name | Secondary at its declaration, when there is one |

### 8.4 Warnings and print

| Case | Header | Primary label | More |
| --- | --- | --- | --- |
| Implicit conversion | Warning: `Implicit conversion from i32 to i64` | `Converted to i64` | Help: `Write it explicitly` with the edit `cast(i64, a)`. Note: `Reported because of --warn-implicit-conversions` |
| print of a struct or pointer | `print takes a number or a bool` | `This is Vec3` | |
| Precision on a non-float | `A precision only applies to floats` | On the second argument | Secondary on the first: `This is i32` |
| Negative precision (runtime) | Panic: `Precision cannot be negative` | `This is negative` | |

## 9. Tests and the example

### 9.1 Test files

- `numbers.t` covers:
  - each integer type: printing its minimum and maximum, and wrapping;
  - literal adoption and the default types;
  - hexadecimal and binary literals;
  - widening at each coercion site;
  - `cast` in every direction, saturation included, and `bitcast`;
  - narrow arithmetic (`u8` `200 + 100 > 250` is false);
  - division per type, `INT64_MIN / -1`, and division by zero for `u8` and
    `i64`.
- `bitwise.t`: each operator, precedence (`a & b == 0`, `a | b << 2`),
  shift wrapping, arithmetic right shift, and compound forms.
- `floats.t`: literals, arithmetic, `print` formatting (0.1, 1.0/3.0, whole
  numbers, 1e20, inf, nan, -0.0), precision, the negative-precision panic,
  and division by zero.
- `pointers.t`: `&`, `&mut`, `*`, writes through pointers, pointers to
  pointers, pointer parameters, `*mut` to `*` coercion, and pointer
  equality.
- `structs.t`: declarations in any order, nested structs, the three literal
  forms, field access through a pointer, field assignment, pass and return
  by value, empty structs, and pointer fields.
- `warnings.t`: `--warn-implicit-conversions` at each site, warnings-only
  output and its summary, warnings plus errors, `--warnings-as-errors`, and
  color.
- `order.t`, extended: struct literal field order, `*p() = g()`, `x +=
  f(&mut x)`, and `p.x + f()` where `f` changes `p.x`.
- Every message in section 8 goes in the test file for its feature, each
  with its full output.

Existing tests change where this milestone changes behavior: `print(true)`
now works, the `&` and `|` lexer helps are gone, the unknown-type note
changed, and the generated C differs. Update them with `dune promote` only
after reading each diff, as before.

The generated C must compile under the test flags. If gcc's
`-Wtype-limits` rejects a legal program such as `x < 0` on a `u8`, add
`-Wno-type-limits` to the test flags rather than changing the language.
Report every flag added.

### 9.2 Example program

`examples/particles.slick` uses every feature:

- `Vec2 :: struct { x, y: f32 }` and a `Particle` holding two `Vec2`s, an
  `id: u8` and `flags: u32`;
- a `step :: fn(p: *mut Particle, dt: f32)` that integrates position;
- bit flags set and tested with `|` and `&`;
- a `u8` counter that wraps;
- an `i64` factorial of 20;
- `cast` between floats and integers;
- `print` with and without precision.

Use step sizes that are exact in binary (0.5, 0.25), so the output does not
depend on rounding. Generate the expected output by running the program and
checking it by hand, then add it as a test next to `fib`.

## 10. Stages

Work on a branch, `milestone-1`. After each stage, `dune build`, `dune
test`, `CC=clang dune test` and `dune build @fmt` must pass. Do not commit
until the programmer asks.

1. **The new `ty`.** Change `ty` and `mismatch`, and add `int_lit`, without
   new syntax yet. Everything still compiles to the same C.
2. **Integer types.** Lexer values and prefixes, type names, literal typing
   with expected types, range checks, `coerce` and widening, binary operator
   unification, narrow-type casts in C, division helpers per type, and
   `print` for integers and `bool`.
3. **`cast` and `bitcast`** between integer types. Floats come in stage 5.
4. **Bitwise operators**, the new precedence, and compound assignments.
5. **Floats**: literals, `f32` and `f64`, arithmetic, float casts and
   `bitcast`, `print` formatting and precision.
6. **Warnings**: `options.ml`, the two flags, warning counts and summaries,
   and the conversion warning.
7. **Pointers**: type syntax, `&`, `&mut`, `*`, places, mutability errors,
   assignment through pointers, and evaluation order.
8. **Structs**: declarations, cycles, C ordering, literals, `.{ }`, field
   access and assignment, zero values, and the pointer-field rule.
9. **Finish**: the example program, `README.md` (the status, a feature list
   for structs, pointers and the numeric types, and the new flags), the
   design doc updates (section 6), and a final pass over section 8.

## 11. Pitfalls

- **Polymorphic `=` on types.** It is safe only while `ty` holds no records
  (4.2). Do not add any.
- **C promotions.** Section 5.2's invariant is the defense. When a test
  shows an unexpected wraparound difference, look there first.
- **`INT64_MIN` and `UINT64_MAX` literals.** OCaml's `int` is 63 bits. Keep
  literal values in `Int64.t` from the lexer to the emitter, and never
  convert them through `int`.
- **Float text.** Emit float literals from the source text, not from an
  OCaml float. `Printf "%f"` loses digits, and decimal to double to float
  can round twice.
- **The `Name {` ambiguity.** Struct literals are off in conditions (D5).
  Make sure the flag is restored on every path out of the condition parser,
  including error recovery.
- **Warning-only runs.** `stop_if_errors` must still print the warnings and
  the warnings summary when there are no errors.
