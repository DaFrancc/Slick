# Milestone 0.5 implementation plan: diagnostics

Plan for the executing agent. Read `Slick Design Decisions.md` first,
especially the Diagnostics section; it is the source of truth. Then read the
Milestone 0 plan (`plans/milestone-0.md`) for the conventions this one keeps:
OCaml style (section 7), tests (section 9) and working rules (section 11).

The language does not change in this milestone. Every program that compiles
today compiles the same way and produces the same C. Only what the compiler
says about broken programs changes.

## 1. What gets built

Diagnostics in the style of Rust's:

1. **Spans.** Every error knows where its problem starts and ends.
2. **Labels.** A primary underline (`^^^`) and secondary ones (`---`) that
   point at related code, each with a short text.
3. **Help and notes.** A suggested fix where one is clear, shown as the edited
   source line, and notes that explain a rule.
4. **A renderer.** Source excerpts with line numbers, in color when writing
   to a terminal.
5. **Several errors per run.** The lexer and parser recover and keep going.
   The checker runs when there are no syntax errors, and it reports every
   type error without follow-on errors.
6. **Sentence case** for every message the compiler, the runtime and the
   command line print.

### Done when

1. `dune build` and `dune test` pass with no warnings, and `dune build @fmt`
   reports nothing.
2. Every message in section 6 renders as specified there and has a test that
   shows its full output.
3. A file with several independent errors reports all of them, each once,
   followed by a summary line with the right count.
4. No input makes the compiler loop forever or crash with an OCaml exception.
   A test feeds it garbage to check this.
5. Color appears with `--color=always`, never with `--color=never` or
   `NO_COLOR`, and by default only when stderr is a terminal.
6. Runtime panics show the source excerpt.
7. `README.md` shows the new error format.

## 2. Output format

### 2.1 One diagnostic

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
```

Line by line:

- **Header:** `Error: <message>`. Later severities are `Warning`; none exist
  yet, but the data model has them.
- **Location:** `<pad>--> <path>:<line>:<col>`, the start of the primary
  label. `<pad>` is as many spaces as the gutter is wide.
- **Gutter:** the line numbers are right-aligned in a column as wide as the
  largest line number shown anywhere in this diagnostic, including its helps.
  Then a space and `|`. Empty gutter lines (`<pad> |`) open and close the
  excerpt.
- **Source lines:** only lines that carry a label are shown, in line order.
  When two shown lines have exactly one line between them, show that line
  too. When the gap is larger, show `...` in place of the line number, with
  no `|`.
- **Underline rows:** under each source line, one row per label on that
  line, in column order. A row has spaces up to the label's start column,
  then `^` (primary) or `-` (secondary) for each character of the span, then
  a space and the label text. A label may have no text.
- **Zero-width spans** (a point between characters, like "just after this
  token") render as one marker character at that column.
- **Spans across lines** underline from their start to the end of their first
  line, and the label goes there.
- **Notes:** `Note: <text>`, after the excerpt, one line each, no source.
- **Helps:** `Help: <text>`. A help with edits is followed by the edited line
  or lines, framed with gutter lines like the excerpt. Under each edit, `+`
  marks inserted text and `~` marks text that replaced something. A deletion
  shows the original line with `-` under the removed text.

Order: header, location, excerpt, then notes, then helps.

A diagnostic with no span (only "No 'main' function found") has a header,
` --> <path>`, and its notes and helps.

### 2.2 A whole run

Diagnostics are separated by one blank line. After the last one, if there
were errors:

```

Error: Could not compile 'game.slick' due to 2 errors
```

It says `due to 1 error` for one. Compile errors exit with 1, as before.

### 2.3 Columns

Columns count characters, not bytes: a UTF-8 sequence is one column. When
showing a source line, a tab becomes four spaces, and underline positions
shift to match. Line and column numbers in the `-->` line are 1-based and
count characters, with a tab as one. Only comments can contain non-ASCII
text today, but strings will soon.

### 2.4 Color

| Part | Style |
| --- | --- |
| `Error` | bold red |
| `Warning` | bold yellow |
| `Note` | bold green |
| `Help` | bold cyan |
| Header message | bold |
| Gutter, line numbers, `-->`, `...` | bold blue |
| Primary underline and its label | bold, in the severity's color |
| Secondary underline and its label | bold blue |
| `+` and `~` in helps, and the text they mark | green |
| `-` in helps | red |

Plain ANSI SGR codes (`\027[1;31m` and so on), reset with `\027[0m` after
each colored piece. Source text itself is never colored.

When to color:

1. `--color=always` or `--color=never`, if given, decides. `--color=auto` is
   the default. Any other value is a usage error.
2. Otherwise, a non-empty `NO_COLOR` turns color off.
3. Otherwise, color is on if stderr is a terminal. Use `Unix.isatty
   Unix.stderr`. This makes `unix`, which ships with OCaml, the only library
   dependency; use it for nothing else.

The flag works with `build` and `run`.

### 2.5 Sentence case

- Every header, label, note and help starts with a capital letter.
- After a colon, the text continues in lower case: `Cannot assign to
  'count': it was declared without 'mut'`.
- A single sentence has no final period. When a note or help needs two
  sentences, both end with a period.
- Names and code are quoted with single quotes: `'count'`, `'x != 0'`. Type
  names are not quoted: `found i32 and bool`.

## 3. Data model

In `src/diag.ml`:

```ocaml
type span = {
  file : string;
  start_line : int; start_col : int;   (* 1-based, in characters *)
  end_line : int; end_col : int;       (* exclusive; equal to start for a point *)
}

type severity = Error | Warning

type label = { l_span : span; l_text : string; l_primary : bool }

(* Replaces the text in e_span with e_text. An empty span inserts. *)
type edit = { e_span : span; e_text : string }

type help = { h_text : string; h_edits : edit list }

type diagnostic = {
  severity : severity;
  message : string;
  labels : label list;        (* exactly one primary, unless there is no span *)
  notes : string list;
  helps : help list;
  file : string;              (* for diagnostics with no span *)
}
```

- Small builder functions make the call sites short: `error span msg
  primary_text`, then `with_label`, `with_note`, `with_help`, each returning
  a new record.
- A sink collects diagnostics: `report d` appends to it and counts errors;
  `error_count ()` reads the count. A module-level record holding a mutable
  list and count is fine. No exceptions.
- The renderer is a separate module, `src/render.ml`: `render source color d
  : string` and `summary path count color : string`. It needs the source
  text, which the driver gives it as an array of lines.
- Keep `Diag.fatal` working during the conversion (section 8, stage 2), then
  delete it.

## 4. Spans in the syntax tree

`Token.t` already has `loc` and `end_loc`. Turn those into one `span` field.
Then carry spans through the AST, replacing `loc` fields:

- `expr.span`: the whole expression, from its first token to its last. A
  parenthesized expression's span includes the parentheses.
- `binary.op_span`, `call.callee_span`, `call.args_span` (from `(` to `)`).
- `type_ann.t_span`.
- `stmt.sspan`: the whole statement, including its `;`.
- `decl`: `d_name_span`, plus `d_colon_eq_span` (the `:=` token, when the
  form uses it) and `d_colon_span` (the `:`), which the 'mut' suggestion
  needs.
- `assign.a_op_span`.
- `param.p_span` (the name) and the span of its type.
- `func`: `f_name_span`, `params_span` (from `(` to `)`), the return type's
  span, and `body.close_span` (the final `}`).
- `return`: the `return` keyword's span.
- `symbol.sym_span`: where it was declared, which secondary labels point at.

## 5. Several errors per run

### 5.1 Lexer

The lexer reports and keeps going:

- Unexpected character: report it, skip it. For a byte of 0x80 or above,
  skip it and every continuation byte (0x80 to 0xBF) after it, so one
  non-ASCII character gives one error.
- Invalid integer literal: report it and produce `Int 0`.
- Literal too large: report it and produce `Int 0`.
- Reserved keyword: report it and produce an `Ident`.

### 5.2 Parser

Recovery without exceptions, by an error flag, as in Wirth's compilers:

- The parser record gets `mutable panicking : bool`.
- When a parse function hits an error and `panicking` is false, it reports,
  sets `panicking`, and returns a placeholder: an `Error_expr` expression, or
  an `Error_stmt` statement. While `panicking` is true, errors are not
  reported and `expect` does not consume tokens.
- After each statement in a block, and after each top-level item, if
  `panicking`: synchronize, then clear the flag.
- Synchronizing skips tokens until just after a `;`, or until (not past) a
  `}`, an `if`, a `while`, a `return`, or end of file. At the top level, it
  stops at an identifier followed by `::`, or end of file, and skips a `}`
  that closes the broken function.
- Every loop in the parser must consume at least one token per iteration
  when `panicking`. Synchronizing must consume at least one token unless it
  is already at a stopping token. This is how the "never loops forever" rule
  is kept; check every loop against it.

### 5.3 Checker

- Run the checker only when the lexer and parser reported nothing, so it
  never sees a broken tree.
- Add `Err` to `ty`. An expression whose error has been reported gets type
  `Err`. Every check accepts `Err` silently, and any operation with an `Err`
  operand has type `Err`. This prevents follow-on errors.
- An unknown type in a declaration still declares the name, with type `Err`.
  Uses of it raise nothing more.
- An undeclared name is reported at every use; each is a different place.
- A function with an unknown parameter or return type still goes in the
  function table, with `Err` in that position.
- Duplicate functions: report the second, keep the first.
- After checking, generate C only if there were no errors.

### 5.4 No cascades

Tests (section 7) cover these specifically:

- `x : Foo = 1;` then `print(x + 1);` gives one error.
- `print(1 + true);` then `y := 1 + true;` gives two errors, not four.
- A missing `)` in a call gives one error, and the next statement still
  parses.
- `fn(a i32)` in a signature gives one error, and the body still parses.

## 6. Message catalog

Every diagnostic, with its new header, its labels (P = primary, S =
secondary), and its notes and helps. The executing agent may improve the
wording within the rules of section 2.5, but should not drop a label or a
help without saying why in the final report.

`A`, `T` and so on stand for the real name or type.

### 6.1 Lexer

| Old message | New header | Labels | Notes and helps |
| --- | --- | --- | --- |
| `'for' is not supported yet` | `'for' is not supported yet` | P keyword: `Reserved for a later version of Slick` | |
| `'0x10' is not a valid integer literal` | `Invalid integer literal '0x10'` | P literal: `Only digits and '_' are allowed` | Note: `Hexadecimal, binary and float literals are not supported yet` |
| `integer literal N does not fit in i32` | `Integer literal N does not fit in i32` | P literal: `Too large` | Note: `An i32 holds values from -2147483648 to 2147483647` |
| `unexpected character 'c'` | `Unexpected character 'c'` | P character, no text | Help for `&`: `Use '&&' for logical and`. For `\|`: `Use '\|\|' for logical or`. For `.` after a digit: `Float literals are not supported yet`. |
| `unexpected byte 0xNN` | `Unexpected byte 0xNN` | P character, no text | Note: `Only comments can contain characters outside ASCII` |

### 6.2 Parser

| Old message | New header | Labels | Notes and helps |
| --- | --- | --- | --- |
| `expected X, found Y` | `Expected X, found Y` | P the found token: `Expected X` | At top level, when Y is `:=`, `:` or `::` followed by something other than `fn`: Note: `Only functions can be defined at the top level for now` |
| `expected ';' at the end of this statement` | `Expected ';' at the end of this statement` | P the point just after the last token, showing the missing `;` in the line, in green, with `+` under it: `Expected ';'` | None: the label already shows the fix (programmer's call, 2026-11-14) |
| (new) a name followed by more on the same line, close to a keyword | `'whle' is not a keyword` | P the name: no text | Help: `Did you mean 'while'?`, replacing it. Without a close keyword: `Expected ';', found X` |
| `expected ')', found X` (closing a call or parentheses) | `Unclosed '('` when X is on a later line or is `;`, `{`, `}` or the end of the file; otherwise `Expected ')', found X` | P the point just after the last token, showing the missing `)` in the line, in green, with `+` under it: `Expected ')'`. In the other case, P X: `Expected ')'` | |
| `comparisons cannot be chained; ...` | `Comparisons cannot be chained` | P second operator: no text. S first operator: no text | Help: `Combine them with '&&'`, inserting `&& <middle operand's source text> ` before the second operator, giving `1 < 2 && 2 < 3` |
| `unexpected ';'` | `Unexpected ';'` | P the `;`: `Not needed here` | Help: `Remove it`, deleting the `;`. After a function body, also Note: `A function definition ends at its '}'` |
| `'x' needs a type or an initial value` | `'x' needs a type or an initial value` | P name: no text | Help: `Give it a type, like 'x : mut i32;', or a value, like 'x : mut = 0;'` (drop `mut` from both if the declaration has none) |
| `cannot assign to this expression` | `Cannot assign to this expression` | P target: `Not a name` | Note: `Only local names can be assigned to` |
| `this expression does nothing; ...` | `This expression does nothing` | P expression: `Its value is not used` | If it is `a == b` with `a` a name: Help: `To assign, use '='`, replacing `==` with `=`. Otherwise: Help: `Only calls can be statements. To keep the value, give it a name: 'value := <source>;'` |

### 6.3 Checker: names and declarations

| Old message | New header | Labels | Notes and helps |
| --- | --- | --- | --- |
| `unknown type 'T'` | `Unknown type 'T'` | P type: `Not a type` | Help, if a known type is close (section 6.7) or T is `int`, `integer` or `boolean`: `Did you mean 'i32'?` replacing it. Otherwise Note: `The types available now are i32 and bool` |
| `undeclared name 'x'` | `Undeclared name 'x'` | P name: `Not declared` | If a symbol named `x` was declared earlier in this function in a block that has ended: S its declaration: `Declared here, in a block that has ended`. Else, if a visible name is close: Help: `Did you mean 'y'?` replacing it |
| `'x' is already declared on line N` | `'x' is already declared` | P new declaration: `Declared again here`. S first declaration: `First declared here` | Note: `Slick does not allow shadowing`. Help: if the first is `mut` and the new one has an initial value: `To change its value, assign to it: 'x = <value>;'`. Otherwise: `Choose a different name` |
| `'f' is already declared as a function on line N` | `'f' is already declared as a function` | P declaration: `Declared again here`. S function name: `Function defined here` | Note: `Slick does not allow shadowing`. Help: `Choose a different name` |
| `'print' is a built-in function and cannot be redeclared` | same, capitalized: `'print' is a built-in function and cannot be redeclared` | P name: no text | Help: `Choose a different name` |
| `function 'f' is already defined on line N` | `Function 'f' is already defined` | P second name: `Defined again here`. S first name: `First defined here` | |
| `'f' cannot be used as a value yet` | `'f' is a function and cannot be used as a value yet` | P name: no text. S function name: `Function defined here` (not for print) | Help: `To call it, add parentheses`, inserting `()` (only if f takes no parameters; otherwise the same help with no edit) |
| `cannot assign to function 'f'` | `Cannot assign to function 'f'` | P name: no text. S function name: `Function defined here` (not for print) | |
| `cannot assign to 'x': it was declared without 'mut' on line N` | `Cannot assign to 'x': it was declared without 'mut'` | P target: `Cannot assign`. S declaration name: `Declared here without 'mut'` | Help: `Declare it with 'mut'`. For `x := v;`, replace `:=` with `: mut =`. For `x : T ...`, insert `mut ` before T. |
| `cannot assign to parameter 'n': ...` | `Cannot assign to parameter 'n': it was declared without 'mut'` | P target: `Cannot assign`. S parameter name: `Declared here without 'mut'` | Help: `Declare it with 'mut'`, inserting `mut ` before its type |

### 6.4 Checker: types and operators

| Old message | New header | Labels | Notes and helps |
| --- | --- | --- | --- |
| `integer literal 2147483648 does not fit in i32` | `Integer literal 2147483648 does not fit in i32` | P literal: `Too large` | Note: `An i32 holds values from -2147483648 to 2147483647` |
| `operator 'op' expects T operands, found A and B` | same, capitalized | P operator: no text. S each operand: its type | |
| `operator '==' needs both sides to have the same type, ...` | same, capitalized | P operator: no text. S each operand: its type | |
| `operator '-' expects i32, found bool` and the same for `!` | same, capitalized | P operator: no text. S operand: its type | For `!` on an i32: Help: `To test for zero, compare it: '<source> == 0'` |
| `operator 'op=' expects i32 operands, found A and B` | same, capitalized | P operator: no text. S target and value: their types | |
| `cannot initialize 'x' of type T with a value of type U` | `Cannot initialize 'x' of type T with a value of type U` | P value: `This is U`. S type: `Declared as T here` | |
| `cannot assign a value of type U to 'x' of type T` | `Cannot assign a value of type U to 'x' of type T` | P value: `This is U`. S declaration: `'x' is declared as T here` (on its type if it has one, else its name) | |
| `condition of 'if' must be bool, found i32` and the same for `while` | `Condition of 'if' must be bool, found i32` | P condition: `Expected bool` | When it is i32: Help: `To test for nonzero, compare it`, inserting ` != 0` after the condition |
| `this expression does nothing` | see 6.2 | | |

### 6.5 Checker: functions and calls

| Old message | New header | Labels | Notes and helps |
| --- | --- | --- | --- |
| `unknown function 'f'` | `Unknown function 'f'` | P name: `Not defined` | If a function or print is close: Help: `Did you mean 'g'?` replacing it |
| `'x' is not a function` | `'x' is not a function` | P name: no text. S its declaration: `'x' is declared here as T` | |
| `'f' expects N arguments, found M` | same, capitalized | P the call's argument list: `Found M` (plural rules as before). S the function's parameter list: `'f' is defined here` (not for print) | |
| `argument N of 'f' expects T, found U` | `Argument N of 'f' expects T, found U` | P argument: `This is U`. S parameter: `Parameter 'p' is declared here` (not for print) | |
| `'f' returns nothing and cannot be used as a value` | `'f' returns nothing, so it has no value to use` | P call: no text. S function name: `Declared here with no return type` (not for print) | |
| `'f' returns T, but this 'return' has no value` | same, capitalized | P `return` keyword: `Needs a value`. S return type: `Declared to return T here` | |
| `'f' returns nothing, but this 'return' has a value` | same, capitalized | P value: no text. S function name: `Declared here with no return type` | Help: `Remove the value, or give 'f' a return type` |
| `'f' returns T, but this 'return' has a value of type U` | same, capitalized | P value: `This is U`. S return type: `Declared to return T here` | |
| `'f' is missing a return: not every path returns a value` | `'f' is missing a return: not every path returns a value` | P final `}`: `Can reach the end without returning`. S return type: `Declared to return T here` | If the body contains a `while` that contains a `return`: Note: `A 'return' inside a 'while' loop does not count, because the loop might not run` |
| `no 'main' function found` | `No 'main' function found` | none | Help: `Add one, like 'main :: fn() { }'` |
| `'main' must take no parameters and return nothing` | same, capitalized | P the parameter list, or the return type if the parameters are empty: no text | Help: `Write it as 'main :: fn() { ... }'` |

### 6.6 Runtime panics

```
3
Panic: Division by zero
 --> panic.slick:4:16
  |
4 |     print(10 / (lives - 3));
  |                ^^^^^^^^^^^ This is zero
```

- `Panic: Division by zero` and `Panic: Remainder by zero`. The location is
  the divisor's start, and the divisor is underlined with `This is zero`.
- The compiler renders the excerpt at compile time (plain, no color) into a
  static string per panic site, and the division helpers take a pointer to it
  instead of a line number. Write the string as a C string literal with the
  existing escaper.
- Exit code 1, and stdout is flushed first, as before.

### 6.7 "Did you mean"

Edit distance (Levenshtein, a plain loop over two arrays). The candidate must
be within `max 1 (String.length name / 3)` edits, and the closest wins; on a
tie, the first declared. Candidates:

- undeclared names: the visible locals and parameters;
- unknown functions: the functions in the file, plus `print`;
- unknown types: `i32` and `bool`.

### 6.8 Command line

| Old | New |
| --- | --- |
| `usage: slick build FILE [-o OUT] [--emit-c]` | `Usage: slick build FILE [-o OUT] [--emit-c] [--color=WHEN]` |
| `       slick run FILE` | `       slick run FILE [--color=WHEN]` |
| `slick: unknown command 'x'` | `Error: Unknown command 'x'`, then the usage |
| `slick: missing input file` | `Error: Missing input file`, then the usage |
| `slick: cannot find 'x'` | `Error: Cannot find 'x'` |
| `slick: 'x' is not a .slick file` | `Error: 'x' is not a .slick file` |
| `slick: '-o' needs a file name` | `Error: '-o' needs a file name` |
| `slick: unknown option 'x'` | `Error: Unknown option 'x'` |
| `slick: unexpected argument 'x'` | `Error: Unexpected argument 'x'` |
| `slick: 'x' only works with 'slick build'` | `Error: 'x' only works with 'slick build'` |
| (new) | `Error: Invalid value 'x' for '--color': use 'auto', 'always' or 'never'` |
| `slick: internal error: ...` | `Error: Internal compiler error: the C compiler rejected the generated code`, then `Note: The generated C was kept at <path>`, then `Note: This is a bug in slick` |

Command-line errors are colored by the same rules, with `Error` in bold red.
Usage errors still exit with 2, and the internal error with 3.

## 7. Tests

The rules from the Milestone 0 plan stand: tests first, expected output typed
by hand, and no `dune promote` except for a diff read line by line.

- **Existing tests:** every compile-error expectation becomes the full
  multi-line output, including the summary line. Each one changes exactly
  once, in stage 3. The tests run with color off: stderr is not a terminal
  under cram, and each test file also exports `NO_COLOR=1`.
- **`test/render.t`** (new) covers the renderer:
  - a two-digit line number widening the gutter, with a secondary label on
    line 9 and the primary on line 10;
  - one line between two labels shown, and a larger gap shown as `...`;
  - two labels on the same line;
  - a tab before the span, and a comment with non-ASCII text before a
    later error line;
  - a span that crosses lines;
  - each kind of edit: insertion `+`, replacement `~`, deletion `-`;
  - `--color=always` piped through `cat -v` to show the escape codes,
    `--color=never`, `NO_COLOR=1` with `--color=auto`, and an invalid
    `--color` value.
- **`test/recovery.t`** (new) covers section 5:
  - three independent errors in different functions all reported, with
    `due to 3 errors`;
  - two syntax errors in one function both reported;
  - a syntax error and a type error in one file: only the syntax error is
    reported, because the checker does not run;
  - the four no-cascade cases in 5.4;
  - garbage input (`) } ; :: fn fn ( -> { ) ;;; @@ 12abc`) finishes with
    errors, and no OCaml exception or hang;
  - lexer recovery: two bad characters and a bad literal on different lines,
    all reported.
- **"Did you mean"**: a close local, a close function, `prnt` for print,
  `i23` and `int` for i32, and a name too far from anything (no help).
- **Panics**: the existing panic tests, updated to the new format.

## 8. Stages

Finish and verify one stage before starting the next. The suite stays green
at every stage.

### Stage 1: spans

Replace locations with spans in tokens, the AST and symbols (section 4). No
output changes: the old messages use the span's start. The whole existing
suite passes unchanged, and that is the test for this stage.

### Stage 2: data model and renderer

Write `Diag` (section 3) and `Render`. Add `test/render.t`, using two or three
real errors converted to the new format to drive it. The rest of the compiler
still uses `Diag.fatal`, unchanged. Add the summary line and `--color` with
`NO_COLOR` and terminal detection here too.

### Stage 3: convert every message

Go through section 6.1 to 6.5 one test file at a time: change the messages
that file covers, then its expectations, then run it. Each message is
reported and then the compiler exits at once (one error per run still).
Delete `Diag.fatal` at the end.

### Stage 4: panics and the command line

Sections 6.6 and 6.8.

### Stage 5: several errors per run

Section 5: lexer, parser, checker, in that order, with `test/recovery.t`
written before each part.

### Stage 6: "did you mean"

Section 6.7.

### Stage 7: finish

- Sweep: every `Diag.report` call has a test showing its full output.
- Check every parser loop against the progress rule in 5.2.
- `dune fmt`, `dune build` from clean with no warnings, and the full suite
  with `CC=clang` as well as the default.
- Update `README.md`: replace the plain error example with the new format.

## 9. Final report

1. Whether each "done when" item holds, with evidence.
2. Any label, help or note from section 6 that was dropped or changed, and
   why.
3. Anything skipped or left failing.
4. Notes for Milestone 1. Known already: struct literals make `if x {`
   ambiguous, and the parser's recovery will need `.` and `{` handling once
   field access and struct literals exist.
