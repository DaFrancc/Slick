Command-line handling: usage errors exit with 2, compile errors with 1, and a
C compiler failure with 3.

  $ export SLICK_CFLAGS="-Wall -Wextra -Werror -Wno-unused -Wno-tautological-compare"

No arguments, an unknown command, or a missing file name prints the usage.

  $ slick
  usage: slick build FILE [-o OUT] [--emit-c]
         slick run FILE
  [2]

  $ slick frobnicate x.slick
  slick: unknown command 'frobnicate'
  usage: slick build FILE [-o OUT] [--emit-c]
         slick run FILE
  [2]

  $ slick run
  slick: missing input file
  usage: slick build FILE [-o OUT] [--emit-c]
         slick run FILE
  [2]

  $ slick build
  slick: missing input file
  usage: slick build FILE [-o OUT] [--emit-c]
         slick run FILE
  [2]

The input must exist and be a .slick file.

  $ slick run nope.slick
  slick: cannot find 'nope.slick'
  [2]

  $ touch notes.txt
  $ slick build notes.txt
  slick: 'notes.txt' is not a .slick file
  [2]

Bad options.

  $ cat > hello.slick <<'EOF'
  > main :: fn() { print(5); }
  > EOF

  $ slick build hello.slick -o
  slick: '-o' needs a file name
  [2]

  $ slick build hello.slick --fast
  slick: unknown option '--fast'
  [2]

  $ slick run hello.slick extra
  slick: unexpected argument 'extra'
  [2]

  $ slick run hello.slick -o out
  slick: '-o' only works with 'slick build'
  [2]

  $ slick run hello.slick --emit-c
  slick: '--emit-c' only works with 'slick build'
  [2]

  $ slick build hello.slick other.slick
  slick: unexpected argument 'other.slick'
  [2]

`build` writes an executable named after the source file, in the current
directory.

  $ slick build hello.slick
  $ ./hello
  5

  $ rm hello
  $ mkdir sub
  $ cp hello.slick sub/
  $ slick build sub/hello.slick
  $ ./hello
  5

`-o` picks the output name.

  $ slick build hello.slick -o other
  $ ./other
  5

`run` builds to a temporary file, runs it, and passes on its exit code.

  $ slick run hello.slick; echo "exit $?"
  5
  exit 0

`--emit-c` prints the C instead of compiling it, and that C is a complete
program.

  $ slick build hello.slick --emit-c > hello.c
  $ cc -std=c11 -fwrapv hello.c -o fromc
  $ ./fromc
  5

A compile error exits with 1 and writes no executable.

  $ cat > broken.slick <<'EOF'
  > main :: fn() { print(1) }
  > EOF
  $ slick build broken.slick
  broken.slick:1:24: error: expected ';' at the end of this statement
  [1]
  $ test -e broken || echo "no executable"
  no executable

If the C compiler rejects the generated code, that is a compiler bug: exit
with 3 and keep the C file.

  $ CC=false slick build hello.slick 2> err; echo "exit $?"
  exit 3
  $ sed 's|/[^ ]*\.c$|FILE.c|' err
  slick: internal error: the C compiler rejected the generated code; it was kept at FILE.c
  $ test -f "$(grep -o '/[^ ]*\.c$' err)" && echo "kept"
  kept
