# Slick: Design Decisions

Nov 13, 2026 · @Francisco

## Overview

Slick is a hobby systems language for game development, built for the fun of it. The target feel is a cleaner C with Odin-style ergonomics and Jai-style compile-time power.

Every section records decisions that are locked. Anything still undecided lives in Open questions at the end.

Source files use the `.slick` extension, matching the language and the toolchain command `slick` (`slick build main.slick`, `slick run`).

## Declarations and syntax

Declarations are name-first (Jai/Odin style), and functions use `fn`.

```
MAX    :: 1024                     // compile-time constant
count  := 0                        // immutable, inferred type
score  : mut = 0                   // mutable, inferred type
health : mut f32 = 100             // mutable, explicit type
Vec3   :: struct { x, y, z: f32 }
add    :: fn(a, b: Vec3) -> Vec3 { ... }
```

- Errors name the declaration kind, e.g. `cannot assign to 'count': it was declared without 'mut' on line 3`.
- `_` discards: an ignored return value (`q, _ := div_mod(17, 5)`), a catch-all `match` arm, an unused parameter, or an explicit `_ = save_game()` on a `#must_use` value.
- `_` is also a digit separator in number literals: `1_000_000`, `0xFF_FF_00_00`.

Dot-call syntax is sugar for any function whose first parameter fits (UFCS). There are no methods declared inside types.

```
enemies.append(e)     // rewritten to append(&mut enemies, e)
boss := pool.get(h)   // rewritten to get(&pool, h)
```

Tradeoff accepted: the compiler adds `&` or `&mut` automatically, so a dot call can mutate without `&mut` at the call site.

Everything is zero-initialized by default; `---` opts out for hot paths. Struct literals use named fields with `=`.

```
pos : mut Vec3                       // {0, 0, 0}
buf : mut [65536]u8 = ---            // deliberately uninitialized

t := Turret{ owner = &player }       // omitted fields are zeroed
p := Vec3{ x = 1, y = 2, z = 3 }
v := Vec3{ 1, 2, 3 }                 // positional only when every field is given
```

- `=` instead of `:` in literals, because `:` already means "has type".
- Exception to zeroing: structs with non-null pointer fields must be initialized explicitly.

When the type is known from context, a literal can drop it with `.{ }`, matching `.Ok(v)` for enum variants: `spawn(.{ 1, 2, 0 }, .{ 0, 5, 0 })`, `t : Turret = .{ owner = &player }`. Only allowed where the type is unambiguous.

A function pointer's type is the `fn` signature itself, with no `*`: a value of that type already holds the address of the code.

```
Easing :: fn(t: f32) -> f32

ease := ease_out_cubic            // fixed
curve : mut Easing = ease_linear  // mut only if it will be repointed
curve = ease_out_cubic

on_death : ?fn(e: *mut Enemy)     // nullable, like any ?T
Button :: struct { label: string, on_click: fn() }
```

- Compiles to a plain C function pointer. Non-null by default.
- `*Easing` is a pointer to a variable holding a function pointer, rarely needed.

No closures. Anonymous functions are plain unnamed functions and can't capture locals. Extra data travels through a normal generic parameter, so copy versus pointer is chosen by what you pass (Zig's approach):

```
count_if :: fn(xs: []$T, ctx: $C, pred: fn(e: *T, ctx: C) -> bool) -> i64 { ... }

threshold := 50
weak := count_if(enemies[:], threshold,
    fn(e: *Enemy, t: i32) -> bool { return e.hp < t })

kills : mut i32 = 0
for_each(enemies[:], &mut kills,
    fn(e: *Enemy, k: *mut i32) { if e.hp <= 0 { *k += 1 } })
```

C++/Rust-style closures (a struct of captures plus a function) can be layered on later through generics without breaking this.

**Attribute placement.** Attributes come after everything except the body; with no body, at the end. Directives like `#run` stand alone wherever a statement or value can go.

```
move   :: fn(q: Query(*mut Position), dt: f32) #system #after(input) { ... }
Result :: enum($T: type, $E: type) #must_use { Ok(T), Err(E) }
MAX    :: 1024 #pub
frames : mut u64 = 0 #pub
Player :: struct #pub { pos: Vec3, _net: NetState #no_serialize }

#run ecs.build_schedule()
SIN_TABLE :: #run make_sin_table()
```

## Primitive types

All numeric types are sized, and there is no default `int` alias.

| Kind | Types |
| --- | --- |
| Signed integers | `i8` `i16` `i32` `i64` |
| Unsigned integers | `u8` `u16` `u32` `u64` |
| Floats | `f32` `f64` |
| Boolean | `bool` |

An integer literal with nothing constraining it defaults to `i32`: `count := 0` is an `i32`. When context gives a type, the literal adopts it: `x : u8 = 5` and `f(5)` with an `i64` parameter both work.

A float literal with nothing constraining it defaults to `f32`: `speed := 4.5` is an `f32`. Context can still make it an `f64`: `t : f64 = 4.5`.

Numbers convert implicitly only when nothing can be lost (`i32` to `i64`, `f32` to `f64`). Anything that could truncate, flip sign, or lose precision needs an explicit cast.

```
a : i32 = 5
b : i64 = a      // ok: lossless widening
c : i16 = a      // error: needs an explicit cast
d : u32 = a      // error: could lose the sign
```

A compiler flag, `-warn-implicit-conversions`, warns on every implicit conversion, including lossless ones.

Explicit casts use a builtin function, chosen because every cast is easy to grep for: `c := cast(i16, a)`.

`cast` converts the value (`cast(u32, 1.5)` is `1`). `bitcast` reinterprets the raw bits and only works between types of the same size: `bitcast(u32, 1.5)` is `0x3FC00000`.

## Arrays and slices

The compiler knows only fixed arrays and slices. Everything growable is a standard-library generic type.

```
verts : [4]Vec3              // fixed array, reads "array of 4 Vec3"
grid  : [16][16]Tile

all := verts[:]              // []Vec3, length 4
mid := verts[1:3]            // []Vec3, elements 1 and 2
n   := mid.len               // i64

sum :: fn(xs: []f32) -> f32 { ... }

enemies : List(Enemy)        // growable, library type
```

- A slice is a pointer plus a length, with `.ptr` and `.len` fields. `.len` is `i64` so `xs.len - 1` never wraps on an empty slice.
- On a fixed array, `.len` is a compile-time constant.
- `[]T` is read-only; `[]mut T` allows writes, following the same rule as `*mut T`.
- Indexing is bounds-checked in debug builds.
- Growable containers are library types: `List(T)`, `StableList(T)` (never moves on growth), `Pool(T)` (generational handles).

Indexing a library type calls a function marked `#operator([])`, found by normal lookup (no traits needed):

```
hp := enemies[3].health       // calls the read-only [] function
enemies[3].health -= 10       // calls the mutable [] function

list_get     :: fn(l: *List($T), i: i64) -> *T #operator([]) { ... }
list_get_mut :: fn(l: *mut List($T), i: i64) -> *mut T #operator([]) { ... }
```

When the expression is written to, the compiler picks the `[]` function that takes and returns `*mut`. Name-based protocols like `next` can become traits later without breaking code.

## Operators

Operators are overloaded by marking an ordinary function with `#operator(...)`. Nothing becomes an operator unless it says so, and every overload is greppable.

```
vec3_add :: fn(a, b: Vec3) -> Vec3 #operator(+) { ... }
mat4_mul :: fn(a: Mat4, b: Vec4) -> Vec4 #operator(*) { ... }

c := a + b
```

- Overloadable: `+ - * /`, comparisons (`==`, `<`, and so on), and `[]`.
- `Vec3`, `Mat4`, `Quat` and other math types are library types built this way, not built into the compiler.

Swizzles are ordinary library functions called with dot syntax, so they need no language feature: `xy :: fn(v: Vec3) -> Vec2 #pub { return .{ v.x, v.y } }`, used as `pos.xy()`. The full set gets generated with `#run` once it exists.

## Strings

There is one `string` type: a read-only slice of UTF-8 bytes, not null-terminated. Ownership is tracked through allocators, like any other slice.

```
name : string = "Archer"
name.len                         // 6, in bytes
name[0:3]                        // "Arc", no copy

a := "Line one\nLine two"        // C-style escapes
b := "Caf\u{E9}"                 // unicode escape
c := `C:\games\assets\tree.glb`  // raw string, no escapes

msg := format("HP: {}", hp)      // allocates from context.allocator

sb : mut = StringBuilder{}        // library type for building piece by piece
sb.write("Score: ")
s := sb.to_string()
```

- No separate owned string type. UI and debug strings typically use the temp allocator and are freed at end of frame.
- Backtick raw strings can span lines, which suits embedded GLSL and test data.
- `cstring` (null-terminated) exists for C interop, with conversions both ways.

## Mutability and pointers

Everything is immutable by default: forgetting `mut` is a compile error, while forgetting `const` would be a silent bug.

**The one rule:** `mut` modifies whatever comes right after it.

```
health : mut f32          // a mutable f32
p      : *mut Enemy       // pointer to a mutable Enemy
q      : mut *Enemy       // repointable pointer to a read-only Enemy
r      : mut *mut Enemy   // both
```

- A leading `mut` is only allowed where a variable is declared: locals, parameters, loop variables. Struct fields take their mutability from the struct they live in.
- `*T` is the pointer type. `&x` gives a `*T`, and `&mut x` gives a `*mut T` (`x` must be `mut`).
- `foo : *mut i64 = &mut source` is the full form; `foo := &mut source` infers the same type.
- Field access auto-dereferences (`p.health`). Writing through a plain pointer uses prefix `*`: `*foo = 10`.
- Pointers are non-null by default. `?*T` and `?*mut T` may be null and must be unwrapped with `if t := target { ... }`.
- `?` applies to any type: `?i32` compiles to a value plus a has-value flag, while `?*T` stays a plain pointer.
- Structs with non-null pointer fields must be initialized explicitly: `Turret{ owner = &player }`.
- There is no borrow checker and no aliasing guarantee: two `*mut` pointers to the same value are allowed.
- C interop: `*T` maps to `const T*`, `*mut T` to `T*`.

No arithmetic on `*T`: a pointer points at one thing, and slices handle walking through memory. Raw offsets use an explicit, greppable builtin: `next := ptr_add(p, 16)`. Pointers to pointers need no special rule (`*mut *mut Node`).

## Generics

`$` marks anything known at compile time, and generics take both types and values.

```
max    :: fn(a, b: $T) -> T { ... }       // T inferred from arguments
zeroed :: fn($T: type) -> T { ... }       // T passed explicitly: zeroed(Vec3)

Pool :: struct($T: type, $N: i64) {
    items: [N]T,
    count: i64,
}
bullets: Pool(Bullet, 256)

push :: fn(p: *mut Pool($T, $N), item: T) { ... }   // T and N matched from the pool's type
```

- Generic structs are instantiated with plain parentheses, so there is no `a < b > c` ambiguity.
- Compiled by monomorphization: one copy per instantiation (`max__i64`, `max__f32`), cached and reused.
- Constraints are checked after instantiation. Errors show both the location inside the generic and the call site. Declared constraints can be added later.

## Tagged unions

Variants are declared inline, and each variant is also a usable type.

```
Event :: enum {
    Damage { target: Handle(Enemy), amount: f32 },
    Spawn  { kind: EnemyKind, pos: Vec3 },
    Quit,
}

apply_damage :: fn(d: Event.Damage) { ... }

match ev {
    .Damage(d) => apply_damage(d),
    .Spawn(s)  => spawn(s.kind, s.pos),
    .Quit      => running = false,
}
```

- `match` is exhaustive: a missing variant is a compile error.
- A plain enum is the case where no variant carries data: `EnemyKind :: enum { Grunt, Archer, Boss }`.

## Error handling

Three tools, each with one job: multiple returns for several outputs, `Result` for failures, `?T` for values that might be missing.

```
div_mod :: fn(a, b: i64) -> (i64, i64) { ... }
q, r := div_mod(17, 5)

Result :: enum($T: type, $E: type) #must_use { Ok(T), Err(E) }

make_mesh :: fn(path: string) -> Result(*mut Mesh, LoadError) {
    m := alloc(Mesh)
    errdefer free(m)               // runs only on an error exit

    m.verts = try load_verts(path) // on Err, return it immediately
    return .Ok(m)
}
```

- Multiple returns are destructured only, not first-class tuples. The C backend returns a generated struct.
- `Result` is a normal standard-library enum. The compiler knows it in one place: `try`. A general `#try(ok = Ok, err = Err)` attribute can come later.
- `try` also works on `?T`, returning early on null.
- `#must_use` is a general attribute. Dropping a `Result` is a compile error unless discarded explicitly with `_ =`.
- No `Option` enum (`?T` covers it) and no Odin-style `or_return`.
- `errdefer` is only allowed in functions that return a `Result`.
- Bugs, as opposed to expected failures, use `assert` and crash loudly.

A function that returns nothing omits `->`. Where a type is still needed, the name is `void`, and a `void` payload can be left off:

```
save_game :: fn(path: string) -> Result(void, SaveError) {
    try write_file(path, data)
    return .Ok
}
```

## Control flow

There are separate loop keywords for readability, and extras like enumerating are library functions rather than syntax.

```
for i in 0..10 { }                     // 0 to 9
for i in 0..=10 { }                    // 0 to 10
for e in enemies { }                   // e is immutable
for e in &mut enemies { e.health -= 10 } // e: *mut Enemy, modifies the real enemies
for i, e in enumerate(enemies) { }     // library iterator
while hp > 0 { }
loop { }                               // infinite, exit with break

outer: for row in grid {
    for cell in row {
        if cell.blocked { continue outer }
    }
}
```

- Iterating a pointer to an array yields pointers to its elements, with the same mutability.
- There is no mutable-copy loop form. Write `c : mut = e` inside the loop instead.
- Iterators: `for` works on ranges, arrays and slices directly, and on anything with a `next` function whose last return value is a `bool` meaning keep going. `enumerate`, `zip`, `pool.alive()` and ECS queries are ordinary library code.
- `defer` runs at scope exit on every path, in reverse order. `errdefer` is covered under Error handling.

## Memory

Code gets memory from an implicit context with a sensible default, and overriding it is the rare path.

```
spawn_wave :: fn() {
    enemies : mut = make(List(Enemy), 64)    // uses context.allocator
}

context.allocator = level_arena              // override for a whole call tree
load_level("cave.slick")

particles : mut = make(List(Particle), 256, context.temp_allocator)   // override for one container
```

- `context.allocator` defaults to a general-purpose heap. The context compiles to a hidden pointer parameter; C-facing functions are marked `#c_call` to leave it out.
- A built-in `temp_allocator` is reset once per frame.
- Containers capture their allocator at creation and use it for every grow and free, even if the context changes later.
- Library authors can pin their own allocator when they know better.
- Dangling pointers: raw pointers stay unchecked. The standard library ships `StableList(T)` (virtual-memory backed, never moves on growth) and `Pool(T)` with generational handles (`pool.get(h)` returns `?*T`). Debug builds poison freed memory.

## Modules

A folder is a module: every file in it shares one namespace. Declarations are private by default and exposed with `#pub`.

```
import "engine/math"

p := math.lerp(a, b, 0.5)

// inside engine/math/
lerp :: fn(a, b: f32, t: f32) -> f32 #pub { ... }   // visible to importers
clamp_internal :: fn(x: f32) -> f32 { ... }        // module-only
```

- Private by default for the same reason as immutable by default: a missing `#pub` is a loud error, a missing `#private` is a silent API leak.
- `#pub` goes after the declaration, like other attributes, so the name stays first.

Struct fields follow their struct, all or nothing: a `#pub` struct has every field visible, and there is no per-field `#private`.

Internal fields use a naming convention instead of a feature: an `_` prefix means "don't touch without good reason" (`_mixer: *mut Mixer`). The compiler warns, not errors, when another module accesses an `_`-prefixed field. Unlike Rust, `_name` does not mean "unused"; bare `_` covers that.

A module is named after its folder; `as` renames it: `import "thirdparty/fastmath" as fm`. There is no import-everything form, so every external name keeps its module prefix.

## Compile-time features and ECS

ECS ships in the standard library, built on general compile-time features rather than baked into the compiler.

```
Position :: struct #component { p: Vec3 }
Velocity :: struct #component { v: Vec3 }

move :: fn(q: Query(*mut Position, *Velocity), dt: f32) #system #after(input) {
    for e in q { e.pos.p += e.vel.v * dt }
}

#run ecs.build_schedule()
```

- The language provides attributes, compile-time reflection, and `#run` (arbitrary compile-time execution).
- `build_schedule` finds every `#system`, reads its `Query` types for reads and writes, rejects cycles with a compile error, and generates the schedule as code.
- Queries reuse pointer mutability (`*mut` for writes, `*` for reads) instead of separate keywords.
- Bridge until `#run` exists: the compiler dumps attributes and type info as JSON, and the existing Python scheduler consumes it.

SoA layouts are a library type generated with `#run`, not a compiler feature. `Soa(T, N)` reads `T`'s fields through reflection and generates one array per field. Access puts the field first, so the layout is visible: `particles.pos[i] += particles.vel[i] * dt`. Available once `#run` exists.

## Compiler implementation

The bootstrap compiler is written in OCaml and emits C. A later compiler will be written in the language itself.

- OCaml for variants, exhaustive `match`, and a garbage-collected AST with no arena bookkeeping.
- Keep the OCaml plain (variants, records, `match`, hash tables; no functors or GADTs) so the self-hosted port is line by line.
- C backend first; a native backend such as RISC-V can come later, with C kept as the reference.
- AI writes the routine parts (lexer, parser, C emission, tests); the interesting parts get written by hand.

Milestones:

0. Minimal Turing-complete core, pushed through the whole pipeline (lex, parse, type-check, emit C, call `cc`): `i32` and `bool`; `:=` and `: mut` declarations with the immutability check; assignment and `+=`; arithmetic, comparison and logical operators; `if`/`else`, `while`; functions with parameters, `return` and recursion; a built-in `print(i32)`. Test program: recursive `fib` printed for 0 to 9.
1. Compile a wider subset to C: structs, pointers, the remaining integer and float types.
2. C interop: call raylib or SDL and get Pong drawing.
3. Signature features: generics, tagged unions, `Result` and `try`, allocator context.
4. Attributes and the JSON reflection dump for the ECS bridge.
5. The deep end: a real IR, `#run`, own codegen, self-hosting.

## Open questions

- [x] The language's name: decided, Slick.
- [x] File extension and CLI command: decided, `.slick` files and the `slick` command.
- [x] Integer literal default: decided, `i32` (see Primitive types).
- [x] Float literal default: decided, `f32` (see Primitive types).
- [x] Implicit numeric conversions: decided, lossless widening only, plus a warning flag (see Primitive types).
- [x] Cast syntax: decided, `cast(T, x)` and `bitcast(T, x)` (see Primitive types).
- [x] Arrays, slices and growable arrays: decided (see Arrays and slices).
- [x] Methods: decided, UFCS dot-call sugar (see Declarations and syntax).
- [x] Strings: decided (see Strings).
- [x] Struct initialization and zero-initialization defaults: decided (see Declarations and syntax).
- [x] Pointer-to-pointer and pointer arithmetic: decided, `ptr_add` only (see Mutability and pointers).
- [x] Function pointers: decided, `fn(...) -> T` is the pointer type (see Declarations and syntax).
- [x] Closures: decided, none; context passed as a generic parameter (see Declarations and syntax).
- [x] "Returns nothing" type: decided, `void`, with `.Ok` standing alone (see Error handling).
- [x] Modules and imports: decided (see Modules).
- [x] Vector and matrix math: decided, library types with `#operator` (see Operators).
- [x] Swizzles: decided, library functions like `v.xy()` (see Operators).
- [x] `#soa` layouts: decided, library `Soa(T, N)` via `#run` (see Compile-time features and ECS).
- [x] Attribute placement: decided (see Declarations and syntax).
